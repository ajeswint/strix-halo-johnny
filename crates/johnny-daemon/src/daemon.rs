//! The daemon's run: wire the two planes together and drain until told to
//! stop. Same order of steps as the Python reader's `do_run`
//! (`docs/tool-install/johnny-m1s2b-reader.py:483-580`).

use std::path::Path;

use crate::control::config::RunConfig;
use crate::control::policy::Policy;
use crate::control::status::{Event, Log};
use crate::data::ring::Ring;
use crate::data::writer::{check_disk_free, check_out_dir, Ports, RotatingWriter};
use crate::data::KernelMaps;
use crate::stop::Stop;
use crate::sys::Sys;

pub const POLL_MS: i32 = 200;
pub const BATCH: usize = 4096;

/// The ring's memory and the maps beside it.
pub struct Attached<M: KernelMaps> {
    pub ring: Ring,
    pub maps: M,
}

fn pump<M: KernelMaps>(
    cfg: &RunConfig,
    policy: &Policy,
    sys: &dyn Sys,
    maps: &M,
    ring: &mut Ring,
    writer: &mut RotatingWriter,
    log: &mut Log,
) -> Result<String, Stop> {
    let start = sys.mono_ns();
    let mut p = Ports { sys, maps, log };
    loop {
        ring.drain(BATCH, policy.on_unknown_version, &mut |raw| {
            writer.sink(raw, &mut p)
        })?;
        writer.flush(&mut p)?;

        if let Some(sig) = sys.stop_signal() {
            return Ok(format!("signal-{sig}"));
        }
        if cfg.max_total_records != 0 && writer.total_records() >= cfg.max_total_records {
            return Ok("max-total-records".to_string());
        }
        let now = sys.mono_ns();
        if cfg.max_total_seconds != 0
            && now.saturating_sub(start) >= cfg.max_total_seconds.saturating_mul(1_000_000_000)
        {
            return Ok("max-total-seconds".to_string());
        }

        // Wait for records, or time out to check rotation and signals.
        maps.wait(POLL_MS);

        // Rotate on age even when no packet arrived.
        if writer.is_open() {
            let elapsed = sys.mono_ns().saturating_sub(writer.file_start_mono());
            if policy.time_rotation_due(elapsed) {
                writer.open_next_file(&mut p)?;
            }
        }
    }
}

/// Validate, attach, drain, close. `attach` opens the pins under `pin_dir`
/// (`bpf::attach` in the daemon).
pub fn run<M: KernelMaps>(
    cfg: &RunConfig,
    sys: &dyn Sys,
    attach: impl FnOnce(&Path) -> Result<Attached<M>, Stop>,
    log: &mut Log,
) -> Result<(), Stop> {
    // Control plane: the operator's limits become the policy.
    let limits = cfg.limits()?;
    let policy = Policy {
        limits,
        on_unknown_version: cfg.on_unknown_version,
    };

    check_out_dir(&cfg.out_dir, sys)?;
    check_disk_free(&cfg.out_dir, &policy, sys)?;

    let Attached { mut ring, maps } = attach(&cfg.pin_dir)?;
    let m2_cfg = maps.read_cfg()?;

    log.emit(&Event::ReaderBegin {
        out_dir: &cfg.out_dir.display().to_string(),
        ring_map_id: maps.ring_map_id(),
        cfg: m2_cfg,
        limits,
        on_unknown_version: cfg.on_unknown_version,
    })?;

    // Data plane.
    let mut writer = RotatingWriter::new(&cfg.out_dir, policy, m2_cfg);
    writer.open_next_file(&mut Ports {
        sys,
        maps: &maps,
        log,
    })?;

    let pumped = pump(cfg, &policy, sys, &maps, &mut ring, &mut writer, log);
    let closed = writer.close_current_file(&mut Ports {
        sys,
        maps: &maps,
        log,
    });
    let reason = match (pumped, closed) {
        (_, Err(e)) => return Err(e),
        (Err(e), Ok(())) => return Err(e),
        (Ok(reason), Ok(())) => reason,
    };

    maps.read_ctl()?;
    log.emit(&Event::ReaderEnd {
        reason: &reason,
        total_files: writer.total_files(),
        total_records: writer.total_records(),
        total_bytes: writer.total_bytes(),
        seq_gaps: writer.seq_gaps(),
        ring_discarded: ring.discarded(),
        unknown_version: ring.unknown_version(),
        backlog: ring.backlog(),
    })
}
