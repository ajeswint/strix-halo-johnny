// SPDX-License-Identifier: GPL-2.0
/*
 * Johnny Module 1 slice 2: host-side test of module1_xdp_records.c.
 *
 * Compiles the SAME source as the BPF object, for x86-64, with -DM2_HOST_TEST,
 * and fakes the four helpers and the maps. No kernel, no root, no NIC.
 *
 * Checks:
 *   LAYOUT      sizeof / offsetof of every m2_rec field; prints REC-FMT, the
 *               Python struct format built from the offsets (the self-test
 *               compares it with REC_FMT in johnny-m1s2-reader.py).
 *   PARSE       crafted frames: TCP, UDP, ICMP, ICMPv6, IPv4 options, IHL < 5,
 *               first and non-first IPv4 fragment, IPv6 ext header, ARP,
 *               short Ethernet, short VLAN, 1 / 2 / 3 VLAN tags, cut TCP.
 *   NO-PAYLOAD  for every frame, the record is byte-identical after the
 *               payload, IP options, TCP options/seq/ack/window/checksum,
 *               IP ID, DSCP/ECN and IP checksum are rewritten with random
 *               bytes; no 4-byte window of a payload sentinel is in a record.
 *   SAMPLING    1-in-N exact and deterministic; N = 0 is records off.
 *   RATE        token bucket: burst at one instant, refill by elapsed time,
 *               rate 0, clamps, F_RL_RECOVERED once per limited span.
 *   RB-FULL     reserve fails: C_RB_FULL counts, the per-queue sequence
 *               shows the gap, nothing is submitted.
 *   ACCOUNTING  per CPU, after every scenario: SEEN = SAMPLED_OUT +
 *               RATE_LIMITED + RB_FULL + EMITTED + DISCARDED; slice 1b
 *               partition l3_diff = l4_diff = 0; PKTS = SEEN.
 *
 * Prints HOST-TEST-OK cases=N on success; any failure prints HOST-TEST-FAIL
 * and exits 1.
 */
#define M2_HOST_TEST 1

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>

typedef unsigned char __u8;
typedef unsigned short __u16;
typedef unsigned int __u32;
typedef unsigned long long __u64;

struct xdp_md {
	void *data;
	void *data_end;
	__u32 rx_queue_index;
};
#define M2_DATA(ctx) ((ctx)->data)
#define M2_DATA_END(ctx) ((ctx)->data_end)

static void *bpf_map_lookup_elem(void *map, const void *key);
static __u64 bpf_ktime_get_ns(void);
static void *bpf_ringbuf_reserve(void *ringbuf, __u64 size, __u64 flags);
static void bpf_ringbuf_submit(void *data, __u64 flags);

/* The source re-declares the __uN typedefs (identical typedefs are legal C11)
 * and defines __always_inline, which glibc's sys/cdefs.h already defined. */
#undef __always_inline
#include "module1_xdp_records.c"

/* ------------------------------------------------------------- fakes */

#define NCPU 4
#define MAXREC 40000

static int cpu;
static __u64 now_ns;
static long rb_room = -1; /* reserves left before NULL; -1 = unlimited */
static __u64 f_stats[NCPU][K_MAX];
static __u64 f_rxq[NCPU][RXQ_MAX];
static __u64 f_ctl[NCPU][C_MAX];
static struct m2_st f_state[NCPU][RXQ_MAX + 1];
static struct m2_cfg f_cfg;
static int cfg_missing;
static struct m2_rec recs[MAXREC];
static int nrec, reserved_open;

static void *bpf_map_lookup_elem(void *map, const void *key)
{
	__u32 k = *(const __u32 *)key;

	if (map == &m1_stats)
		return k < K_MAX ? &f_stats[cpu][k] : NULL;
	if (map == &m1_rxq)
		return k < RXQ_MAX ? &f_rxq[cpu][k] : NULL;
	if (map == &m2_ctl)
		return k < C_MAX ? &f_ctl[cpu][k] : NULL;
	if (map == &m2_state)
		return k < RXQ_MAX + 1 ? &f_state[cpu][k] : NULL;
	if (map == &m2_cfg)
		return (k == 0 && !cfg_missing) ? &f_cfg : NULL;
	fprintf(stderr, "HOST-TEST-FAIL unknown map\n");
	exit(1);
}

static __u64 bpf_ktime_get_ns(void)
{
	return now_ns;
}

