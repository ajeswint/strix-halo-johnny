//! Data plane (the enforcement point): the ring consumer and the run-file
//! writer. It holds no limits of its own. It asks `control::policy` and
//! carries out the answer.

pub mod ring;
pub mod synth;
pub mod writer;

use johnny_record_v1::M2Cfg;

use crate::stop::Stop;

/// The pinned maps other than the ring's memory: what the kernel side says
/// about itself. `bpf::PinnedMaps` is the real one.
pub trait KernelMaps {
    fn ring_map_id(&self) -> u32;
    /// `m2_cfg[0]`.
    fn read_cfg(&self) -> Result<M2Cfg, Stop>;
    /// `m2_ctl` summed over CPUs, in `CTL_NAMES` order.
    fn read_ctl(&self) -> Result<[u64; 6], Stop>;
    /// Sleep until the ring has data or `timeout_ms` passes.
    fn wait(&self, timeout_ms: i32);
}
