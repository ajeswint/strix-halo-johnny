// SPDX-License-Identifier: GPL-2.0
/*
 * Johnny Module 1 slice 2: passive native-XDP program for eno1np0 (SPAN port)
 * that keeps every slice 1b counter and also writes one fixed-size,
 * HEADER-ONLY record per sampled frame to a BPF ring buffer.
 * Design:  docs/tool-install/module1-slice2-ringbuf-design.md
 * Runbook: docs/tool-install/module1-slice2-ringbuf.md (Phase C)
 *
 * Counters: m1_stats and m1_rxq have the slice 1b layout, slot order and
 * meaning (same partition), so the slice 1b/1c readback (STAT, STAT-RXQ,
 * PART l3_diff/l4_diff) runs unchanged against this program. The record path
 * has its own per-CPU counters in m2_ctl. Every frame that reaches the record
 * path lands in exactly one of SAMPLED_OUT / RATE_LIMITED / RB_FULL / EMITTED
 * / DISCARDED, so SEEN is their sum.
 *
 * Record (struct m2_rec, 80 bytes, version 1): only named header fields. The
 * record is built on the stack, zeroed first, filled field by field, then
 * copied whole into the reserved ring slot. Nothing copies a frame byte range
 * whose length depends on the frame. The farthest any read goes is: the
 * Ethernet header, up to two VLAN tags, the fixed 20-byte IPv4 / 40-byte IPv6
 * header, and at the L4 offset at most 14 bytes (TCP: ports and the flags
 * byte 13; UDP: ports; ICMP/ICMPv6: type and code). IPv4 options, IPv6
 * extension headers, ICMP bodies (which embed an original datagram), and any
 * byte past the L4 fields above are never read. A non-first IPv4 fragment has
 * no L4 header, so its L4 fields stay zero (reading them would read payload).
 * IPv6 extension headers are not walked: l4_proto keeps the next-header value,
 * F_IP6_EXT is set and the L4 fields stay zero.
 *
 * Sampling and bounds (runtime knobs in m2_cfg, written only by an AJ-run
 * paste; ver != 1 means "use the compiled defaults"):
 * - per CPU, deterministic 1-in-N (a counter, not random); N = 0 = records off
 *   (counters only, a kill switch that does not detach);
 * - per CPU, a token bucket on bpf_ktime_get_ns: rate records/s, burst;
 * - the ring is M2_RB_BYTES; when it is full the record is dropped and
 *   counted (RB_FULL). The program never waits and never retries.
 *
 * What it does NOT do: no XDP_DROP / XDP_TX / XDP_REDIRECT / XDP_ABORTED, no
 * redirect, no bpf_xdp_adjust_*, no bpf_xdp_load_bytes, no tail calls, no
 * AF_XDP, no ringbuf_output (copying), no random numbers. Helpers used:
 * bpf_map_lookup_elem (1), bpf_ktime_get_ns (5), bpf_ringbuf_reserve (131),
 * bpf_ringbuf_submit (132). The only `return` in the entry point is
 * XDP_PASS; the work is in a void helper. The rock-box self-test checks the
 * disassembly (helper ids, every r0 constant before exit is 2).
 *
 * Map slot orders below MUST match STAT_NAMES / CTL_NAMES in
 * module1-slice2-records.sh, and the record layout MUST match REC_FMT in
 * johnny-m1s2-reader.py (the self-test compares both).
 *
 * Build (off-box, rock-box; Johnny has no compiler): clang 22.1.8, see the
 * design doc section 9. The host self-test compiles this same file for x86-64
 * with -DM2_HOST_TEST (module1-slice2-host-test.c), so the parse that runs in
 * the kernel is the parse the test checks.
 */

#if __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error "little-endian only (Johnny is x86_64)"
#endif

typedef unsigned char __u8;
typedef unsigned short __u16;
typedef unsigned int __u32;
typedef unsigned long long __u64;

#define SEC(name) __attribute__((section(name), used))
#define __uint(name, val) int (*name)[val]
#define __type(name, val) typeof(val) *name
#define __always_inline inline __attribute__((always_inline))
#define BE16(x) __builtin_bswap16(x)

