//! A synthetic ring in ordinary memory, laid out the way the consumer sees
//! the kernel's: a consumer position, a producer position, and the data
//! area mapped twice. Test support for Rock Box, where no BPF map can be
//! created without privilege. The daemon binary does not use it.

use johnny_record_v1::REC_SIZE;

use crate::data::ring::{Ring, RB_BUSY, RB_DISCARD, RB_HDR};
use crate::stop::Stop;

pub const FRAME: u64 = RB_HDR + REC_SIZE as u64;

pub struct SynthRing {
    /// `[consumer_pos][producer_pos][data: 2 * size bytes]` as u64 words.
    /// Held and used only as a raw pointer, so the consumer's pointers into
    /// the same allocation stay valid while the producer side writes.
    base: *mut u64,
    words: usize,
    size: u64,
}

impl Drop for SynthRing {
    fn drop(&mut self) {
        // SAFETY: base and words are the boxed slice leaked in new().
        unsafe {
            drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
                self.base, self.words,
            )));
        }
    }
}

impl SynthRing {
    pub fn new(size: u64) -> Self {
        assert!(size >= 4096 && size.is_power_of_two());
        let words = 2 + (2 * size / 8) as usize;
        let base = Box::into_raw(vec![0u64; words].into_boxed_slice()).cast::<u64>();
        SynthRing { base, words, size }
    }

    pub fn consumer_pos(&self) -> u64 {
        // SAFETY: word 0 of the allocation.
        unsafe { self.base.read_volatile() }
    }

    pub fn producer_pos(&self) -> u64 {
        // SAFETY: word 1 of the allocation.
        unsafe { self.base.add(1).read_volatile() }
    }

    pub fn set_positions(&mut self, cons: u64, prod: u64) {
        // SAFETY: words 0 and 1 of the allocation.
        unsafe {
            self.base.write_volatile(cons);
            self.base.add(1).write_volatile(prod);
        }
    }

    fn put(&mut self, pos: u64, bytes: &[u8]) {
        let size = self.size;
        // SAFETY: the data area is words 2.. of the allocation, 2 * size bytes.
        let data = unsafe { self.base.add(2).cast::<u8>() };
        for (i, b) in bytes.iter().enumerate() {
            let at = ((pos + i as u64) % size) as usize;
            // SAFETY: at < size, and at + size < 2 * size.
            unsafe {
                data.add(at).write_volatile(*b);
                data.add(at + size as usize).write_volatile(*b);
            }
        }
    }

    /// Write a raw header word at `pos` without moving the producer.
    pub fn put_header(&mut self, pos: u64, hdr: u32) {
        self.put(pos, &hdr.to_le_bytes());
    }

    /// Append one frame the way `bpf_ringbuf_reserve` + submit would, with
    /// header word `hdr` (the length, plus `BUSY` or `DISCARD`). Returns
    /// its position. Panics if the ring is full: a scenario must not overrun.
    pub fn produce_raw(&mut self, hdr: u32, rec: &[u8; REC_SIZE]) -> u64 {
        let pos = self.producer_pos();
        assert!(
            pos - self.consumer_pos() + FRAME <= self.size,
            "synthetic ring full"
        );
        let mut frame = [0u8; FRAME as usize];
        frame[0..4].copy_from_slice(&hdr.to_le_bytes());
        frame[8..].copy_from_slice(rec);
        self.put(pos, &frame);
        let cons = self.consumer_pos();
        self.set_positions(cons, pos + FRAME);
        pos
    }

    /// `produce_raw` with the right length and `flags` (`BUSY`, `DISCARD`, or 0).
    pub fn produce(&mut self, flags: u32, rec: &[u8; REC_SIZE]) -> u64 {
        self.produce_raw(REC_SIZE as u32 | flags, rec)
    }

    /// Clear BUSY on the frame at `pos`; set DISCARD if `discard`.
    pub fn commit(&mut self, pos: u64, discard: bool) {
        let hdr = REC_SIZE as u32 | if discard { RB_DISCARD } else { 0 };
        self.put_header(pos, hdr);
    }

    /// A consumer over this memory.
    ///
    /// # Safety
    ///
    /// The `SynthRing` must outlive the returned `Ring`.
    pub unsafe fn consumer(&mut self) -> Result<Ring, Stop> {
        Ring::from_raw(
            self.base,
            self.base.add(1),
            self.base.add(2).cast::<u8>(),
            self.size,
            None,
        )
    }
}

