//! The run-file writer: rotation, pruning, and the free-space check, in the
//! Python reader's order (`docs/tool-install/johnny-m1s2b-reader.py:289-474`).
//! Every "should I" is asked of `control::policy`; this module does the I/O.

use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::Write as _;
use std::os::unix::fs::{DirBuilderExt as _, MetadataExt as _, OpenOptionsExt as _};
use std::path::{Path, PathBuf};

use johnny_record_v1::record::{raw_rxq, raw_seq_lo};
use johnny_record_v1::{utc, M2Cfg, RunHeader, SeqGaps, HDR_SIZE, REC_SIZE};

use crate::control::policy::{is_run_file, run_file_name, Policy};
use crate::control::status::{Event, Log, PruneWhy};
use crate::data::KernelMaps;
use crate::stop;
use crate::stop::Stop;
use crate::sys::Sys;

/// Records buffered before a write.
const FLUSH_RECORDS: usize = 256;

/// What the writer reaches outside itself through.
pub struct Ports<'p> {
    pub sys: &'p dyn Sys,
    pub maps: &'p dyn KernelMaps,
    pub log: &'p mut Log,
}

/// The output dir must be a real directory, owned by us, mode 0700.
pub fn check_out_dir(path: &Path, sys: &dyn Sys) -> Result<(), Stop> {
    let shown = path.display();
    if fs::metadata(path).is_err() {
        DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(path)
            .map_err(|e| stop!("out-dir-mkdir-failed {shown} ({e})"))?;
    }
    let st = fs::symlink_metadata(path).map_err(|_| stop!("out-dir-missing {shown}"))?;
    let is_dir = fs::metadata(path).map(|m| m.is_dir()).unwrap_or(false);
    if !is_dir || st.file_type().is_symlink() {
        return Err(stop!("out-dir-not-dir {shown}"));
    }
    if st.uid() != sys.euid() || st.mode() & 0o777 != 0o700 {
        return Err(stop!(
            "out-dir-mode {shown} uid={} mode={:o}",
            st.uid(),
            st.mode() & 0o777
        ));
    }
    Ok(())
}

/// Run files in `out_dir`, oldest first (names sort by their UTC stamp).
pub fn run_files(out_dir: &Path) -> Result<Vec<String>, Stop> {
    let rd = fs::read_dir(out_dir).map_err(|e| stop!("list-failed {} ({e})", out_dir.display()))?;
    let mut names = Vec::new();
    for entry in rd {
        let entry = entry.map_err(|e| stop!("list-failed {} ({e})", out_dir.display()))?;
        if let Some(name) = entry.file_name().to_str() {
            if is_run_file(name) {
                names.push(name.to_string());
            }
        }
    }
    names.sort();
    Ok(names)
}

pub fn check_disk_free(out_dir: &Path, policy: &Policy, sys: &dyn Sys) -> Result<(), Stop> {
    let free = sys
        .free_bytes(out_dir)
        .map_err(|e| stop!("statvfs-failed {} ({e})", out_dir.display()))?;
    policy.disk_ok(free)
}

pub struct RotatingWriter {
    out_dir: PathBuf,
    policy: Policy,
    cfg: M2Cfg,
    file: Option<File>,
    path: String,
    file_bytes: u64,
    file_records: u64,
    file_start_mono: u64,
    buf: Vec<u8>,
    gaps: SeqGaps,
    total_files: u64,
    total_records: u64,
    total_bytes: u64,
}

impl RotatingWriter {
    pub fn new(out_dir: &Path, policy: Policy, cfg: M2Cfg) -> Self {
        RotatingWriter {
            out_dir: out_dir.to_path_buf(),
            policy,
            cfg,
            file: None,
            path: String::new(),
            file_bytes: 0,
            file_records: 0,
            file_start_mono: 0,
            buf: Vec::with_capacity(FLUSH_RECORDS * REC_SIZE),
            gaps: SeqGaps::default(),
            total_files: 0,
            total_records: 0,
            total_bytes: 0,
        }
    }

    pub fn is_open(&self) -> bool {
        self.file.is_some()
    }

    pub fn file_start_mono(&self) -> u64 {
        self.file_start_mono
    }

    pub fn total_files(&self) -> u64 {
        self.total_files
    }

    pub fn total_records(&self) -> u64 {
        self.total_records
    }

    pub fn total_bytes(&self) -> u64 {
        self.total_bytes
    }

    pub fn seq_gaps(&self) -> u64 {
        self.gaps.gaps()
    }

    fn unlink(&self, name: &str, why: PruneWhy, p: &mut Ports<'_>) -> Result<(), Stop> {
        let path = self.out_dir.join(name);
        fs::remove_file(&path).map_err(|e| stop!("prune-failed {} ({e})", path.display()))?;
        p.log.emit(&Event::Pruned { name, why })
    }

