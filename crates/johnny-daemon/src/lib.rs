//! Johnny Stage 1 userspace sensor daemon.
//!
//! Drains ring `m2_rb` (filled in-kernel by the C program `j_xdp_records`)
//! into rotating run files that are byte-compatible with
//! `docs/tool-install/johnny-m1s2b-reader.py`. Userspace only: it opens the
//! existing pins and never loads, attaches, or changes a BPF program.
//!
//! One daemon, two planes (`docs/architecture/architecture-rev2.md` §1.2,
//! NIST SP 800-207 terms):
//!
//! - [`control`] is the control plane. `config` takes the operator's limits
//!   and validates them (Policy Administrator). `policy` makes every
//!   decision as a pure function: rotate, prune, stop on low disk (Policy
//!   Engine). `status` is the event log.
//! - [`data`] is the data plane, the enforcement point (PEP). `ring` is the
//!   ring consumer and `writer` is the run-file writer. They hold no limits
//!   of their own; they ask the policy and carry out the answer.
//!
//! [`bpf`] is the only module that uses the aya crate.

#[cfg(not(all(target_arch = "x86_64", target_os = "linux")))]
compile_error!("johnny-daemon supports x86_64 Linux only (ring memory ordering, bpf syscall ABI)");

pub mod bpf;
pub mod control;
pub mod daemon;
pub mod data;
pub mod stop;
pub mod sys;
pub mod tools;

pub use stop::Stop;