#define XDP_PASS 2
#define BPF_MAP_TYPE_ARRAY 2
#define BPF_MAP_TYPE_PERCPU_ARRAY 6
#define BPF_MAP_TYPE_RINGBUF 27

#define M2_REC_VERSION 1
#define M2_CFG_VERSION 1
#define M2_RB_BYTES (1 << 22) /* 4 MiB: power of two, page multiple */

/* Compiled defaults, used while m2_cfg.ver != M2_CFG_VERSION. */
#define M2_DEF_SAMPLE_EVERY 1
#define M2_DEF_RATE 2000 /* records/s per CPU */
#define M2_DEF_BURST 4000
/* Clamps on configured values (keep the token arithmetic far from overflow). */
#define M2_RATE_MAX 1000000
#define M2_BURST_MAX 100000

/* Slice 1b stats slots. Keep in this order (same as module1_xdp_observe.c). */
enum {
	K_PKTS = 0,
	K_BYTES,
	K_IPV4,
	K_IPV6,
	K_ARP,
	K_OTHER,
	K_TRUNC,
	K_VLAN,
	K_TCP,
	K_UDP,
	K_ICMP,
	K_L4_OTHER,
	K_MAX
};

/* Record-path counters (m2_ctl). Keep in this order. */
enum {
	C_SEEN = 0,
	C_SAMPLED_OUT,
	C_RATE_LIMITED,
	C_RB_FULL,
	C_EMITTED,
	C_DISCARDED,
	C_MAX
};

#define RXQ_MAX 64
/* m2_state slot RXQ_MAX holds this CPU's sampling and token-bucket state;
 * slots 0..RXQ_MAX-1 hold the per-queue record sequence (.ctr only). */
#define ST_CPU RXQ_MAX

/* m2_rec.flags */
#define F_TRUNC_L3 0x01 /* Ethernet / VLAN / fixed IP header cut short, or IP version / IHL invalid */
#define F_TRUNC_L4 0x02 /* L4 header expected but cut short */
#define F_FRAG 0x04 /* IPv4 fragment (MF set or offset != 0) */
#define F_IP6_EXT 0x08 /* IPv6 next header is an extension header; not walked, no L4 */
#define F_VLAN 0x10 /* at least one VLAN tag */
#define F_QINQ 0x20 /* two VLAN tags */
#define F_RL_RECOVERED 0x40 /* first record on this CPU after a rate-limited span */
#define F_VLAN_DEEP 0x80 /* a third VLAN tag; not parsed (ethertype is that tag's TPID) */

struct m2_rec {
	__u8 ver; /* 0  M2_REC_VERSION */
	__u8 flags; /* 1  F_* */
	__u16 rxq; /* 2  rx_queue_index, capped at 0xffff */
	__u32 wire_len; /* 4  data_end - data (linear frame, no FCS) */
	__u64 ts_ns; /* 8  bpf_ktime_get_ns (CLOCK_MONOTONIC) */
	__u8 dst_mac[6]; /* 16 */
	__u8 src_mac[6]; /* 22 */
	__u16 ethertype; /* 28 innermost after <= 2 VLAN tags, host order */
	__u16 vlan_tci; /* 30 outer tag TCI, host order, 0 if none */
	__u8 src_ip[16]; /* 32 IPv4 in the first 4 bytes, rest 0; or IPv6 */
	__u8 dst_ip[16]; /* 48 */
	__u8 l4_proto; /* 64 IPv4 protocol / IPv6 next header (not walked) */
	__u8 ttl_hlim; /* 65 */
	__u16 l3_len; /* 66 IPv4 total length / IPv6 payload length + 40 (capped) */
	__u16 sport; /* 68 TCP/UDP source port; ICMP/ICMPv6: type << 8 | code */
	__u16 dport; /* 70 TCP/UDP destination port */
	__u8 tcp_flags; /* 72 TCP header byte 13 */
	__u8 rsv0; /* 73 0 */
	__u16 rsv1; /* 74 0 */
	__u32 seq_lo; /* 76 per-queue record sequence, low 32 bits */
};