    /// Enforce the keep count, then the byte cap. Oldest deleted first.
    fn prune(&self, p: &mut Ports<'_>) -> Result<(), Stop> {
        let files = run_files(&self.out_dir)?;
        let by_keep = self.policy.keep_prune(files.len());
        for name in &files[..by_keep] {
            self.unlink(name, PruneWhy::Keep(self.policy.limits.keep), p)?;
        }
        let rest = &files[by_keep..];
        let mut sizes = Vec::with_capacity(rest.len());
        for name in rest {
            let path = self.out_dir.join(name);
            let meta =
                fs::metadata(&path).map_err(|e| stop!("prune-failed {} ({e})", path.display()))?;
            sizes.push(meta.len());
        }
        let plan = self.policy.cap_prune(&sizes);
        for name in &rest[..plan.delete] {
            self.unlink(name, PruneWhy::Cap(self.policy.limits.dir_cap_bytes), p)?;
        }
        plan.verdict
    }

    pub fn open_next_file(&mut self, p: &mut Ports<'_>) -> Result<(), Stop> {
        self.close_current_file(p)?;

        check_disk_free(&self.out_dir, &self.policy, p.sys)?;
        self.prune(p)?;
        check_disk_free(&self.out_dir, &self.policy, p.sys)?;

        let now_utc = utc::compact((p.sys.real_ns() / 1_000_000_000) as i64);
        let mut idx = 0;
        let mut path = self.out_dir.join(run_file_name(&now_utc, idx));
        while path.exists() {
            idx += 1;
            path = self.out_dir.join(run_file_name(&now_utc, idx));
        }
        let shown = path.display().to_string();

        // O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600.
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .custom_flags(libc::O_NOFOLLOW)
            .mode(0o600)
            .open(&path)
            .map_err(|e| stop!("open-failed {shown} ({e})"))?;
        let start_mono = p.sys.mono_ns();
        let ctl = p.maps.read_ctl()?;
        // mono -> realtime offset: realtime read on both sides of the
        // monotonic read, midpoint.
        let r0 = i128::from(p.sys.real_ns());
        let m = i128::from(p.sys.mono_ns());
        let r1 = i128::from(p.sys.real_ns());
        let offset = ((r0 + r1) / 2 - m) as i64;
        let header = RunHeader::v1(offset, start_mono, self.cfg, ctl);
        file.write_all(&header.encode())
            .map_err(|e| stop!("write-failed {shown} ({e})"))?;

        self.file = Some(file);
        self.path = shown;
        self.file_start_mono = start_mono;
        self.file_bytes = HDR_SIZE as u64;
        self.file_records = 0;
        self.total_files += 1;
        p.log.emit(&Event::FileOpen {
            file: &self.path,
            file_num: self.total_files,
            date_utc: &now_utc,
        })
    }

    pub fn close_current_file(&mut self, p: &mut Ports<'_>) -> Result<(), Stop> {
        if self.file.is_none() {
            return Ok(());
        }
        self.flush(p)?;
        if let Some(file) = self.file.take() {
            file.sync_all()
                .map_err(|e| stop!("fsync-failed {} ({e})", self.path))?;
        }
        self.total_bytes += self.file_bytes;
        p.log.emit(&Event::FileClosed {
            file: &self.path,
            records: self.file_records,
            bytes: self.file_bytes,
        })
    }

    /// Take one record from the ring.
    pub fn sink(&mut self, raw: &[u8; REC_SIZE], p: &mut Ports<'_>) -> Result<(), Stop> {
        let elapsed = p.sys.mono_ns().saturating_sub(self.file_start_mono);
        if self
            .policy
            .must_rotate(self.file.is_some(), self.file_bytes, elapsed)
        {
            self.open_next_file(p)?;
        }

        self.gaps.observe(raw_rxq(raw), raw_seq_lo(raw));
        self.buf.extend_from_slice(raw);
        self.file_records += 1;
        self.total_records += 1;
        self.file_bytes += REC_SIZE as u64;

        if self.buf.len() >= FLUSH_RECORDS * REC_SIZE {
            self.flush(p)?;
        }
        Ok(())
    }

    pub fn flush(&mut self, p: &mut Ports<'_>) -> Result<(), Stop> {
        if self.buf.is_empty() {
            return Ok(());
        }
        let Some(file) = self.file.as_mut() else {
            return Ok(());
        };
        check_disk_free(&self.out_dir, &self.policy, p.sys)?;
        let res = file.write_all(&self.buf);
        self.buf.clear();
        res.map_err(|e| stop!("write-failed {} ({e})", self.path))
    }
}
