//! The kernel boundary, and the only module that uses the aya crate.
//!
//! It opens the pins that `j_xdp_records` already owns, checks each map's
//! type and size, reads `m2_cfg` and `m2_ctl` through aya, and maps the
//! ring's memory. It creates nothing, loads nothing, attaches nothing, and
//! writes to no map; the only kernel memory it writes is the ring's
//! consumer position.
//!
//! Privilege matches the Python reader
//! (`docs/tool-install/johnny-m1s2b-reader.py:504-506`): `m2_rb` is opened
//! read-write (the consumer page needs it), `m2_cfg` and `m2_ctl` are
//! opened with `BPF_F_RDONLY`. aya 0.16 has no read-only pin open, so those
//! two descriptors come from one small `BPF_OBJ_GET` call here and are then
//! handed to aya (`MapData::from_fd`).
//!
//! Not exercised on Rock Box: creating a BPF map there needs privilege
//! (`kernel.unprivileged_bpf_disabled=2`). The tests drive the daemon
//! through `data::synth` instead. `--probe` is the first, read-only use of
//! this module on Johnny.

use std::ffi::CString;
use std::io;
use std::os::fd::{AsFd as _, AsRawFd as _, FromRawFd as _, OwnedFd};
use std::os::unix::ffi::OsStrExt as _;
use std::path::Path;
use std::ptr;

use aya::maps::{Array, Map, MapData, MapError, MapType, PerCpuArray};
use johnny_record_v1::runfile::{CFG_SIZE, CTL_NAMES};
use johnny_record_v1::{M2Cfg, OUTPUT_VERSION};

use crate::daemon::Attached;
use crate::data::ring::Ring;
use crate::data::KernelMaps;
use crate::stop;
use crate::stop::Stop;

/// `M2_RB_BYTES` (`docs/tool-install/module1_xdp_records.c:80`).
pub const RB_BYTES: u32 = 1 << 22;

const BPF_OBJ_GET: libc::c_long = 7;
const BPF_F_RDONLY: u32 = 1 << 3;

fn errno_of(e: &MapError) -> i32 {
    match e {
        MapError::SyscallError(s) => s.io_error.raw_os_error().unwrap_or(0),
        _ => 0,
    }
}

fn require_pin(pin: &Path) -> Result<(), Stop> {
    if !pin.exists() {
        return Err(stop!("pin-missing {}", pin.display()));
    }
    Ok(())
}

/// `BPF_OBJ_GET` with `BPF_F_RDONLY`.
fn obj_get_rdonly(pin: &Path) -> io::Result<OwnedFd> {
    #[repr(C)]
    struct ObjGetAttr {
        pathname: u64,
        bpf_fd: u32,
        file_flags: u32,
    }
    let path = CString::new(pin.as_os_str().as_bytes())
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    let attr = ObjGetAttr {
        pathname: path.as_ptr() as u64,
        bpf_fd: 0,
        file_flags: BPF_F_RDONLY,
    };
    loop {
        // SAFETY: attr is a valid bpf_attr prefix for BPF_OBJ_GET and path
        // outlives the call.
        let rc = unsafe {
            libc::syscall(
                libc::SYS_bpf,
                BPF_OBJ_GET,
                &attr as *const ObjGetAttr,
                std::mem::size_of::<ObjGetAttr>(),
            )
        };
        if rc >= 0 {
            // SAFETY: a fresh descriptor that nothing else owns.
            return Ok(unsafe { OwnedFd::from_raw_fd(rc as i32) });
        }
        let err = io::Error::last_os_error();
        if err.kind() != io::ErrorKind::Interrupted {
            return Err(err);
        }
    }
}

/// Open one pin through aya and check it is the map we expect.
fn open_pin(pin: &Path, want: MapType, want_entries: u32, rdonly: bool) -> Result<MapData, Stop> {
    require_pin(pin)?;
    let shown = pin.display();
    let data = if rdonly {
        let fd = obj_get_rdonly(pin).map_err(|e| {
            stop!("obj-get {shown} errno={} ({e})", e.raw_os_error().unwrap_or(0))
        })?;
        MapData::from_fd(fd).map_err(|e| stop!("obj-info {shown} errno={}", errno_of(&e)))?
    } else {
        MapData::from_pin(pin).map_err(|e| stop!("obj-get {shown} errno={} ({e})", errno_of(&e)))?
    };
    let info = data
        .info()
        .map_err(|e| stop!("obj-info {shown} errno={}", errno_of(&e)))?;
    match info.map_type() {
        Ok(t) if t == want => {}
        Ok(t) => {
            return Err(stop!("map-type {shown} got={} want={}", t as u32, want as u32));
        }
        Err(_) => return Err(stop!("map-type {shown} got=unknown want={}", want as u32)),
    }
    if info.max_entries() != want_entries {
        return Err(stop!(
            "map-entries {shown} got={} want={want_entries}",
            info.max_entries()
        ));
    }
    Ok(data)
}