_Static_assert(sizeof(struct m2_rec) == 80, "m2_rec size");
_Static_assert(__builtin_offsetof(struct m2_rec, wire_len) == 4, "m2_rec wire_len");
_Static_assert(__builtin_offsetof(struct m2_rec, ts_ns) == 8, "m2_rec ts_ns");
_Static_assert(__builtin_offsetof(struct m2_rec, dst_mac) == 16, "m2_rec dst_mac");
_Static_assert(__builtin_offsetof(struct m2_rec, ethertype) == 28, "m2_rec ethertype");
_Static_assert(__builtin_offsetof(struct m2_rec, src_ip) == 32, "m2_rec src_ip");
_Static_assert(__builtin_offsetof(struct m2_rec, l4_proto) == 64, "m2_rec l4_proto");
_Static_assert(__builtin_offsetof(struct m2_rec, sport) == 68, "m2_rec sport");
_Static_assert(__builtin_offsetof(struct m2_rec, tcp_flags) == 72, "m2_rec tcp_flags");
_Static_assert(__builtin_offsetof(struct m2_rec, seq_lo) == 76, "m2_rec seq_lo");

struct m2_cfg {
	__u32 ver; /* M2_CFG_VERSION, else the compiled defaults apply */
	__u32 sample_every; /* N: 1 in N per CPU; 0 = records off */
	__u32 rate; /* records/s per CPU; 0 = records off */
	__u32 burst; /* token bucket depth, records */
};

_Static_assert(sizeof(struct m2_cfg) == 16, "m2_cfg size");

struct m2_st {
	__u64 ctr; /* ST_CPU: sampling counter; queue slots: record sequence */
	__u64 credit_ns; /* ST_CPU: token bucket credit, in ns of rate */
	__u64 last_ns; /* ST_CPU: last refill time, 0 = never */
	__u64 limited; /* ST_CPU: 1 while in a rate-limited span */
};

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, K_MAX);
	__type(key, __u32);
	__type(value, __u64);
} m1_stats SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, RXQ_MAX);
	__type(key, __u32);
	__type(value, __u64);
} m1_rxq SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, C_MAX);
	__type(key, __u32);
	__type(value, __u64);
} m2_ctl SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, struct m2_cfg);
} m2_cfg SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, RXQ_MAX + 1);
	__type(key, __u32);
	__type(value, struct m2_st);
} m2_state SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, M2_RB_BYTES);
} m2_rb SEC(".maps");

#ifndef M2_HOST_TEST
static void *(*bpf_map_lookup_elem)(void *map, const void *key) = (void *)1;
static __u64 (*bpf_ktime_get_ns)(void) = (void *)5;
static void *(*bpf_ringbuf_reserve)(void *ringbuf, __u64 size, __u64 flags) = (void *)131;
static void (*bpf_ringbuf_submit)(void *data, __u64 flags) = (void *)132;

struct xdp_md {
	__u32 data;
	__u32 data_end;
	__u32 data_meta;
	__u32 ingress_ifindex;
	__u32 rx_queue_index;
	__u32 egress_ifindex;
};

#define M2_DATA(ctx) ((void *)(long)(ctx)->data)
#define M2_DATA_END(ctx) ((void *)(long)(ctx)->data_end)
#endif

struct eth_hdr {
	__u8 dst[6];
	__u8 src[6];
	__u16 proto; /* network byte order */
} __attribute__((packed));

struct vlan_hdr {
	__u16 tci;
	__u16 encap; /* network byte order */
} __attribute__((packed));

/* Fixed part only; options are never read. */
struct ip4_hdr {
	__u8 ver_ihl;
	__u8 tos;
	__u16 tot_len;
	__u16 id;
	__u16 frag_off;
	__u8 ttl;
	__u8 protocol;
	__u16 check;
	__u8 saddr[4];
	__u8 daddr[4];
} __attribute__((packed));

