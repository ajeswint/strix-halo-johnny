use std::io::{self, Write as _};
use std::process::ExitCode;

use johnny_daemon::control::config::{self, LogFormat, Mode};
use johnny_daemon::control::status::{render_stop, Log};
use johnny_daemon::stop::Stop;
use johnny_daemon::sys::{self, RealSys, Sys as _};
use johnny_daemon::{bpf, daemon, stop, tools};

fn run(mode: Mode) -> (LogFormat, Result<(), Stop>) {
    match mode {
        Mode::Version => {
            println!(
                "johnny-daemon {} record-version 1 header-version 1",
                env!("CARGO_PKG_VERSION")
            );
            (LogFormat::Text, Ok(()))
        }
        Mode::Help => {
            print!("{}", config::USAGE);
            (LogFormat::Text, Ok(()))
        }
        Mode::Summary { file, top } => {
            let mut out = io::BufWriter::new(io::stdout().lock());
            let res = tools::summary(&file, top, &mut out);
            (LogFormat::Text, res.and_then(|()| flush(&mut out)))
        }
        Mode::DumpJson { file } => {
            let mut out = io::BufWriter::new(io::stdout().lock());
            let res = tools::dump_json(&file, &mut out);
            (LogFormat::Json, res.and_then(|()| flush(&mut out)))
        }
        Mode::Probe { pin_dir } => (
            LogFormat::Json,
            bpf::probe(&pin_dir).map(|line| println!("{line}")),
        ),
        Mode::Run(cfg) => {
            let format = cfg.log_format;
            if RealSys.euid() != 0 {
                return (format, Err(stop!("not-root")));
            }
            if let Err(e) = sys::install_signal_handlers() {
                return (format, Err(stop!("signal-setup ({e})")));
            }
            let mut log = Log::stdout(format);
            (format, daemon::run(&cfg, &RealSys, bpf::attach, &mut log))
        }
    }
}

fn flush(out: &mut dyn io::Write) -> Result<(), Stop> {
    out.flush().map_err(|e| stop!("write-failed stdout ({e})"))
}

fn main() -> ExitCode {
    let mode = match config::parse(std::env::args().skip(1)) {
        Ok(mode) => mode,
        Err(config::UsageError(msg)) => {
            let _ = writeln!(io::stderr(), "{}johnny-daemon: error: {msg}", config::USAGE);
            return ExitCode::from(2);
        }
    };
    match run(mode) {
        (_, Ok(())) => ExitCode::SUCCESS,
        (format, Err(stop)) => {
            let _ = writeln!(io::stderr(), "{}", render_stop(format, &stop));
            ExitCode::from(1)
        }
    }
}