static void *bpf_ringbuf_reserve(void *ringbuf, __u64 size, __u64 flags)
{
	if (ringbuf != &m2_rb || size != sizeof(struct m2_rec) || flags != 0 || reserved_open) {
		fprintf(stderr, "HOST-TEST-FAIL bad reserve\n");
		exit(1);
	}
	if (rb_room == 0 || nrec >= MAXREC)
		return NULL;
	if (rb_room > 0)
		rb_room--;
	reserved_open = 1;
	/* Poison: a field the program forgets to write shows up as 0xEE. */
	memset(&recs[nrec], 0xEE, sizeof(recs[nrec]));
	return &recs[nrec];
}

static void bpf_ringbuf_submit(void *data, __u64 flags)
{
	if (data != &recs[nrec] || flags != 0 || !reserved_open) {
		fprintf(stderr, "HOST-TEST-FAIL bad submit\n");
		exit(1);
	}
	reserved_open = 0;
	nrec++;
}

/* ------------------------------------------------------------- harness */

static int cases, fails;

#define CHECK(cond, ...)                                       \
	do {                                                   \
		if (!(cond)) {                                 \
			printf("HOST-TEST-FAIL %s:%d ", __func__, __LINE__); \
			printf(__VA_ARGS__);                   \
			printf("\n");                          \
			fails++;                               \
		}                                              \
	} while (0)

static void reset(void)
{
	memset(f_stats, 0, sizeof(f_stats));
	memset(f_rxq, 0, sizeof(f_rxq));
	memset(f_ctl, 0, sizeof(f_ctl));
	memset(f_state, 0, sizeof(f_state));
	memset(&f_cfg, 0, sizeof(f_cfg));
	cfg_missing = 0;
	f_cfg.ver = M2_CFG_VERSION;
	f_cfg.sample_every = 1;
	f_cfg.rate = M2_DEF_RATE;
	f_cfg.burst = M2_DEF_BURST;
	nrec = 0;
	reserved_open = 0;
	rb_room = -1;
	now_ns = 1000000000ULL;
	cpu = 0;
}

static int run(void *frame, __u32 len, __u32 q)
{
	struct xdp_md ctx = { frame, (__u8 *)frame + len, q };

	return j_xdp_records(&ctx);
}

/* Per-CPU accounting invariant and slice 1b partition, every CPU. */
static void check_accounting(const char *what)
{
	for (int c = 0; c < NCPU; c++) {
		__u64 *k = f_ctl[c], *s = f_stats[c];
		__u64 sum = k[C_SAMPLED_OUT] + k[C_RATE_LIMITED] + k[C_RB_FULL] + k[C_EMITTED] +
			    k[C_DISCARDED];
		__u64 l3 = s[K_IPV4] + s[K_IPV6] + s[K_ARP] + s[K_OTHER] + s[K_TRUNC];
		__u64 l4 = s[K_TCP] + s[K_UDP] + s[K_ICMP] + s[K_L4_OTHER];

		CHECK(k[C_SEEN] == sum, "%s cpu%d seen=%llu sum=%llu", what, c, k[C_SEEN], sum);
		CHECK(s[K_PKTS] == k[C_SEEN], "%s cpu%d pkts=%llu seen=%llu", what, c, s[K_PKTS], k[C_SEEN]);
		CHECK(s[K_PKTS] == l3, "%s cpu%d l3_diff=%lld", what, c, (long long)(s[K_PKTS] - l3));
		CHECK(s[K_IPV4] + s[K_IPV6] == l4, "%s cpu%d l4_diff=%lld", what, c,
		      (long long)(s[K_IPV4] + s[K_IPV6] - l4));
		CHECK(k[C_DISCARDED] == 0, "%s cpu%d discarded=%llu", what, c, k[C_DISCARDED]);
	}
}

/* ------------------------------------------------------------- frames */

static const __u8 MAC_D[6] = { 0x02, 0x11, 0x22, 0x33, 0x44, 0x55 };
static const __u8 MAC_S[6] = { 0x02, 0xaa, 0xbb, 0xcc, 0xdd, 0xee };

struct fb {
	__u8 b[1600];
	__u32 len;
	/* Byte ranges the record must NOT depend on: [start, end). */
	__u32 nr_start[8], nr_end[8];
	int nr;
};

static void put16(__u8 *p, __u16 v)
{
	p[0] = v >> 8;
	p[1] = v & 0xff;
}

static void noread(struct fb *f, __u32 a, __u32 b)
{
	f->nr_start[f->nr] = a;
	f->nr_end[f->nr] = b;
	f->nr++;
}