/* Fixed part only; extension headers are never read. */
struct ip6_hdr {
	__u8 vtc0; /* version (high nibble) */
	__u8 vtc1;
	__u16 flow_lo;
	__u16 payload_len;
	__u8 nexthdr;
	__u8 hop_limit;
	__u8 saddr[16];
	__u8 daddr[16];
} __attribute__((packed));

static __always_inline void bump(__u32 slot, __u64 n)
{
	__u32 key = slot;
	__u64 *v = bpf_map_lookup_elem(&m1_stats, &key);

	/* Per-CPU slot: this CPU is the only writer, so a plain add is enough. */
	if (v)
		*v += n;
}

static __always_inline void ctl(__u32 slot)
{
	__u32 key = slot;
	__u64 *v = bpf_map_lookup_elem(&m2_ctl, &key);

	if (v)
		*v += 1;
}

static __always_inline void bump_l4(__u8 l4)
{
	if (l4 == 6)
		bump(K_TCP, 1);
	else if (l4 == 17)
		bump(K_UDP, 1);
	else if (l4 == 1 || l4 == 58) /* ICMP, ICMPv6 */
		bump(K_ICMP, 1);
	else
		bump(K_L4_OTHER, 1);
}

static __always_inline void copy4(__u8 *dst, const __u8 *src)
{
	dst[0] = src[0];
	dst[1] = src[1];
	dst[2] = src[2];
	dst[3] = src[3];
}

static __always_inline void copy6(__u8 *dst, const __u8 *src)
{
	copy4(dst, src);
	dst[4] = src[4];
	dst[5] = src[5];
}

static __always_inline void copy16(__u8 *dst, const __u8 *src)
{
	copy4(dst, src);
	copy4(dst + 4, src + 4);
	copy4(dst + 8, src + 8);
	copy4(dst + 12, src + 12);
}

/*
 * L4 fields at p. Called only when an L4 header is there (not a non-first
 * fragment, not an extension header). Reads at most 14 bytes from p.
 */
static __always_inline void parse_l4(struct m2_rec *r, void *p, void *data_end)
{
	__u8 *b = p;

	if (r->l4_proto == 6) {
		if ((void *)(b + 14) > data_end) {
			r->flags |= F_TRUNC_L4;
			return;
		}
		r->sport = (__u16)((b[0] << 8) | b[1]);
		r->dport = (__u16)((b[2] << 8) | b[3]);
		r->tcp_flags = b[13];
	} else if (r->l4_proto == 17) {
		if ((void *)(b + 4) > data_end) {
			r->flags |= F_TRUNC_L4;
			return;
		}
		r->sport = (__u16)((b[0] << 8) | b[1]);
		r->dport = (__u16)((b[2] << 8) | b[3]);
	} else if (r->l4_proto == 1 || r->l4_proto == 58) {
		/* ICMP in IPv4, ICMPv6 in IPv6 (the caller only gets 58 from IPv6
		 * and 1 from IPv4 in practice; either way only type and code). */
		if ((void *)(b + 2) > data_end) {
			r->flags |= F_TRUNC_L4;
			return;
		}
		r->sport = (__u16)((b[0] << 8) | b[1]);
	}
}

static __always_inline void parse_ip4(struct m2_rec *r, void *p, void *data_end)
{
	struct ip4_hdr *ip = p;
	__u32 ihl;
	__u16 fo;

	if ((void *)(ip + 1) > data_end) {
		r->flags |= F_TRUNC_L3;
		bump(K_TRUNC, 1);
		return;
	}
	/* Slice 1b classification: any frame with a full fixed header. */
	bump(K_IPV4, 1);
	bump_l4(ip->protocol);

	r->l3_len = BE16(ip->tot_len);
	r->ttl_hlim = ip->ttl;
	r->l4_proto = ip->protocol;
	copy4(r->src_ip, ip->saddr);
	copy4(r->dst_ip, ip->daddr);
	ihl = ip->ver_ihl & 0x0f;
	if ((ip->ver_ihl >> 4) != 4 || ihl < 5) {
		r->flags |= F_TRUNC_L3;
		return;
	}
	fo = BE16(ip->frag_off);
	if (fo & 0x3fff) /* MF or offset */
		r->flags |= F_FRAG;
	if (fo & 0x1fff) /* non-first fragment: no L4 header */
		return;
	/* ihl is 5..15, so the L4 offset is 20..60 bytes: options are skipped, not read. */
	parse_l4(r, (__u8 *)p + ihl * 4, data_end);
}

