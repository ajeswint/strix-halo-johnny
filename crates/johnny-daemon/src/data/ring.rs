//! Consumer side of a BPF_MAP_TYPE_RINGBUF mapping
//! (https://docs.kernel.org/bpf/ringbuf.html). A port of the Python
//! reader's `Ring` (`docs/tool-install/johnny-m1s2b-reader.py:94-136`):
//! same checks, same order, same STOP text.
//!
//! A structurally bad ring (positions, record length) stops the daemon; it
//! never skips ahead. A well-framed 80-byte record with an unknown version
//! byte follows the policy: skipped and counted, or a stop.

use std::any::Any;
use std::ptr;
use std::sync::atomic::{AtomicU64, Ordering};

use johnny_record_v1::{REC_SIZE, REC_VERSION};

use crate::control::config::UnknownVersion;
use crate::stop;
use crate::stop::Stop;

pub const RB_BUSY: u32 = 1 << 31;
pub const RB_DISCARD: u32 = 1 << 30;
pub const RB_HDR: u64 = 8;

pub struct Ring {
    cons: *mut u64,
    prod: *const u64,
    data: *const u8,
    size: u64,
    mask: u64,
    discarded: u64,
    unknown_version: u64,
    _keepalive: Option<Box<dyn Any>>,
}

impl Ring {
    /// # Safety
    ///
    /// `cons` must point to a writable, 8-aligned u64 (the consumer
    /// position). `prod` must point to a readable, 8-aligned u64 (the
    /// producer position). `data` must point to `2 * size` readable bytes,
    /// 8-aligned, in which byte `i` and byte `i + size` are the same memory
    /// (the kernel maps the data pages twice). All three must stay valid
    /// for the life of the `Ring`; `keepalive` is dropped with it.
    pub unsafe fn from_raw(
        cons: *mut u64,
        prod: *const u64,
        data: *const u8,
        size: u64,
        keepalive: Option<Box<dyn Any>>,
    ) -> Result<Ring, Stop> {
        if size < 4096 || size & (size - 1) != 0 {
            return Err(stop!("ring-size {size}"));
        }
        Ok(Ring {
            cons,
            prod,
            data,
            size,
            mask: size - 1,
            discarded: 0,
            unknown_version: 0,
            _keepalive: keepalive,
        })
    }

    fn consumer_pos(&self) -> u64 {
        // SAFETY: from_raw's contract. Only this consumer writes it.
        unsafe { AtomicU64::from_ptr(self.cons).load(Ordering::Relaxed) }
    }

    fn producer_pos(&self) -> u64 {
        // SAFETY: from_raw's contract. The kernel writes this word; an
        // aligned 8-byte volatile read is one load on x86-64.
        unsafe { ptr::read_volatile(self.prod) }
    }

    /// Records the kernel discarded after reserving (skipped, not written).
    pub fn discarded(&self) -> u64 {
        self.discarded
    }

    /// Records skipped because their version byte is not 1.
    pub fn unknown_version(&self) -> u64 {
        self.unknown_version
    }

    /// Bytes produced and not yet consumed.
    pub fn backlog(&self) -> u64 {
        self.producer_pos().wrapping_sub(self.consumer_pos())
    }

    /// Hand up to `max_n` records to `sink`. Returns the number handed.
    /// The consumer position moves past a record only after `sink` took it.
    pub fn drain(
        &mut self,
        max_n: usize,
        on_unknown: UnknownVersion,
        sink: &mut dyn FnMut(&[u8; REC_SIZE]) -> Result<(), Stop>,
    ) -> Result<usize, Stop> {
        let mut cons = self.consumer_pos();
        let prod = self.producer_pos();
        if prod < cons || prod - cons > self.size {
            return Err(stop!("ring-corrupt positions cons={cons} prod={prod}"));
        }
        let mut n = 0;
        while cons < prod && n < max_n {
            let off = (cons & self.mask) as usize;
            // SAFETY: off < size and is 8-aligned (positions advance in
            // multiples of 8), so the header word is inside the mapping.
            let hdr = unsafe { ptr::read_volatile(self.data.add(off).cast::<u32>()) };
            if hdr & RB_BUSY != 0 {
                break;
            }
            let len = u64::from(hdr & !(RB_BUSY | RB_DISCARD));
            let step = (len + RB_HDR + 7) & !7;
            if len != REC_SIZE as u64 || cons + step > prod {
                return Err(stop!("ring-corrupt len={len} cons={cons} prod={prod}"));
            }
            if hdr & RB_DISCARD != 0 {
                self.discarded += 1;
            } else {
                let mut raw = [0u8; REC_SIZE];
                // SAFETY: off + 8 + 80 <= size + 88 <= 2 * size, inside
                // the double mapping. The kernel does not touch a
                // committed record again.
                unsafe {
                    ptr::copy_nonoverlapping(
                        self.data.add(off + RB_HDR as usize),
                        raw.as_mut_ptr(),
                        REC_SIZE,
                    );
                }
                if raw[0] != REC_VERSION {
                    match on_unknown {
                        UnknownVersion::Stop => {
                            return Err(stop!("ring-corrupt ver={}", raw[0]));
                        }
                        UnknownVersion::Skip => self.unknown_version += 1,
                    }
                } else {
                    sink(&raw)?;
                    n += 1;
                }
            }
            cons += step;
            // Release store after the data reads.
            // SAFETY: from_raw's contract.
            unsafe { AtomicU64::from_ptr(self.cons).store(cons, Ordering::Release) };
        }
        Ok(n)
    }
}