/* Ethernet + n VLAN tags (TPID 0x8100 outer, 0x88a8 second, 0x8100 third). */
static __u32 eth(struct fb *f, int ntags, __u16 ethertype)
{
	__u32 o = 12;

	memset(f, 0, sizeof(*f));
	memcpy(f->b, MAC_D, 6);
	memcpy(f->b + 6, MAC_S, 6);
	for (int i = 0; i < ntags; i++) {
		put16(f->b + o, i == 1 ? 0x88a8 : 0x8100);
		put16(f->b + o + 2, (__u16)(0x0064 + i)); /* VID 100 + i, PCP 0 */
		o += 4;
	}
	put16(f->b + o, ethertype);
	return o + 2;
}

static void fill_payload(struct fb *f, __u32 from, __u32 to)
{
	static const char sentinel[] = "PAYLOAD-SENTINEL";

	for (__u32 i = from; i < to; i++)
		f->b[i] = (__u8)sentinel[(i - from) % 16];
	noread(f, from, to);
	f->len = to;
}

/* IPv4 header at o; ihl in words; returns L4 offset. */
static __u32 ip4(struct fb *f, __u32 o, __u8 ihl, __u8 proto, __u16 frag, __u16 totlen)
{
	__u8 *p = f->b + o;

	p[0] = 0x40 | ihl;
	p[1] = 0xb8; /* DSCP/ECN: not recorded */
	put16(p + 2, totlen);
	put16(p + 4, 0x1234); /* IP ID: not recorded */
	put16(p + 6, frag);
	p[8] = 63;
	p[9] = proto;
	put16(p + 10, 0xbeef); /* checksum: not recorded */
	p[12] = 192, p[13] = 168, p[14] = 50, p[15] = 10;
	p[16] = 10, p[17] = 0, p[18] = 0, p[19] = 7;
	noread(f, o + 1, o + 2);
	noread(f, o + 4, o + 6);
	noread(f, o + 10, o + 12);
	if (ihl > 5) {
		memset(p + 20, 0x01, (ihl - 5) * 4); /* NOP options */
		noread(f, o + 20, o + ihl * 4);
	}
	return o + (ihl >= 5 ? ihl * 4 : 20);
}

static __u32 ip6(struct fb *f, __u32 o, __u8 nh, __u16 plen)
{
	__u8 *p = f->b + o;

	p[0] = 0x6a; /* version 6, traffic class high nibble: not recorded */
	p[1] = 0xbc;
	put16(p + 2, 0xdef0); /* flow label: not recorded */
	put16(p + 4, plen);
	p[6] = nh;
	p[7] = 255;
	for (int i = 0; i < 16; i++) {
		p[8 + i] = (__u8)(0x20 + i);
		p[24 + i] = (__u8)(0x40 + i);
	}
	noread(f, o + 1, o + 4); /* byte 0 carries the version nibble */
	return o + 40;
}

static __u32 tcp(struct fb *f, __u32 o, __u16 sp, __u16 dp, __u8 flags)
{
	__u8 *p = f->b + o;

	put16(p, sp);
	put16(p + 2, dp);
	memset(p + 4, 0x5a, 8); /* seq, ack */
	p[12] = 0x80; /* data offset 8 words: 12 bytes of options */
	p[13] = flags;
	put16(p + 14, 0xffff); /* window */
	put16(p + 16, 0xabcd); /* checksum */
	put16(p + 18, 0); /* urgent */
	memset(p + 20, 0x01, 12); /* options */
	noread(f, o + 4, o + 12);
	noread(f, o + 14, o + 32);
	return o + 32;
}

/* ------------------------------------------------------------- record checks */

static unsigned long rng = 0x9e3779b97f4a7c15UL;

static __u8 rnd(void)
{
	rng ^= rng << 13;
	rng ^= rng >> 7;
	rng ^= rng << 17;
	return (__u8)rng;
}

/* Emit one record for f on queue q (fresh state, defaults). */
static struct m2_rec one(struct fb *f, __u32 q)
{
	reset();
	CHECK(run(f->b, f->len, q) == XDP_PASS, "verdict");
	CHECK(nrec == 1, "nrec=%d", nrec);
	check_accounting("one");
	return recs[0];
}

