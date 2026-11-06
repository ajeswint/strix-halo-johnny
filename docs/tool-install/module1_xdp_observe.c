// SPDX-License-Identifier: GPL-2.0
/*
 * Johnny Module 1 slice 1b: passive, observe-only native-XDP counters for
 * eno1np0 (SPAN port). Runbook: docs/tool-install/module1-slice1b-attach.md
 *
 * What it does: counts frames, bytes, an ethertype / L4 class split and the
 * Rx queue index, in per-CPU array maps. It reads the Ethernet header, up to
 * two VLAN tags, and one byte of the fixed IPv4 / IPv6 header (the L4 protocol
 * number). It keeps no payload and no header bytes, and does not modify the
 * frame.
 *
 * What it does NOT do (slice 1b): no XDP_DROP / XDP_TX / XDP_REDIRECT /
 * XDP_ABORTED, no bpf_redirect_map, no bpf_xdp_adjust_*, no ring buffer, no
 * AF_XDP, no tail calls, no helper except bpf_map_lookup_elem. The only
 * `return` in the XDP entry point is XDP_PASS: the work is in a void helper,
 * so no code path can return anything else. The rock-box self-test greps for
 * this and checks the object's disassembly (every constant written to r0 is 2).
 *
 * Build (off-box, rock-box; Johnny has no compiler). Exact commands and the
 * compiler provenance are in the runbook, section "Build". Output:
 *   docs/tool-install/module1-xdp-observe.o  (sha256 pinned in the runbook)
 *
 * IPv6 extension headers are not walked: a packet whose IPv6 next-header is an
 * extension header counts as L4_OTHER. Non-first IPv4 fragments are classified
 * by the IPv4 protocol field like any other.
 *
 * Map slot order below MUST match the name table in
 * module1-slice1b-attach.sh (the self-test compares them).
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
#define BPF_MAP_TYPE_PERCPU_ARRAY 6

/* Stats slots. Keep in this order. */
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

#define RXQ_MAX 64

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

static void *(*bpf_map_lookup_elem)(void *map, const void *key) = (void *)1;

struct xdp_md {
	__u32 data;
	__u32 data_end;
	__u32 data_meta;
	__u32 ingress_ifindex;
	__u32 rx_queue_index;
	__u32 egress_ifindex;
};

struct eth_hdr {
	__u8 dst[6];
	__u8 src[6];
	__u16 proto; /* network byte order */
} __attribute__((packed));

struct vlan_hdr {
	__u16 tci;
	__u16 encap; /* network byte order */
} __attribute__((packed));

/* Fixed part only; only `protocol` is read. */
struct ip4_hdr {
	__u8 ver_ihl;
	__u8 tos;
	__u16 tot_len;
	__u16 id;
	__u16 frag_off;
	__u8 ttl;
	__u8 protocol;
	__u16 check;
	__u32 saddr;
	__u32 daddr;
} __attribute__((packed));

/* Fixed part only; only `nexthdr` is read. */
struct ip6_hdr {
	__u32 vtc_flow;
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

/*
 * Classes are a partition: every frame lands in exactly one of
 * IPV4 / IPV6 / ARP / OTHER / TRUNC, and every IPV4 or IPV6 frame lands in
 * exactly one of TCP / UDP / ICMP / L4_OTHER. VLAN counts frames that still
 * carry a tag when XDP sees them (not part of the partition).
 */
static __always_inline void observe(struct xdp_md *ctx)
{
	void *data = (void *)(long)ctx->data;
	void *data_end = (void *)(long)ctx->data_end;
	struct eth_hdr *eth = data;
	__u32 qkey = ctx->rx_queue_index;
	__u64 *qv;
	__u16 proto;
	void *p;

	bump(K_PKTS, 1);
	bump(K_BYTES, (__u64)(data_end - data));

	/* Out-of-range queue index: lookup returns NULL and nothing is counted. */
	qv = bpf_map_lookup_elem(&m1_rxq, &qkey);
	if (qv)
		*qv += 1;

	if ((void *)(eth + 1) > data_end) {
		bump(K_TRUNC, 1);
		return;
	}
	proto = eth->proto;
	p = eth + 1;

#pragma unroll
	for (int i = 0; i < 2; i++) {
		if (proto == BE16(0x8100) || proto == BE16(0x88a8)) {
			struct vlan_hdr *vh = p;

			if ((void *)(vh + 1) > data_end) {
				bump(K_TRUNC, 1);
				return;
			}
			if (i == 0)
				bump(K_VLAN, 1);
			proto = vh->encap;
			p = vh + 1;
		}
	}

	if (proto == BE16(0x0800)) {
		struct ip4_hdr *ip = p;

		if ((void *)(ip + 1) > data_end) {
			bump(K_TRUNC, 1);
			return;
		}
		bump(K_IPV4, 1);
		bump_l4(ip->protocol);
	} else if (proto == BE16(0x86dd)) {
		struct ip6_hdr *ip6 = p;

		if ((void *)(ip6 + 1) > data_end) {
			bump(K_TRUNC, 1);
			return;
		}
		bump(K_IPV6, 1);
		bump_l4(ip6->nexthdr);
	} else if (proto == BE16(0x0806)) {
		bump(K_ARP, 1);
	} else {
		bump(K_OTHER, 1);
	}
}

SEC("xdp")
int j_xdp_observe(struct xdp_md *ctx)
{
	observe(ctx);
	return XDP_PASS;
}

char _license[] SEC("license") = "GPL";