fn cfg_map(pin_dir: &Path) -> Result<Array<MapData, [u8; CFG_SIZE]>, Stop> {
    let pin = pin_dir.join("m2_cfg");
    let data = open_pin(&pin, MapType::Array, 1, true)?;
    Map::from_map_data(data)
        .and_then(Array::try_from)
        .map_err(|e| stop!("map-shape {} ({e})", pin.display()))
}

fn ctl_map(pin_dir: &Path) -> Result<PerCpuArray<MapData, u64>, Stop> {
    let pin = pin_dir.join("m2_ctl");
    let data = open_pin(&pin, MapType::PerCpuArray, CTL_NAMES.len() as u32, true)?;
    Map::from_map_data(data)
        .and_then(PerCpuArray::try_from)
        .map_err(|e| stop!("map-shape {} ({e})", pin.display()))
}

fn read_cfg(cfg: &Array<MapData, [u8; CFG_SIZE]>) -> Result<M2Cfg, Stop> {
    let raw = cfg
        .get(&0, 0)
        .map_err(|e| stop!("cfg-lookup errno={} ({e})", errno_of(&e)))?;
    Ok(M2Cfg::decode(&raw))
}

fn read_ctl(ctl: &PerCpuArray<MapData, u64>) -> Result<[u64; 6], Stop> {
    let mut out = [0u64; 6];
    for (k, slot) in out.iter_mut().enumerate() {
        let per_cpu = ctl
            .get(&(k as u32), 0)
            .map_err(|e| stop!("ctl-lookup key={k} errno={} ({e})", errno_of(&e)))?;
        *slot = per_cpu.iter().fold(0u64, |a, v| a.wrapping_add(*v));
    }
    Ok(out)
}

/// One `mmap`, unmapped on drop.
struct Mapping {
    addr: *mut libc::c_void,
    len: usize,
}

impl Mapping {
    fn new(fd: i32, len: usize, prot: i32, offset: usize) -> io::Result<Mapping> {
        // SAFETY: a fresh shared mapping of a map fd; the kernel picks the address.
        let addr = unsafe {
            libc::mmap(
                ptr::null_mut(),
                len,
                prot,
                libc::MAP_SHARED,
                fd,
                offset as libc::off_t,
            )
        };
        if addr == libc::MAP_FAILED {
            return Err(io::Error::last_os_error());
        }
        Ok(Mapping { addr, len })
    }
}

impl Drop for Mapping {
    fn drop(&mut self) {
        // SAFETY: addr and len are the mapping made in new().
        unsafe { libc::munmap(self.addr, self.len) };
    }
}

fn page_size() -> usize {
    // SAFETY: sysconf has no memory effects.
    unsafe { libc::sysconf(libc::_SC_PAGESIZE) as usize }
}

fn mmap_stop(what: &str, e: &io::Error) -> Stop {
    stop!("mmap-{what} errno={} ({e})", e.raw_os_error().unwrap_or(0))
}

pub struct PinnedMaps {
    rb: MapData,
    ring_map_id: u32,
    cfg: Array<MapData, [u8; CFG_SIZE]>,
    ctl: PerCpuArray<MapData, u64>,
}

impl KernelMaps for PinnedMaps {
    fn ring_map_id(&self) -> u32 {
        self.ring_map_id
    }

    fn read_cfg(&self) -> Result<M2Cfg, Stop> {
        read_cfg(&self.cfg)
    }

    fn read_ctl(&self) -> Result<[u64; 6], Stop> {
        read_ctl(&self.ctl)
    }