static void no_payload(const char *name, struct fb *f, __u32 q)
{
	struct m2_rec base = one(f, q), again;
	static const char sentinel[] = "PAYLOAD-SENTINEL";
	const __u8 *rb = (const __u8 *)&base;

	cases++;
	for (int t = 0; t < 64; t++) {
		struct fb g = *f;

		for (int r = 0; r < f->nr; r++)
			for (__u32 i = f->nr_start[r]; i < f->nr_end[r]; i++)
				g.b[i] = rnd();
		again = one(&g, q);
		if (memcmp(&base, &again, sizeof(base)) != 0) {
			CHECK(0, "%s: record depends on a not-recorded byte (trial %d)", name, t);
			break;
		}
	}
	for (size_t i = 0; i + 4 <= sizeof(base); i++)
		for (int s = 0; s + 4 <= 16; s++)
			CHECK(memcmp(rb + i, sentinel + s, 4) != 0, "%s: payload bytes at rec+%zu", name, i);
	CHECK(base.rsv0 == 0 && base.rsv1 == 0, "%s: reserved not 0", name);
	CHECK(base.ver == 1, "%s: ver", name);
	CHECK(base.ts_ns == now_ns, "%s: ts", name);
}

static int ip_is(const __u8 *ip, const __u8 *want, int n)
{
	for (int i = 0; i < 16; i++)
		if (ip[i] != (i < n ? want[i] : 0))
			return 0;
	return 1;
}

static void test_layout(void)
{
	static const struct {
		const char *name;
		size_t off, size;
		const char *code;
	} t[] = {
#define F(n, c) { #n, offsetof(struct m2_rec, n), sizeof(((struct m2_rec *)0)->n), c }
		F(ver, "B"), F(flags, "B"), F(rxq, "H"), F(wire_len, "I"), F(ts_ns, "Q"),
		F(dst_mac, "6s"), F(src_mac, "6s"), F(ethertype, "H"), F(vlan_tci, "H"),
		F(src_ip, "16s"), F(dst_ip, "16s"), F(l4_proto, "B"), F(ttl_hlim, "B"),
		F(l3_len, "H"), F(sport, "H"), F(dport, "H"), F(tcp_flags, "B"), F(rsv0, "B"),
		F(rsv1, "H"), F(seq_lo, "I"),
#undef F
	};
	static const size_t want[] = { 0, 1, 2, 4, 8, 16, 22, 28, 30, 32, 48, 64, 65, 66, 68, 70, 72, 73, 74, 76 };
	char fmt[128] = "<";
	size_t end = 0;

	cases++;
	CHECK(sizeof(struct m2_rec) == 80, "sizeof m2_rec %zu", sizeof(struct m2_rec));
	CHECK(sizeof(struct m2_cfg) == 16, "sizeof m2_cfg");
	for (size_t i = 0; i < sizeof(t) / sizeof(t[0]); i++) {
		CHECK(t[i].off == want[i], "%s at %zu want %zu", t[i].name, t[i].off, want[i]);
		CHECK(t[i].off == end, "%s: hole before it (%zu != %zu)", t[i].name, t[i].off, end);
		end = t[i].off + t[i].size;
		strcat(fmt, t[i].code);
	}
	CHECK(end == 80, "fields end at %zu", end);
	printf("REC-FMT %s\n", fmt);
	printf("CTL-NAMES seen sampled_out rate_limited rb_full emitted discarded C_MAX=%d\n", C_MAX);
	printf("STAT-ORDER K_PKTS=%d K_BYTES=%d K_IPV4=%d K_IPV6=%d K_ARP=%d K_OTHER=%d K_TRUNC=%d "
	       "K_VLAN=%d K_TCP=%d K_UDP=%d K_ICMP=%d K_L4_OTHER=%d K_MAX=%d\n",
	       K_PKTS, K_BYTES, K_IPV4, K_IPV6, K_ARP, K_OTHER, K_TRUNC, K_VLAN, K_TCP, K_UDP, K_ICMP,
	       K_L4_OTHER, K_MAX);
	CHECK(C_SEEN == 0 && C_SAMPLED_OUT == 1 && C_RATE_LIMITED == 2 && C_RB_FULL == 3 &&
		      C_EMITTED == 4 && C_DISCARDED == 5 && C_MAX == 6,
	      "m2_ctl order");
}

