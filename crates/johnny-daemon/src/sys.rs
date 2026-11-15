//! The few OS calls the daemon needs besides files and BPF: clocks, free
//! disk space, the effective uid, and stop signals. A trait, so the tests
//! can hold the clock still.

use std::ffi::CString;
use std::io;
use std::os::unix::ffi::OsStrExt as _;
use std::path::Path;
use std::sync::atomic::{AtomicI32, Ordering};

pub trait Sys {
    fn euid(&self) -> u32;
    /// CLOCK_MONOTONIC, ns. The clock `bpf_ktime_get_ns` stamps records with.
    fn mono_ns(&self) -> u64;
    /// CLOCK_REALTIME, ns.
    fn real_ns(&self) -> u64;
    /// Bytes available to unprivileged writers on the filesystem holding `dir`.
    fn free_bytes(&self, dir: &Path) -> io::Result<u64>;
    /// The first SIGTERM or SIGINT received, if any.
    fn stop_signal(&self) -> Option<i32>;
}

pub struct RealSys;

static STOP_SIGNAL: AtomicI32 = AtomicI32::new(0);

extern "C" fn on_stop_signal(sig: libc::c_int) {
    let _ = STOP_SIGNAL.compare_exchange(0, sig, Ordering::SeqCst, Ordering::SeqCst);
}

/// SIGTERM and SIGINT set a flag the drain loop checks (no SA_RESTART, so
/// the poll wakes). SIGXFSZ is ignored so a write past LimitFSIZE fails with
/// EFBIG and becomes a STOP instead of killing the process.
pub fn install_signal_handlers() -> io::Result<()> {
    // SAFETY: sigaction with a zeroed struct and an async-signal-safe
    // handler (one atomic compare-exchange).
    unsafe {
        let mut sa: libc::sigaction = std::mem::zeroed();
        sa.sa_sigaction = on_stop_signal as extern "C" fn(libc::c_int) as libc::sighandler_t;
        libc::sigemptyset(&mut sa.sa_mask);
        for sig in [libc::SIGTERM, libc::SIGINT] {
            if libc::sigaction(sig, &sa, std::ptr::null_mut()) != 0 {
                return Err(io::Error::last_os_error());
            }
        }
        if libc::signal(libc::SIGXFSZ, libc::SIG_IGN) == libc::SIG_ERR {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}

fn clock_ns(clock: libc::clockid_t) -> u64 {
    let mut ts = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    // SAFETY: ts is a valid timespec. These two clocks cannot fail.
    unsafe { libc::clock_gettime(clock, &mut ts) };
    ts.tv_sec as u64 * 1_000_000_000 + ts.tv_nsec as u64
}

impl Sys for RealSys {
    fn euid(&self) -> u32 {
        // SAFETY: geteuid has no failure mode.
        unsafe { libc::geteuid() }
    }

    fn mono_ns(&self) -> u64 {
        clock_ns(libc::CLOCK_MONOTONIC)
    }

    fn real_ns(&self) -> u64 {
        clock_ns(libc::CLOCK_REALTIME)
    }

    fn free_bytes(&self, dir: &Path) -> io::Result<u64> {
        let c = CString::new(dir.as_os_str().as_bytes())
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
        // SAFETY: c is NUL-terminated and vfs is a valid out pointer.
        let mut vfs: libc::statvfs = unsafe { std::mem::zeroed() };
        if unsafe { libc::statvfs(c.as_ptr(), &mut vfs) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok((vfs.f_bavail as u64).saturating_mul(vfs.f_frsize as u64))
    }

    fn stop_signal(&self) -> Option<i32> {
        match STOP_SIGNAL.load(Ordering::SeqCst) {
            0 => None,
            sig => Some(sig),
        }
    }
}
