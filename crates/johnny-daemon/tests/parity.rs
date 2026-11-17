//! Stage 1 daemon end-to-end and Python reader parity tests (Rock Box,
//! synthetic ring and recorded fixtures only; no root, no BPF syscall,
//! no network).

use std::cell::Cell;
use std::fs;
use std::io;
use std::os::unix::fs::{PermissionsExt as _, symlink};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

use johnny_daemon::control::config::{LogFormat, RunConfig, UnknownVersion};
use johnny_daemon::control::status::Log;
use johnny_daemon::daemon::{self, Attached};
use johnny_daemon::data::KernelMaps;
use johnny_daemon::data::synth::{DISCARD, SynthRing};
use johnny_daemon::stop::Stop;
use johnny_daemon::sys::Sys;
use johnny_daemon_test_support::*;
use johnny_record_v1::record::ETHERTYPE_IPV4;
use johnny_record_v1::{M2Cfg, REC_SIZE, RecordV1};

mod johnny_daemon_test_support {
    use super::*;

    static NEXT_ID: AtomicU64 = AtomicU64::new(1);

    pub struct TempDir {
        path: PathBuf,
    }

    impl TempDir {
        pub fn new(label: &str) -> Self {
            let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "johnny-daemon-test-{label}-{}-{id}",
                std::process::id()
            ));
            let _ = fs::remove_dir_all(&path);
            fs::create_dir_all(&path).unwrap();
            fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
            TempDir { path }
        }

        pub fn path(&self) -> &Path {
            &self.path
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }
}

struct FakeSys {
    euid: u32,
    mono_ns: Cell<u64>,
    real_ns: Cell<u64>,
    free_bytes: Cell<u64>,
    signal: Cell<Option<i32>>,
    step_mono_on_wait: u64,
}

impl FakeSys {
    fn new(mono_ns: u64, real_ns: u64) -> Self {
        FakeSys {
            euid: unsafe { libc::geteuid() },
            mono_ns: Cell::new(mono_ns),
            real_ns: Cell::new(real_ns),
            free_bytes: Cell::new(500 << 30),
            signal: Cell::new(None),
            step_mono_on_wait: 0,
        }
    }
}

impl Sys for FakeSys {
    fn euid(&self) -> u32 {
        self.euid
    }

    fn mono_ns(&self) -> u64 {
        self.mono_ns.get()
    }

    fn real_ns(&self) -> u64 {
        self.real_ns.get()
    }

    fn free_bytes(&self, _dir: &Path) -> io::Result<u64> {
        Ok(self.free_bytes.get())
    }

    fn stop_signal(&self) -> Option<i32> {
        self.signal.get()
    }
}

struct FakeMaps<'a> {
    ring_map_id: u32,
    cfg: M2Cfg,
    ctl: [u64; 6],
    sys: Option<&'a FakeSys>,
    signal_on_wait: Option<i32>,
}

impl KernelMaps for FakeMaps<'_> {
    fn ring_map_id(&self) -> u32 {
        self.ring_map_id
    }

    fn read_cfg(&self) -> Result<M2Cfg, Stop> {
        Ok(self.cfg)
    }

    fn read_ctl(&self) -> Result<[u64; 6], Stop> {
        Ok(self.ctl)
    }

    fn wait(&self, _timeout_ms: i32) {
        if let Some(sys) = self.sys {
            if sys.step_mono_on_wait > 0 {
                sys.mono_ns
                    .set(sys.mono_ns.get() + sys.step_mono_on_wait);
                sys.real_ns
                    .set(sys.real_ns.get() + sys.step_mono_on_wait);
            }
            if let Some(sig) = self.signal_on_wait {
                sys.signal.set(Some(sig));
            }
        }
    }
}

#[derive(Default, Clone)]
struct SharedBuf(std::rc::Rc< std::cell::RefCell<Vec<u8>> >);

impl SharedBuf {
    fn text(&self) -> String {
        String::from_utf8(self.0.borrow().clone()).unwrap()
    }
}