/// The header flag for a frame still being written.
pub const BUSY: u32 = RB_BUSY;
/// The header flag for a frame the producer gave up on.
pub const DISCARD: u32 = RB_DISCARD;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::control::config::UnknownVersion::{Skip, Stop as StopOn};

    fn rec(seq: u32) -> [u8; REC_SIZE] {
        let mut r = [0u8; REC_SIZE];
        r[0] = 1;
        r[76..80].copy_from_slice(&seq.to_le_bytes());
        r
    }

    fn drain_all(ring: &mut Ring, policy: UnknownVersion) -> Result<Vec<u32>, Stop> {
        let mut got = Vec::new();
        ring.drain(usize::MAX, policy, &mut |raw| {
            got.push(u32::from_le_bytes([raw[76], raw[77], raw[78], raw[79]]));
            Ok(())
        })?;
        Ok(got)
    }
    use crate::control::config::UnknownVersion;

    // The same steps as the ring part of
    // docs/tool-install/module1-slice2b-self-test.sh (section 4, "1. Ring
    // consumer test").
    #[test]
    fn self_test_ring_steps() {
        let mut s = SynthRing::new(4096);
        let mut ring = unsafe { s.consumer() }.unwrap();
        assert_eq!(drain_all(&mut ring, StopOn).unwrap(), Vec::<u32>::new());

        s.produce(0, &rec(100));
        assert_eq!(drain_all(&mut ring, StopOn).unwrap(), vec![100]);
        assert_eq!(s.consumer_pos(), s.producer_pos());

        s.produce(DISCARD, &rec(101));
        assert_eq!(drain_all(&mut ring, StopOn).unwrap(), Vec::<u32>::new());
        assert_eq!(ring.discarded(), 1);

        let busy = s.produce(BUSY, &rec(102));
        assert_eq!(drain_all(&mut ring, StopOn).unwrap(), Vec::<u32>::new());
        assert_eq!(s.consumer_pos(), busy, "a busy record is not passed");

        s.put_header(busy, 99);
        assert_eq!(
            drain_all(&mut ring, StopOn).unwrap_err().to_string(),
            format!("STOP-ring-corrupt len=99 cons={busy} prod={}", busy + FRAME)
        );

        s.set_positions(500, 400);
        assert_eq!(
            drain_all(&mut ring, StopOn).unwrap_err().to_string(),
            "STOP-ring-corrupt positions cons=500 prod=400"
        );
    }

    #[test]
    fn busy_then_commit_resumes_in_order() {
        let mut s = SynthRing::new(4096);
        let mut ring = unsafe { s.consumer() }.unwrap();
        s.produce(0, &rec(1));
        let busy = s.produce(BUSY, &rec(2));
        s.produce(0, &rec(3));
        assert_eq!(drain_all(&mut ring, Skip).unwrap(), vec![1]);
        assert_eq!(ring.backlog(), 2 * FRAME);
        s.commit(busy, false);
        assert_eq!(drain_all(&mut ring, Skip).unwrap(), vec![2, 3]);
        assert_eq!(ring.backlog(), 0);
    }

    #[test]
    fn wraps_many_times() {
        // 4096 / 88 is not whole, so frames straddle the end of the data area.
        let mut s = SynthRing::new(4096);
        let mut ring = unsafe { s.consumer() }.unwrap();
        let mut want = Vec::new();
        let mut got = Vec::new();
        for seq in 0..1000u32 {
            s.produce(0, &rec(seq));
            want.push(seq);
            if seq % 7 == 0 {
                got.extend(drain_all(&mut ring, Skip).unwrap());
            }
        }
        got.extend(drain_all(&mut ring, Skip).unwrap());
        assert_eq!(got, want);
        assert_eq!(s.consumer_pos(), 1000 * FRAME);
    }

    #[test]
    fn overrun_positions_stop() {
        let mut s = SynthRing::new(4096);
        let mut ring = unsafe { s.consumer() }.unwrap();
        s.set_positions(0, 4097);
        assert_eq!(
            drain_all(&mut ring, Skip).unwrap_err().to_string(),
            "STOP-ring-corrupt positions cons=0 prod=4097"
        );
    }

    #[test]
    fn record_past_producer_stops() {
        let mut s = SynthRing::new(4096);
        let mut ring = unsafe { s.consumer() }.unwrap();
        s.produce(0, &rec(1));
        s.set_positions(0, 80);
        assert_eq!(
            drain_all(&mut ring, Skip).unwrap_err().to_string(),
            "STOP-ring-corrupt len=80 cons=0 prod=80"
        );
    }

    #[test]
    fn unknown_version_follows_the_policy() {
        let mut v2 = rec(2);
        v2[0] = 2;

        let mut s = SynthRing::new(4096);
        let mut ring = unsafe { s.consumer() }.unwrap();
        s.produce(0, &rec(1));
        s.produce(0, &v2);
        s.produce(0, &rec(3));
        assert_eq!(drain_all(&mut ring, Skip).unwrap(), vec![1, 3]);
        assert_eq!(ring.unknown_version(), 1);
        assert_eq!(ring.backlog(), 0);

        let mut s = SynthRing::new(4096);
        let mut ring = unsafe { s.consumer() }.unwrap();
        s.produce(0, &rec(1));
        let at = s.produce(0, &v2);
        s.produce(0, &rec(3));
        assert_eq!(
            drain_all(&mut ring, StopOn).unwrap_err().to_string(),
            "STOP-ring-corrupt ver=2"
        );
        assert_eq!(s.consumer_pos(), at, "the stop does not pass the record");
    }

    #[test]
    fn sink_error_leaves_the_record_in_the_ring() {
        let mut s = SynthRing::new(4096);
        let mut ring = unsafe { s.consumer() }.unwrap();
        s.produce(0, &rec(1));
        let second = s.produce(0, &rec(2));
        let mut calls = 0;
        let err = ring
            .drain(10, Skip, &mut |_| {
                calls += 1;
                if calls == 2 {
                    Err(Stop("x".into()))
                } else {
                    Ok(())
                }
            })
            .unwrap_err();
        assert_eq!(err, Stop("x".into()));
        assert_eq!(s.consumer_pos(), second);
    }

    #[test]
    fn max_n_bounds_one_drain() {
        let mut s = SynthRing::new(4096);
        let mut ring = unsafe { s.consumer() }.unwrap();
        for seq in 0..10 {
            s.produce(0, &rec(seq));
        }
        let mut n = 0;
        assert_eq!(ring.drain(4, Skip, &mut |_| { n += 1; Ok(()) }).unwrap(), 4);
        assert_eq!(n, 4);
        assert_eq!(ring.backlog(), 6 * FRAME);
    }

    #[test]
    fn bad_sizes() {
        for size in [0u64, 100, 4095, 6000] {
            let mut word = 0u64;
            let p: *mut u64 = &mut word;
            let r = unsafe { Ring::from_raw(p, p, p.cast::<u8>(), size, None) };
            assert_eq!(r.err().unwrap().to_string(), format!("STOP-ring-size {size}"));
        }
    }
}