static void test_parse(void)
{
	static const __u8 v4s[4] = { 192, 168, 50, 10 }, v4d[4] = { 10, 0, 0, 7 };
	__u8 v6s[16], v6d[16];
	struct fb f;
	struct m2_rec r;
	__u32 o;

	for (int i = 0; i < 16; i++)
		v6s[i] = (__u8)(0x20 + i), v6d[i] = (__u8)(0x40 + i);

	/* TCP over IPv4, 12 bytes of TCP options, 100 bytes of payload. */
	o = eth(&f, 0, 0x0800);
	o = ip4(&f, o, 5, 6, 0x4000 /* DF */, 20 + 32 + 100);
	o = tcp(&f, o, 51515, 443, 0x18);
	fill_payload(&f, o, o + 100);
	r = one(&f, 3);
	CHECK(r.ethertype == 0x0800 && r.l4_proto == 6 && r.sport == 51515 && r.dport == 443 &&
		      r.tcp_flags == 0x18 && r.ttl_hlim == 63 && r.l3_len == 152 && r.flags == 0 &&
		      r.rxq == 3 && r.wire_len == f.len && r.vlan_tci == 0,
	      "tcp4 fields");
	CHECK(memcmp(r.dst_mac, MAC_D, 6) == 0 && memcmp(r.src_mac, MAC_S, 6) == 0, "tcp4 macs");
	CHECK(ip_is(r.src_ip, v4s, 4) && ip_is(r.dst_ip, v4d, 4), "tcp4 ips");
	CHECK(f_stats[0][K_IPV4] == 1 && f_stats[0][K_TCP] == 1 && f_rxq[0][3] == 1, "tcp4 1b counters");
	no_payload("tcp4", &f, 3);

	/* IPv4 with 8 bytes of options (IHL 7), UDP: ports after the options. */
	o = eth(&f, 0, 0x0800);
	o = ip4(&f, o, 7, 17, 0, 28 + 8 + 40);
	put16(f.b + o, 5353), put16(f.b + o + 2, 53), put16(f.b + o + 4, 48), put16(f.b + o + 6, 0x1111);
	noread(&f, o + 4, o + 8);
	fill_payload(&f, o + 8, o + 48);
	r = one(&f, 0);
	CHECK(r.l4_proto == 17 && r.sport == 5353 && r.dport == 53 && r.tcp_flags == 0 && r.flags == 0,
	      "udp4+options fields sport=%u dport=%u", r.sport, r.dport);
	no_payload("udp4-options", &f, 0);

	/* ICMP echo over IPv4. */
	o = eth(&f, 0, 0x0800);
	o = ip4(&f, o, 5, 1, 0, 20 + 8 + 56);
	f.b[o] = 8, f.b[o + 1] = 0;
	noread(&f, o + 2, o + 8);
	fill_payload(&f, o + 8, o + 64);
	r = one(&f, 1);
	CHECK(r.l4_proto == 1 && r.sport == 0x0800 && r.dport == 0 && f_stats[0][K_ICMP] == 1, "icmp4");
	no_payload("icmp4", &f, 1);

	/* IHL < 5: truncated-L3, no L4, still counted as IPv4 by slice 1b. */
	o = eth(&f, 0, 0x0800);
	ip4(&f, o, 4, 6, 0, 40);
	f.b[o] = 0x44;
	fill_payload(&f, o + 20, o + 60);
	r = one(&f, 0);
	CHECK((r.flags & F_TRUNC_L3) && r.sport == 0 && r.dport == 0 && f_stats[0][K_IPV4] == 1, "ihl<5");
	no_payload("ihl<5", &f, 0);

	/* First fragment (MF): L4 parsed, frag flag set. */
	o = eth(&f, 0, 0x0800);
	o = ip4(&f, o, 5, 17, 0x2000, 1500);
	put16(f.b + o, 1000), put16(f.b + o + 2, 2000);
	noread(&f, o + 4, o + 8);
	fill_payload(&f, o + 8, o + 200);
	r = one(&f, 0);
	CHECK((r.flags & F_FRAG) && r.sport == 1000 && r.dport == 2000, "first fragment");
	no_payload("frag-first", &f, 0);

	/* Non-first fragment: bytes where ports would be are payload; ports stay 0. */
	o = eth(&f, 0, 0x0800);
	o = ip4(&f, o, 5, 17, 0x00b9, 600);
	fill_payload(&f, o, o + 200);
	r = one(&f, 0);
	CHECK((r.flags & F_FRAG) && r.sport == 0 && r.dport == 0, "non-first fragment");
	no_payload("frag-later", &f, 0);

	/* IPv6 TCP. */
	o = eth(&f, 0, 0x86dd);
	o = ip6(&f, o, 6, 32 + 30);
	o = tcp(&f, o, 40000, 22, 0x02);
	fill_payload(&f, o, o + 30);
	r = one(&f, 11);
	CHECK(r.ethertype == 0x86dd && r.l4_proto == 6 && r.sport == 40000 && r.dport == 22 &&
		      r.tcp_flags == 0x02 && r.ttl_hlim == 255 && r.l3_len == 40 + 62 && r.rxq == 11,
	      "tcp6 fields");
	CHECK(ip_is(r.src_ip, v6s, 16) && ip_is(r.dst_ip, v6d, 16), "tcp6 ips");
	no_payload("tcp6", &f, 11);

	/* IPv6 hop-by-hop ext header: not walked, no L4 even though a TCP header follows. */
	o = eth(&f, 0, 0x86dd);
	o = ip6(&f, o, 0, 8 + 32);
	f.b[o] = 6, f.b[o + 1] = 0;
	noread(&f, o, o + 8);
	o = tcp(&f, o + 8, 1234, 80, 0x10);
	fill_payload(&f, o - 32, o + 20); /* the whole TCP header counts as unread here */
	r = one(&f, 0);
	CHECK((r.flags & F_IP6_EXT) && r.l4_proto == 0 && r.sport == 0 && r.dport == 0 &&
		      f_stats[0][K_L4_OTHER] == 1,
	      "ip6 ext");
	no_payload("ip6-ext", &f, 0);

	/* ICMPv6 neighbor solicitation. */
	o = eth(&f, 0, 0x86dd);
	o = ip6(&f, o, 58, 24);
	f.b[o] = 135, f.b[o + 1] = 0;
	noread(&f, o + 2, o + 4);
	fill_payload(&f, o + 4, o + 24);
	r = one(&f, 0);
	CHECK(r.l4_proto == 58 && r.sport == (135 << 8) && f_stats[0][K_ICMP] == 1, "icmp6");
	no_payload("icmp6", &f, 0);

	/* ARP: L2 only; the ARP body (sender/target addresses) is not recorded. */
	o = eth(&f, 0, 0x0806);
	fill_payload(&f, o, o + 28);
	r = one(&f, 0);
	CHECK(r.ethertype == 0x0806 && r.l4_proto == 0 && f_stats[0][K_ARP] == 1 &&
		      ip_is(r.src_ip, v4s, 0),
	      "arp");
	no_payload("arp", &f, 0);

	/* One VLAN tag + IPv4 UDP. */
	o = eth(&f, 1, 0x0800);
	o = ip4(&f, o, 5, 17, 0, 28);
	put16(f.b + o, 67), put16(f.b + o + 2, 68);
	noread(&f, o + 4, o + 8);
	fill_payload(&f, o + 8, o + 8);
	f.len = o + 8;
	r = one(&f, 0);
	CHECK((r.flags & F_VLAN) && !(r.flags & F_QINQ) && r.vlan_tci == 100 && r.ethertype == 0x0800 &&
		      r.sport == 67 && f_stats[0][K_VLAN] == 1,
	      "vlan1");
	no_payload("vlan1", &f, 0);

	/* QinQ. */
	o = eth(&f, 2, 0x86dd);
	o = ip6(&f, o, 17, 8);
	put16(f.b + o, 546), put16(f.b + o + 2, 547);
	fill_payload(&f, o + 4, o + 8);
	r = one(&f, 0);
	CHECK((r.flags & (F_VLAN | F_QINQ)) == (F_VLAN | F_QINQ) && r.vlan_tci == 100 &&
		      r.ethertype == 0x86dd && r.dport == 547 && f_stats[0][K_VLAN] == 1,
	      "qinq");
	no_payload("qinq", &f, 0);

	/* Three tags: the third is not parsed; counted as other. */
	o = eth(&f, 3, 0x0800);
	fill_payload(&f, o, o + 40);
	r = one(&f, 0);
	CHECK((r.flags & F_VLAN_DEEP) && r.ethertype == 0x8100 && r.l4_proto == 0 &&
		      f_stats[0][K_OTHER] == 1,
	      "vlan deep");
	no_payload("vlan-deep", &f, 0);

	/* Short Ethernet (10 bytes): truncated, still one record, slice 1b K_TRUNC. */
	memset(&f, 0, sizeof(f));
	memcpy(f.b, MAC_D, 6);
	f.len = 10;
	r = one(&f, 0);
	CHECK((r.flags & F_TRUNC_L3) && r.wire_len == 10 && f_stats[0][K_TRUNC] == 1 &&
		      r.dst_mac[0] == 0,
	      "short eth");

	/* VLAN tag cut short. */
	o = eth(&f, 1, 0x0800);
	f.len = 16;
	r = one(&f, 0);
	CHECK((r.flags & F_TRUNC_L3) && r.ethertype == 0x8100 && f_stats[0][K_TRUNC] == 1, "short vlan");

	/* TCP header cut at 10 bytes: truncated-L4, no ports. */
	o = eth(&f, 0, 0x0800);
	o = ip4(&f, o, 5, 6, 0, 30);
	put16(f.b + o, 1), put16(f.b + o + 2, 2);
	f.len = o + 10;
	r = one(&f, 0);
	CHECK((r.flags & F_TRUNC_L4) && r.sport == 0 && r.dport == 0 && f_stats[0][K_TCP] == 1, "cut tcp");

	/* Short IPv4 fixed header: K_TRUNC, not K_IPV4. */
	o = eth(&f, 0, 0x0800);
	f.len = o + 19;
	r = one(&f, 0);
	CHECK((r.flags & F_TRUNC_L3) && f_stats[0][K_TRUNC] == 1 && f_stats[0][K_IPV4] == 0, "short ip4");
	cases += 6;
}