    fn wait(&self, timeout_ms: i32) {
        let mut pfd = libc::pollfd {
            fd: self.rb.fd().as_fd().as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        // A signal or an error ends the wait early; the loop re-checks.
        // SAFETY: one valid pollfd.
        unsafe { libc::poll(&mut pfd, 1, timeout_ms) };
    }
}

/// Open `m2_rb`, `m2_cfg`, `m2_ctl` under `pin_dir` and map the ring.
pub fn attach(pin_dir: &Path) -> Result<Attached<PinnedMaps>, Stop> {
    let rb_pin = pin_dir.join("m2_rb");
    let rb = open_pin(&rb_pin, MapType::RingBuf, RB_BYTES, false)?;
    let ring_map_id = rb
        .info()
        .map_err(|e| stop!("obj-info {} errno={}", rb_pin.display(), errno_of(&e)))?
        .id();
    let cfg = cfg_map(pin_dir)?;
    let ctl = ctl_map(pin_dir)?;

    let page = page_size();
    let size = RB_BYTES as usize;
    let fd = rb.fd().as_fd().as_raw_fd();
    // Page 0: consumer position, read-write. Then, read-only: the producer
    // position page and the data pages, mapped twice by the kernel.
    let cons = Mapping::new(fd, page, libc::PROT_READ | libc::PROT_WRITE, 0)
        .map_err(|e| mmap_stop("consumer", &e))?;
    let prod = Mapping::new(fd, page + 2 * size, libc::PROT_READ, page)
        .map_err(|e| mmap_stop("producer", &e))?;
    let cons_ptr = cons.addr.cast::<u64>();
    let prod_ptr = prod.addr.cast::<u64>().cast_const();
    // SAFETY: both mappings are page-aligned, sized as the ring layout
    // requires, and owned by the Ring from here on.
    let ring = unsafe {
        let data_ptr = prod.addr.cast::<u8>().cast_const().add(page);
        Ring::from_raw(
            cons_ptr,
            prod_ptr,
            data_ptr,
            size as u64,
            Some(Box::new((cons, prod))),
        )?
    };
    Ok(Attached {
        ring,
        maps: PinnedMaps {
            rb,
            ring_map_id,
            cfg,
            ctl,
        },
    })
}

/// Read-only look at the three pins: types, sizes, `m2_cfg`, `m2_ctl`, and
/// the ring's two positions. Every pin is opened `BPF_F_RDONLY` and the
/// ring pages are mapped `PROT_READ`, so this consumes nothing and can run
/// beside the live reader. One JSON line.
pub fn probe(pin_dir: &Path) -> Result<String, Stop> {
    let rb_pin = pin_dir.join("m2_rb");
    let rb = open_pin(&rb_pin, MapType::RingBuf, RB_BYTES, true)?;
    let ring_map_id = rb
        .info()
        .map_err(|e| stop!("obj-info {} errno={}", rb_pin.display(), errno_of(&e)))?
        .id();
    let cfg = read_cfg(&cfg_map(pin_dir)?)?;
    let ctl = read_ctl(&ctl_map(pin_dir)?)?;

    let page = page_size();
    let pos = Mapping::new(rb.fd().as_fd().as_raw_fd(), 2 * page, libc::PROT_READ, 0)
        .map_err(|e| mmap_stop("probe", &e))?;
    // SAFETY: two readable pages; the positions are the first word of each.
    let (cons, prod) = unsafe {
        let base = pos.addr.cast::<u8>().cast_const();
        (
            ptr::read_volatile(base.cast::<u64>()),
            ptr::read_volatile(base.add(page).cast::<u64>()),
        )
    };

    let ctl_json: Vec<String> = CTL_NAMES
        .iter()
        .zip(ctl.iter())
        .map(|(k, v)| format!("\"{k}\":{v}"))
        .collect();
    Ok(format!(
        "{{\"version\":{OUTPUT_VERSION},\"event\":\"probe\",\"ring_map_id\":{ring_map_id},\
         \"ring_bytes\":{RB_BYTES},\"cfg\":{{\"ver\":{},\"sample_every\":{},\"rate\":{},\
         \"burst\":{}}},\"ctl\":{{{}}},\"consumer_pos\":{cons},\"producer_pos\":{prod},\
         \"backlog\":{}}}",
        cfg.ver,
        cfg.sample_every,
        cfg.rate,
        cfg.burst,
        ctl_json.join(","),
        prod.wrapping_sub(cons)
    ))
}