impl io::Write for SharedBuf {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.0.borrow_mut().extend_from_slice(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf()
}

fn sample_records() -> Vec<[u8; REC_SIZE]> {
    let v4_a = [192, 168, 50, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let v4_b = [192, 168, 50, 223, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let v4_c = [80, 254, 212, 210, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let v6_a = [
        0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01,
    ];
    let v6_b = [
        0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x42,
    ];

    let specs = [
        (0u8, 0u16, 1514u32, ETHERTYPE_IPV4, 0u16, v4_a, v4_c, 6u8, 64u8, 1500u16, 51234u16, 443u16, 0x18u8, 1u32),
        (0x10, 1, 128, ETHERTYPE_IPV4, 100, v4_b, v4_c, 17, 64, 110, 53000, 53, 0, 10),
        (0, 0, 64, ETHERTYPE_IPV4, 0, v4_c, v4_a, 6, 57, 50, 443, 51234, 0x10, 2),
        // Sequence gap of 2 on rxq 0 (seq jumps from 2 to 5)
        (0x01, 0, 98, ETHERTYPE_IPV4, 0, v4_a, v4_b, 1, 64, 84, 0, 0, 0, 5),
        // IPv6 ICMPv6 on rxq 2
        (0x08, 2, 118, 0x86dd, 0, v6_a, v6_b, 58, 255, 64, 0, 0, 0, 100),
        // Other L4 proto (GRE=47) on rxq 3
        (0, 3, 200, ETHERTYPE_IPV4, 0, v4_b, v4_a, 47, 64, 186, 0, 0, 0, 7),
    ];

    specs
        .iter()
        .enumerate()
        .map(
            |(
                i,
                &(
                    flags,
                    rxq,
                    wire_len,
                    ethertype,
                    vlan_tci,
                    src_ip,
                    dst_ip,
                    l4_proto,
                    ttl_hlim,
                    l3_len,
                    sport,
                    dport,
                    tcp_flags,
                    seq_lo,
                ),
            )| {
                RecordV1 {
                    flags,
                    rxq,
                    wire_len,
                    ts_ns: 5_000_000_000 + (i as u64) * 1_000_000,
                    dst_mac: [0x00, 0x11, 0x22, 0x33, 0x44, i as u8],
                    src_mac: [0xaa, 0xbb, 0xcc, 0xdd, 0xee, i as u8],
                    ethertype,
                    vlan_tci,
                    src_ip,
                    dst_ip,
                    l4_proto,
                    ttl_hlim,
                    l3_len,
                    sport,
                    dport,
                    tcp_flags,
                    rsv0: 0,
                    rsv1: 0,
                    seq_lo,
                }
                .encode()
            },
        )
        .collect()
}

/// Prove byte-for-byte run-file parity, rotation/pruning parity, log text
/// parity, and `--summary` parity against `docs/tool-install/johnny-m1s2b-reader.py`
/// on the same synthetic ring input and recorded Johnny map fixtures.
#[test]
fn parity_run_files_and_summary_match_python_reader() {
    let root = repo_root();
    let py_reader = root.join("docs/tool-install/johnny-m1s2b-reader.py");
    assert!(py_reader.exists(), "missing {}", py_reader.display());

    let rust_dir = TempDir::new("parity-rust");
    let py_dir = TempDir::new("parity-py");

    // Pre-populate both output dirs with 3 old files so keep=3 prunes the
    // oldest on the first open, and later rotations prune again.
    for dir in [rust_dir.path(), py_dir.path()] {
        for i in 0..3 {
            let p = dir.join(format!("run-20261114T23000{i}Z.bin"));
            fs::write(&p, vec![b'x'; 256]).unwrap();
        }
    }

    let records = sample_records();
    // 2 records per file (96 + 2 * 80 = 256 bytes); 6 valid records -> 3 files opened.
    let file_max_bytes = 96 + 2 * 80;
    let keep = 3;
    let dir_cap_bytes = 768; // fits 2 existing 256-byte files + 1 reserved 256-byte file
    let reserve_bytes = 1024;
    let fixed_mono_ns: u64 = 5_000_000_000;
    let fixed_real_ns: u64 = 1_794_698_471_000_000_000; // 2026-11-14T23:21:11Z
    // Recorded Johnny m2_ctl sums from docs/findings/module1-slice2b/2026-11-12-evidence-johnny.txt
    // and live rev 114 m2_cfg.
    let cfg = M2Cfg {
        ver: 1,
        sample_every: 1,
        rate: 1_000_000,
        burst: 100_000,
    };
    let ctl: [u64; 6] = [843_847, 0, 407_183, 0, 436_664, 0];

    // 1. Run the Rust daemon on a synthetic ring containing the 6 records
    //    plus 1 discarded frame in the middle.
    let mut synth = SynthRing::new(4096);
    for (i, rec) in records.iter().enumerate() {
        if i == 3 {
            synth.produce(DISCARD, rec);
        }
        synth.produce(0, rec);
    }
    let ring = unsafe { synth.consumer() }.unwrap();
    let maps = FakeMaps {
        ring_map_id: 78,
        cfg,
        ctl,
        sys: None,
        signal_on_wait: None,
    };
    let sys = FakeSys::new(fixed_mono_ns, fixed_real_ns);
    let run_cfg = RunConfig {
        file_max_bytes: file_max_bytes as i128,
        file_max_seconds: 3600,
        keep,
        dir_cap_bytes: dir_cap_bytes as i128,
        reserve_bytes: reserve_bytes as i128,
        pin_dir: PathBuf::from("/unused"),
        out_dir: rust_dir.path().to_path_buf(),
        max_total_records: records.len() as u64,
        max_total_seconds: 0,
        on_unknown_version: UnknownVersion::Stop,
        log_format: LogFormat::Text,
    };
    let rust_log_buf = SharedBuf::default();
    let mut log = Log::new(LogFormat::Text, Box::new(rust_log_buf.clone()));
    daemon::run(&run_cfg, &sys, |_| Ok(Attached { ring, maps }), &mut log).unwrap();

    // 2. Run the Python reader on the exact same synthetic ring, clocks, and limits.
    let hex_records: Vec<String> = records
        .iter()
        .map(|r| r.iter().map(|b| format!("{b:02x}")).collect())
        .collect();
    let py_out = Command::new("python3")
        .arg("-I")
        .arg("-c")
        .arg(
            r#"
import ctypes, importlib.util, os, struct, sys, time

reader_path, out_dir = sys.argv[1], sys.argv[2]
hex_recs = sys.argv[3:]

spec = importlib.util.spec_from_file_location("reader", reader_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

FIXED_MONO = 5_000_000_000
FIXED_REAL = 1_794_698_471_000_000_000
orig_gmtime = time.gmtime
time.clock_gettime_ns = lambda clk: FIXED_MONO if clk == time.CLOCK_MONOTONIC else FIXED_REAL
time.gmtime = lambda secs=None: orig_gmtime(FIXED_REAL // 1_000_000_000 if secs is None else secs)
mod.check_disk_free = lambda d, r: 500 << 30

size = 4096
cons = (ctypes.c_uint64 * 1)()
prod = (ctypes.c_uint64 * 1)()
data = (ctypes.c_char * (2 * size))()
ring = mod.Ring(ctypes.addressof(cons), ctypes.addressof(prod), ctypes.addressof(data), size)

def put_frame(flags, raw):
    pos = prod[0]
    hdr = (mod.REC_SIZE | flags) & 0xFFFFFFFF
    frame = struct.pack("<II", hdr, 0) + raw
    for i, b in enumerate(frame):
        at = (pos + i) % size
        data[at] = b
        data[at + size] = b
    prod[0] = pos + 88

for i, h in enumerate(hex_recs):
    raw = bytes.fromhex(h)
    if i == 3:
        put_frame(mod.RB_DISCARD, raw)
    put_frame(0, raw)

ctl_vals = [843847, 0, 407183, 0, 436664, 0]
class FakeBpf:
    def lookup(self, fd, k, sz):
        return struct.pack("<Q", ctl_vals[k])

cfg = (1, 1, 1000000, 100000)
file_max_bytes = 96 + 2 * 80
keep = 3
dir_cap = 768
reserve = 1024

print("M1S2B-READER-BEGIN out_dir=%s ring_map_id=%d cfg=ver:%d,every:%d,rate:%d,burst:%d "
      "file_max_bytes=%d file_max_seconds=%d keep=%d dir_cap=%d reserve=%d"
      % (out_dir, 78, *cfg, file_max_bytes, 3600, keep, dir_cap, reserve), flush=True)

writer = mod.RotatingWriter(
    out_dir=out_dir,
    file_max_bytes=file_max_bytes,
    file_max_seconds=3600,
    keep=keep,
    dir_cap_bytes=dir_cap,
    reserve_bytes=reserve,
    bpf=FakeBpf(),
    cfg=cfg,
    ctl_fd=0,
    ncpu=1,
)
writer.open_next_file()
ring.drain(4096, writer.sink)
writer.flush()
writer.close_current_file()
print("M1S2B-READER-END reason=%s total_files=%d total_records=%d total_bytes=%d "
      "seq_gaps=%d ring_discarded=%d backlog=%d"
      % ("max-total-records", writer.total_files, writer.total_records, writer.total_bytes,
         writer.gaps, ring.discarded, ring.prod.value - ring.cons.value), flush=True)
"#,
        )
        .arg(&py_reader)
        .arg(py_dir.path())
        .args(&hex_records)
        .output()
        .unwrap();
    assert!(
        py_out.status.success(),
        "python reader failed: {}",
        String::from_utf8_lossy(&py_out.stderr)
    );

    // 3. Compare event logs (normalizing out_dir path).
    let rust_log = rust_log_buf
        .text()
        .replace(&rust_dir.path().display().to_string(), "<OUT>");
    let py_log = String::from_utf8(py_out.stdout)
        .unwrap()
        .replace(&py_dir.path().display().to_string(), "<OUT>");
    assert_eq!(rust_log, py_log, "daemon text log vs python reader log");

    // 4. Compare surviving run files and every byte of their contents.
    let rust_files = johnny_daemon::data::writer::run_files(rust_dir.path()).unwrap();
    let py_files = johnny_daemon::data::writer::run_files(py_dir.path()).unwrap();
    assert_eq!(
        rust_files,
        vec![
            "run-20261114T232111Z-01.bin",
            "run-20261114T232111Z-02.bin",
            "run-20261114T232111Z.bin",
        ]
    );
    assert_eq!(rust_files, py_files);

    let bin = env!("CARGO_BIN_EXE_johnny-daemon");
    for name in &rust_files {
        let rf = rust_dir.path().join(name);
        let pf = py_dir.path().join(name);
        let r_bytes = fs::read(&rf).unwrap();
        let p_bytes = fs::read(&pf).unwrap();
        assert_eq!(r_bytes.len(), 96 + 2 * 80);
        assert_eq!(r_bytes, p_bytes, "byte parity failed on {name}");

        // Compare `johnny-daemon --summary` vs `johnny-m1s2b-reader.py --summary` on the same file.
        let r_sum = Command::new(bin)
            .args(["--summary", rf.to_str().unwrap(), "--top", "5"])
            .output()
            .unwrap();
        let p_sum = Command::new("python3")
            .arg("-I")
            .arg(&py_reader)
            .args(["--summary", rf.to_str().unwrap(), "--top", "5"])
            .output()
            .unwrap();
        assert!(r_sum.status.success());
        assert!(p_sum.status.success());
        assert_eq!(
            String::from_utf8_lossy(&r_sum.stdout),
            String::from_utf8_lossy(&p_sum.stdout),
            "--summary parity failed on {name}"
        );
    }
}

#[test]
fn daemon_json_log_and_dump_json_stamp_version_1() {
    let dir = TempDir::new("json-v1");
    let records = sample_records();
    let mut synth = SynthRing::new(4096);
    for rec in &records {
        synth.produce(0, rec);
    }
    // Inject one v2 record: default policy (Skip) skips and counts it.
    let mut v2 = records[0];
    v2[0] = 2;
    synth.produce(0, &v2);

    let ring = unsafe { synth.consumer() }.unwrap();
    let maps = FakeMaps {
        ring_map_id: 78,
        cfg: M2Cfg {
            ver: 1,
            sample_every: 1,
            rate: 1_000_000,
            burst: 100_000,
        },
        ctl: [100, 0, 0, 0, 100, 0],
        sys: None,
        signal_on_wait: None,
    };
    let sys = FakeSys::new(1_000_000_000, 1_794_698_471_000_000_000);
    let cfg = RunConfig {
        out_dir: dir.path().to_path_buf(),
        max_total_records: records.len() as u64,
        ..RunConfig::default()
    };
    let log_buf = SharedBuf::default();
    let mut log = Log::new(LogFormat::Json, Box::new(log_buf.clone()));
    daemon::run(&cfg, &sys, |_| Ok(Attached { ring, maps }), &mut log).unwrap();

    let log_text = log_buf.text();
    let lines: Vec<&str> = log_text.lines().collect();
    assert_eq!(lines.len(), 4, "begin + open + closed + end: {log_text}");
    for line in &lines {
        assert!(
            line.starts_with("{\"version\":1,\"event\":\""),
            "missing version 1 stamp: {line}"
        );
        assert!(line.ends_with('}'));
    }
    assert!(lines[3].contains("\"unknown_version\":1"));
    assert!(lines[3].contains("\"seq_gaps\":2"));

    let run_file = dir.path().join("run-20261114T232111Z.bin");
    let mut dump = Vec::new();
    johnny_daemon::tools::dump_json(run_file.to_str().unwrap(), &mut dump).unwrap();
    let dump_str = String::from_utf8(dump).unwrap();
    let dump_lines: Vec<&str> = dump_str.lines().collect();
    assert_eq!(dump_lines.len(), records.len() + 1);
    for line in &dump_lines {
        assert!(line.starts_with("{\"version\":1,"));
    }
    assert!(dump_lines.last().unwrap().contains("\"event\":\"dump-end\""));
    assert!(
        dump_lines
            .last()
            .unwrap()
            .contains(&format!("\"records\":{}", records.len()))
    );
}

#[test]
fn daemon_time_rotation_and_stop_paths() {
    // 1. Idle time rotation + max-total-seconds stop.
    let dir = TempDir::new("time-rot");
    let mut synth = SynthRing::new(4096);
    let ring = unsafe { synth.consumer() }.unwrap();
    let mut sys = FakeSys::new(10_000_000_000, 1_794_698_471_000_000_000);
    sys.step_mono_on_wait = 10_000_000_000; // +10 s per poll
    let maps = FakeMaps {
        ring_map_id: 1,
        cfg: M2Cfg::default(),
        ctl: [0; 6],
        sys: Some(&sys),
        signal_on_wait: None,
    };
    let cfg = RunConfig {
        out_dir: dir.path().to_path_buf(),
        file_max_seconds: 10,
        max_total_seconds: 20,
        ..RunConfig::default()
    };
    let log_buf = SharedBuf::default();
    let mut log = Log::new(LogFormat::Text, Box::new(log_buf.clone()));
    daemon::run(&cfg, &sys, |_| Ok(Attached { ring, maps }), &mut log).unwrap();
    let text = log_buf.text();
    assert!(text.contains("reason=max-total-seconds total_files=3"), "{text}");

    // 2. Signal stop.
    let dir_sig = TempDir::new("sig-stop");
    let mut synth = SynthRing::new(4096);
    let ring = unsafe { synth.consumer() }.unwrap();
    let sys = FakeSys::new(10_000_000_000, 1_794_698_471_000_000_000);
    let maps = FakeMaps {
        ring_map_id: 1,
        cfg: M2Cfg::default(),
        ctl: [0; 6],
        sys: Some(&sys),
        signal_on_wait: Some(15),
    };
    let cfg = RunConfig {
        out_dir: dir_sig.path().to_path_buf(),
        ..RunConfig::default()
    };
    let log_buf = SharedBuf::default();
    let mut log = Log::new(LogFormat::Text, Box::new(log_buf.clone()));
    daemon::run(&cfg, &sys, |_| Ok(Attached { ring, maps }), &mut log).unwrap();
    assert!(log_buf.text().contains("reason=signal-15"));

    // 3. Low disk free stops before opening.
    let dir_low = TempDir::new("low-disk");
    let mut synth = SynthRing::new(4096);
    let ring = unsafe { synth.consumer() }.unwrap();
    let sys = FakeSys::new(0, 1_794_698_471_000_000_000);
    sys.free_bytes.set(100);
    let maps = FakeMaps {
        ring_map_id: 1,
        cfg: M2Cfg::default(),
        ctl: [0; 6],
        sys: None,
        signal_on_wait: None,
    };
    let cfg = RunConfig {
        out_dir: dir_low.path().to_path_buf(),
        reserve_bytes: 1024,
        ..RunConfig::default()
    };
    let mut log = Log::new(LogFormat::Text, Box::new(SharedBuf::default()));
    let err = daemon::run(&cfg, &sys, |_| Ok(Attached { ring, maps }), &mut log).unwrap_err();
    assert_eq!(err.to_string(), "STOP-low-disk free=100 reserve=1024");

    // 4. Out-dir mode and symlink refusal.
    let dir_bad = TempDir::new("bad-mode");
    fs::set_permissions(dir_bad.path(), fs::Permissions::from_mode(0o755)).unwrap();
    let err = johnny_daemon::data::writer::check_out_dir(dir_bad.path(), &sys).unwrap_err();
    assert!(err.to_string().starts_with("STOP-out-dir-mode "));

    let link_path = dir_low.path().join("symlink-out");
    symlink(dir_low.path(), &link_path).unwrap();
    let err = johnny_daemon::data::writer::check_out_dir(&link_path, &sys).unwrap_err();
    assert!(err.to_string().starts_with("STOP-out-dir-not-dir "));
}

#[test]
fn cli_binary_smoke() {
    let bin = env!("CARGO_BIN_EXE_johnny-daemon");

    let ver = Command::new(bin).arg("--version").output().unwrap();
    assert!(ver.status.success());
    assert_eq!(
        String::from_utf8_lossy(&ver.stdout),
        "johnny-daemon 0.1.0 record-version 1 header-version 1\n"
    );

    let bad = Command::new(bin).arg("--no-such-flag").output().unwrap();
    assert_eq!(bad.status.code(), Some(2));

    // Non-root run mode stops with STOP-not-root (JSON by default, plain text with --log-format text).
    if unsafe { libc::geteuid() } != 0 {
        let out_json = Command::new(bin).output().unwrap();
        assert_eq!(out_json.status.code(), Some(1));
        assert_eq!(
            String::from_utf8_lossy(&out_json.stderr),
            "{\"version\":1,\"event\":\"stop\",\"stop\":\"STOP-not-root\"}\n"
        );

        let out_text = Command::new(bin)
            .args(["--log-format", "text"])
            .output()
            .unwrap();
        assert_eq!(out_text.status.code(), Some(1));
        assert_eq!(String::from_utf8_lossy(&out_text.stderr), "STOP-not-root\n");
    }

    // Short / corrupt header handling in --summary and --dump-json.
    let dir = TempDir::new("cli-err");
    let short = dir.path().join("short.bin");
    fs::write(&short, b"short").unwrap();
    let out = Command::new(bin)
        .args(["--summary", short.to_str().unwrap()])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&out.stderr).starts_with("STOP-header-short "));

    let corrupt = dir.path().join("corrupt.bin");
    fs::write(&corrupt, [0u8; 96]).unwrap();
    let out = Command::new(bin)
        .args(["--dump-json", corrupt.to_str().unwrap()])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&out.stderr).contains("STOP-header-corrupt "));
}

#[test]
fn unit_file_matches_or_exceeds_reader_sandbox() {
    let root = repo_root();
    let py_unit =
        fs::read_to_string(root.join("etc/systemd/system/johnny-m1s2b-reader.service")).unwrap();
    let rs_unit =
        fs::read_to_string(root.join("etc/systemd/system/johnny-daemon.service")).unwrap();

    fn directives(unit: &str) -> std::collections::BTreeMap<String, String> {
        unit.lines()
            .map(str::trim)
            .filter(|l| !l.is_empty() && !l.starts_with('#') && !l.starts_with('['))
            .filter_map(|l| l.split_once('='))
            .map(|(k, v)| (k.trim().to_string(), v.trim().to_string()))
            .collect()
    }

    let py_map = directives(&py_unit);
    let rs_map = directives(&rs_unit);

    for (k, py_val) in &py_map {
        match k.as_str() {
            "Description" => continue,
            "ConditionPathExists" => {
                assert_eq!(
                    rs_map.get(k).map(String::as_str),
                    Some("/usr/local/libexec/johnny/johnny-daemon")
                );
            }
            "ExecStart" => {
                assert_eq!(
                    rs_map.get(k).map(String::as_str),
                    Some(
                        "/usr/local/libexec/johnny/johnny-daemon --file-max-bytes 1073741824 --file-max-seconds 3600 --keep 200 --dir-cap-bytes 214748364800 --reserve-bytes 107374182400"
                    )
                );
            }
            _ => {
                assert_eq!(
                    rs_map.get(k),
                    Some(py_val),
                    "directive {k} in johnny-daemon.service must match johnny-m1s2b-reader.service"
                );
            }
        }
    }
    assert_eq!(
        rs_map.get("Conflicts").map(String::as_str),
        Some("johnny-m1s2b-reader.service")
    );
}

#[test]
fn cutover_runbook_audit() {
    let root = repo_root();
    let runbook = root.join("docs/tool-install/stage1-rust-daemon-cutover.md");
    assert!(runbook.exists(), "missing {}", runbook.display());
    let unit_bytes = fs::read(root.join("etc/systemd/system/johnny-daemon.service")).unwrap();
    let unit_sha = Command::new("sha256sum")
        .arg(root.join("etc/systemd/system/johnny-daemon.service"))
        .output()
        .unwrap();
    let unit_sha = String::from_utf8(unit_sha.stdout)
        .unwrap()
        .split_whitespace()
        .next()
        .unwrap()
        .to_string();
    assert!(!unit_bytes.is_empty());

    let out = Command::new("python3")
        .arg("-I")
        .arg("-c")
        .arg(
            r####"
import hashlib, json, re, shlex, sys

doc_path, want_unit_sha, sbom_path = sys.argv[1:4]
sbom_raw = open(sbom_path, "rb").read()
want_sbom_sha = hashlib.sha256(sbom_raw).hexdigest()
want_bin_sha = json.loads(sbom_raw.decode("utf-8"))["metadata"]["component"]["hashes"][0]["content"]
text = open(doc_path, encoding="utf-8").read()
assert "DO NOT RUN BEFORE PASTE W" in text, "missing Paste W hold banner"
assert "2026-11-21 15:33 CT" in text, "missing week-test end timestamp"

lines = text.splitlines()
blocks = []
label = None
i = 0
while i < len(lines):
    s = lines[i].strip()
    if s.startswith("***<u>Run on Rock Box</u>***"):
        label = "rock"
    elif s.startswith("```"):
        lang = s[3:].strip()
        j = i + 1
        body = []
        while j < len(lines) and not lines[j].startswith("```"):
            body.append(lines[j])
            j += 1
        if lang == "bash":
            blocks.append((label, "\n".join(body)))
        label = None
        i = j
    i += 1

def outside_single_quotes(body):
    inq = False
    for ln in body.split("\n"):
        out = []
        for ch in ln:
            if ch == "'":
                inq = not inq
            elif not inq:
                out.append(ch)
        yield "".join(out)

expected_tokens = [
    "STAGE1-ROCKBOX-GATE-DONE",
    "STAGE1-COPY-DONE",
    "STAGE1-PROBE-INSTALL-DONE",
    "STAGE1-CUTOVER-DONE",
    "STAGE1-VERIFY-DONE",
    "STAGE1-ROLLBACK-DONE",
]
assert len(blocks) == len(expected_tokens), f"got {len(blocks)} blocks, want {len(expected_tokens)}"

for idx, ((lab, body), want_tok) in enumerate(zip(blocks, expected_tokens), 1):
    assert lab == "rock", f"block #{idx} missing ***<u>Run on Rock Box</u>***"
    assert not re.search(r"<[A-Za-z_][^>\n]*>", body), f"placeholder in block #{idx}"
    for s in outside_single_quotes(body):
        assert not re.search(r"(^|[;&|(])\s*sudo\b", s.strip()), f"sudo outside ssh single quotes in block #{idx}: {s}"
    if "sudo" in body:
        assert "ssh -t aj@192.168.50.152 'sudo -v &&\n" in body, f"block #{idx} missing ssh -t sudo -v header"
        assert body.rstrip().endswith("'"), f"block #{idx} must end with closing single quote"
    stoks = shlex.split(body)
    for k, tok in enumerate(stoks):
        if tok == "ssh":
            h_idx = -1
            for m in range(k + 1, len(stoks)):
                if stoks[m].startswith("-"):
                    continue
                if "@" in stoks[m] or "192.168." in stoks[m]:
                    h_idx = m
                    break
            assert h_idx >= 0, f"block #{idx}: ssh without destination host"
            end_idx = len(stoks)
            for m in range(h_idx + 1, len(stoks)):
                if stoks[m] in ("&&", ";", "||", "|"):
                    end_idx = m
                    break
            remote_args = stoks[h_idx + 1:end_idx]
            assert len(remote_args) == 1, f"block #{idx}: nested quotes split ssh command: {remote_args}"
    assert f"echo {want_tok}" in body, f"block #{idx} missing token {want_tok}"
    for h, path in re.findall(r"\b([0-9a-f]{64})  ([^\s\"']+)", body):
        if path.endswith("johnny-daemon.service"):
            assert h == want_unit_sha, f"block #{idx} wrong unit sha {h} != {want_unit_sha}"
        elif path.endswith("johnny-daemon.cdx.json"):
            assert h == want_sbom_sha, f"block #{idx} wrong sbom sha {h} != {want_sbom_sha}"
        elif path.endswith("/johnny-daemon") or path == "johnny-daemon":
            assert h == want_bin_sha, f"block #{idx} wrong bin sha {h} != {want_bin_sha}"

rb = text.find("## Rollback")
assert rb >= 0 and "not part of the paste sequence" in text[rb:rb + 200]
"####,
        )
        .arg(&runbook)
        .arg(&unit_sha)
        .arg(root.join("crates/johnny-daemon.cdx.json"))
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "cutover runbook audit failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn probe_opens_m2_rb_read_write_and_maps_positions_read_only() {
    let root = repo_root();
    let bpf_src = fs::read_to_string(root.join("crates/johnny-daemon/src/bpf.rs")).unwrap();
    let start = bpf_src
        .find("pub fn probe(")
        .expect("missing pub fn probe in src/bpf.rs");
    let rest = &bpf_src[start..];
    let open_brace = rest.find('{').expect("missing opening brace for probe()");
    let mut depth = 0usize;
    let mut end = None;
    for (idx, ch) in rest[open_brace..].char_indices() {
        match ch {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    end = Some(open_brace + idx + 1);
                    break;
                }
            }
            _ => {}
        }
    }
    let probe_body = &rest[..end.expect("unclosed brace in probe()")];
    assert!(
        probe_body.contains("open_pin(&rb_pin, MapType::RingBuf, RB_BYTES, false)"),
        "probe() must open m2_rb read-write (rdonly=false) so do_mmap keeps VM_SHARED for bpf_map_mmap"
    );
    assert!(
        !probe_body.contains("open_pin(&rb_pin, MapType::RingBuf, RB_BYTES, true)"),
        "probe() must not open m2_rb read-only (BPF_F_RDONLY)"
    );
    assert!(
        probe_body.contains(
            "Mapping::new(rb.fd().as_fd().as_raw_fd(), 2 * page, libc::PROT_READ, 0)"
        ),
        "probe() must map consumer+producer pages with PROT_READ only"
    );
    assert!(
        !probe_body.contains("PROT_WRITE"),
        "probe() must never map ring pages with PROT_WRITE"
    );
}