/* Build a UDP v4 frame once; reused by the rate tests. */
static struct fb udp_frame;

static void make_udp(void)
{
	__u32 o = eth(&udp_frame, 0, 0x0800);

	o = ip4(&udp_frame, o, 5, 17, 0, 28 + 16);
	put16(udp_frame.b + o, 9), put16(udp_frame.b + o + 2, 9);
	fill_payload(&udp_frame, o + 8, o + 24);
}

static void burst(int n, __u32 q)
{
	for (int i = 0; i < n; i++)
		CHECK(run(udp_frame.b, udp_frame.len, q) == XDP_PASS, "verdict");
}

static void test_sampling(void)
{
	reset();
	f_cfg.sample_every = 10;
	f_cfg.rate = 1000000;
	f_cfg.burst = 100000;
	burst(1000, 2);
	CHECK(nrec == 100 && f_ctl[0][C_SAMPLED_OUT] == 900 && f_ctl[0][C_EMITTED] == 100,
	      "1-in-10: nrec=%d so=%llu", nrec, f_ctl[0][C_SAMPLED_OUT]);
	/* Deterministic: frames 0, 10, 20, ... ; per-queue seq 0..99 with no gap. */
	for (int i = 0; i < nrec; i++)
		CHECK(recs[i].seq_lo == (__u32)i, "1-in-10 seq %d=%u", i, recs[i].seq_lo);
	check_accounting("sample10");
	cases++;

	/* Per CPU: two CPUs sample independently from their own counters. */
	reset();
	f_cfg.sample_every = 3;
	f_cfg.rate = 1000000;
	f_cfg.burst = 100000;
	for (int i = 0; i < 30; i++) {
		cpu = i & 1;
		burst(1, 0);
	}
	CHECK(f_ctl[0][C_EMITTED] == 5 && f_ctl[1][C_EMITTED] == 5, "per-cpu sampling %llu %llu",
	      f_ctl[0][C_EMITTED], f_ctl[1][C_EMITTED]);
	check_accounting("sample-percpu");
	cases++;

	/* N = 0: records off; counters still count every frame. */
	reset();
	f_cfg.sample_every = 0;
	burst(500, 0);
	CHECK(nrec == 0 && f_ctl[0][C_SAMPLED_OUT] == 500 && f_stats[0][K_PKTS] == 500, "N=0");
	check_accounting("N=0");
	cases++;

	/* Wrong cfg version and a missing cfg slot: compiled defaults (N=1, 2000/s, burst 4000). */
	reset();
	f_cfg.ver = 99;
	f_cfg.sample_every = 0;
	burst(10, 0);
	CHECK(nrec == 10, "cfg ver mismatch uses defaults: nrec=%d", nrec);
	reset();
	cfg_missing = 1;
	burst(5000, 0);
	CHECK(nrec == M2_DEF_BURST && f_ctl[0][C_RATE_LIMITED] == 5000 - M2_DEF_BURST,
	      "cfg missing: defaults nrec=%d", nrec);
	check_accounting("cfg-missing");
	cases += 2;
}