static __always_inline void parse_ip6(struct m2_rec *r, void *p, void *data_end)
{
	struct ip6_hdr *ip6 = p;
	__u32 len;
	__u8 nh;

	if ((void *)(ip6 + 1) > data_end) {
		r->flags |= F_TRUNC_L3;
		bump(K_TRUNC, 1);
		return;
	}
	bump(K_IPV6, 1);
	bump_l4(ip6->nexthdr);

	len = (__u32)BE16(ip6->payload_len) + 40;
	r->l3_len = len > 0xffff ? 0xffff : (__u16)len;
	r->ttl_hlim = ip6->hop_limit;
	nh = ip6->nexthdr;
	r->l4_proto = nh;
	copy16(r->src_ip, ip6->saddr);
	copy16(r->dst_ip, ip6->daddr);
	if ((ip6->vtc0 >> 4) != 6) {
		r->flags |= F_TRUNC_L3;
		return;
	}
	/* Hop-by-hop, routing, fragment, ESP, AH, destination options, mobility,
	 * HIP, shim6, experimental: not walked (design section 3). */
	if (nh == 0 || nh == 43 || nh == 44 || nh == 50 || nh == 51 || nh == 60 || nh == 135 ||
	    nh == 139 || nh == 140 || nh == 253 || nh == 254) {
		r->flags |= F_IP6_EXT;
		return;
	}
	parse_l4(r, ip6 + 1, data_end);
}

/*
 * Count the frame (slice 1b partition, unchanged) and fill r from its headers.
 * Never reads past the fields listed at the top of this file.
 */
static __always_inline void parse(struct m2_rec *r, void *data, void *data_end)
{
	struct eth_hdr *eth = data;
	__u16 proto;
	void *p;

	if ((void *)(eth + 1) > data_end) {
		r->flags |= F_TRUNC_L3;
		bump(K_TRUNC, 1);
		return;
	}
	copy6(r->dst_mac, eth->dst);
	copy6(r->src_mac, eth->src);
	proto = eth->proto;
	p = eth + 1;

#pragma unroll
	for (int i = 0; i < 2; i++) {
		if (proto == BE16(0x8100) || proto == BE16(0x88a8)) {
			struct vlan_hdr *vh = p;

			if ((void *)(vh + 1) > data_end) {
				r->ethertype = BE16(proto);
				r->flags |= F_TRUNC_L3;
				bump(K_TRUNC, 1);
				return;
			}
			if (i == 0) {
				bump(K_VLAN, 1);
				r->vlan_tci = BE16(vh->tci);
				r->flags |= F_VLAN;
			} else {
				r->flags |= F_QINQ;
			}
			proto = vh->encap;
			p = vh + 1;
		}
	}
	r->ethertype = BE16(proto);

	if (proto == BE16(0x0800)) {
		parse_ip4(r, p, data_end);
	} else if (proto == BE16(0x86dd)) {
		parse_ip6(r, p, data_end);
	} else if (proto == BE16(0x0806)) {
		bump(K_ARP, 1);
	} else {
		if (proto == BE16(0x8100) || proto == BE16(0x88a8))
			r->flags |= F_VLAN_DEEP;
		bump(K_OTHER, 1);
	}
}

/*
 * Sampling and token bucket. Returns 1 if this frame may take a ring slot.
 * Counts SAMPLED_OUT / RATE_LIMITED itself. Sets F_RL_RECOVERED on the first
 * record after a rate-limited span.
 */