static void test_rate(void)
{
	int before, flagged;

	/* Burst 4000 at one instant: exactly 4000 admitted, the rest limited. */
	reset();
	burst(10000, 0);
	CHECK(nrec == 4000 && f_ctl[0][C_RATE_LIMITED] == 6000, "burst nrec=%d rl=%llu", nrec,
	      f_ctl[0][C_RATE_LIMITED]);
	check_accounting("burst");
	cases++;

	/* 0.5 s later at 2000/s: 1000 more; the first carries F_RL_RECOVERED. */
	before = nrec;
	now_ns += 500000000ULL;
	burst(3000, 0);
	CHECK(nrec - before == 1000, "refill 0.5s: %d", nrec - before);
	CHECK(recs[before].flags & F_RL_RECOVERED, "recovered flag on first after limit");
	flagged = 0;
	for (int i = 0; i < nrec; i++)
		flagged += !!(recs[i].flags & F_RL_RECOVERED);
	CHECK(flagged == 1, "recovered flag count %d", flagged);
	check_accounting("refill");
	cases++;

	/* Steady 1 frame per 400 us = 2500/s offered against 2000/s, 10 s. After
	 * the burst drains, emitted converges to 2000/s (credit can never exceed cap). */
	reset();
	for (int i = 0; i < 25000; i++) {
		now_ns += 400000ULL;
		burst(1, 0);
	}
	CHECK(nrec >= 20000 + 4000 - 2 && nrec <= 20000 + 4000 + 2, "steady 2500/s for 10 s: nrec=%d", nrec);
	check_accounting("steady");
	cases++;

	/* Under the rate: nothing limited. */
	reset();
	for (int i = 0; i < 5000; i++) {
		now_ns += 1000000ULL; /* 1000/s */
		burst(1, 0);
	}
	CHECK(nrec == 5000 && f_ctl[0][C_RATE_LIMITED] == 0, "under rate: nrec=%d", nrec);
	cases++;

	/* rate = 0: every sampled frame is rate-limited. */
	reset();
	f_cfg.rate = 0;
	burst(100, 0);
	CHECK(nrec == 0 && f_ctl[0][C_RATE_LIMITED] == 100, "rate 0");
	check_accounting("rate0");
	cases++;

	/* burst 0 -> 1; burst above max -> clamped to M2_BURST_MAX. */
	reset();
	f_cfg.burst = 0;
	burst(10, 0);
	CHECK(nrec == 1, "burst 0 -> 1: nrec=%d", nrec);
	reset();
	f_cfg.rate = 0xffffffffu;
	f_cfg.burst = 0xffffffffu;
	burst(M2_BURST_MAX + 7, 0);
	CHECK(f_ctl[0][C_EMITTED] + f_ctl[0][C_RB_FULL] == M2_BURST_MAX &&
		      f_ctl[0][C_RATE_LIMITED] == 7,
	      "burst clamp: emitted+full=%llu rl=%llu", f_ctl[0][C_EMITTED] + f_ctl[0][C_RB_FULL],
	      f_ctl[0][C_RATE_LIMITED]);
	check_accounting("clamp");
	cases += 2;

	/* Clock going backwards (another CPU's earlier ts never reaches here, but be
	 * safe): no refill, no wrap to a huge credit. */
	reset();
	now_ns = 5000000000ULL;
	burst(4000, 0);
	now_ns -= 1000000000ULL;
	before = nrec;
	burst(10, 0);
	CHECK(nrec == before, "clock backwards gives no credit");
	cases++;
}

static void test_rb_full(void)
{
	/* Room for 5, then 3 failures, then room again: the queue sequence shows
	 * the gap of 3 and C_RB_FULL counts 3. */
	reset();
	rb_room = 5;
	burst(8, 4);
	CHECK(nrec == 5 && f_ctl[0][C_RB_FULL] == 3 && f_ctl[0][C_EMITTED] == 5, "rb full");
	rb_room = -1;
	burst(2, 4);
	CHECK(nrec == 7 && recs[5].seq_lo == 8 && recs[6].seq_lo == 9 && recs[4].seq_lo == 4,
	      "seq gap after full: %u %u", recs[5].seq_lo, recs[6].seq_lo);
	check_accounting("rb-full");
	cases++;

	/* Separate queues keep separate sequences. */
	reset();
	burst(3, 0);
	burst(2, 1);
	CHECK(recs[3].seq_lo == 0 && recs[4].seq_lo == 1 && recs[2].seq_lo == 2, "per-queue seq");
	cases++;

	/* Out-of-range queue (>= RXQ_MAX): counted, record seq 0, rxq capped. */
	reset();
	burst(2, 70000);
	CHECK(nrec == 2 && recs[1].seq_lo == 0 && recs[1].rxq == 0xffff && f_stats[0][K_PKTS] == 2,
	      "oob queue");
	check_accounting("oob-queue");
	cases++;
}

int main(void)
{
	test_layout();
	test_parse();
	make_udp();
	test_sampling();
	test_rate();
	test_rb_full();
	if (fails) {
		printf("HOST-TEST-FAIL failures=%d\n", fails);
		return 1;
	}
	printf("HOST-TEST-OK cases=%d\n", cases);
	return 0;
}