static __always_inline int admit(struct m2_rec *r, __u64 now)
{
	__u32 zero = 0, cpu_slot = ST_CPU;
	struct m2_cfg *c = bpf_map_lookup_elem(&m2_cfg, &zero);
	struct m2_st *s = bpf_map_lookup_elem(&m2_state, &cpu_slot);
	__u64 n = M2_DEF_SAMPLE_EVERY, rate = M2_DEF_RATE, burst = M2_DEF_BURST;
	__u64 cost, cap, elapsed, ctr;

	if (c && c->ver == M2_CFG_VERSION) {
		n = c->sample_every;
		rate = c->rate;
		burst = c->burst;
	}
	if (!s || n == 0) {
		ctl(C_SAMPLED_OUT);
		return 0;
	}
	ctr = s->ctr;
	s->ctr = ctr + 1;
	if (n > 1 && ctr % n != 0) {
		ctl(C_SAMPLED_OUT);
		return 0;
	}
	if (rate == 0) {
		ctl(C_RATE_LIMITED);
		return 0;
	}
	if (rate > M2_RATE_MAX)
		rate = M2_RATE_MAX;
	if (burst == 0)
		burst = 1;
	if (burst > M2_BURST_MAX)
		burst = M2_BURST_MAX;
	cost = 1000000000ULL / rate;
	cap = burst * cost;
	if (s->last_ns == 0) {
		s->credit_ns = cap; /* start full */
	} else {
		elapsed = now > s->last_ns ? now - s->last_ns : 0;
		if (elapsed > cap)
			elapsed = cap;
		s->credit_ns += elapsed;
	}
	if (s->credit_ns > cap)
		s->credit_ns = cap;
	s->last_ns = now;
	if (s->credit_ns < cost) {
		s->limited = 1;
		ctl(C_RATE_LIMITED);
		return 0;
	}
	s->credit_ns -= cost;
	if (s->limited) {
		s->limited = 0;
		r->flags |= F_RL_RECOVERED;
	}
	return 1;
}

static __always_inline void observe(struct xdp_md *ctx)
{
	void *data = M2_DATA(ctx);
	void *data_end = M2_DATA_END(ctx);
	__u32 qkey = ctx->rx_queue_index;
	__u64 flen = (__u64)(data_end - data);
	struct m2_st *qs;
	struct m2_rec r;
	struct m2_rec *slot;
	__u64 *qv;
	__u64 now;

	__builtin_memset(&r, 0, sizeof(r));

	/* 1. Slice 1b counters: every frame. */
	bump(K_PKTS, 1);
	bump(K_BYTES, flen);
	/* Out-of-range queue index: lookup returns NULL and nothing is counted. */
	qv = bpf_map_lookup_elem(&m1_rxq, &qkey);
	if (qv)
		*qv += 1;
	parse(&r, data, data_end);

	/* 2. Record path: sample, rate limit, reserve, fill, submit. */
	ctl(C_SEEN);
	now = bpf_ktime_get_ns();
	if (!admit(&r, now))
		return;

	r.ver = M2_REC_VERSION;
	r.rxq = qkey > 0xffff ? 0xffff : (__u16)qkey;
	r.wire_len = (__u32)flen;
	r.ts_ns = now;
	/* Per-queue sequence: counts every reserve attempt, so a gap the reader
	 * sees on a queue is a RB_FULL drop on that queue. Queue >= RXQ_MAX: 0. */
	if (qkey < RXQ_MAX) {
		qs = bpf_map_lookup_elem(&m2_state, &qkey);
		if (qs) {
			r.seq_lo = (__u32)qs->ctr;
			qs->ctr += 1;
		}
	}

	slot = bpf_ringbuf_reserve(&m2_rb, sizeof(struct m2_rec), 0);
	if (!slot) {
		ctl(C_RB_FULL);
		return;
	}
	__builtin_memcpy(slot, &r, sizeof(struct m2_rec));
	bpf_ringbuf_submit(slot, 0);
	ctl(C_EMITTED);
}

SEC("xdp")
int j_xdp_records(struct xdp_md *ctx)
{
	observe(ctx);
	return XDP_PASS;
}

char _license[] SEC("license") = "GPL";
