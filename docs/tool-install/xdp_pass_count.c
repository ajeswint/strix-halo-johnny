// SPDX-License-Identifier: GPL-2.0
/*
 * Johnny step 11: temporary native-XDP pass counter for eno1np0.
 * Loaded only by docs/tool-install/step-11-e810-capture.sh, then detached.
 * Not installed under /etc and not attached at boot.
 *
 * Build (this object is what AJ copies; do not rebuild on Johnny):
 *   clang -O2 -g -Wall -Wextra -target bpf -mcpu=v3 \
 *     -c docs/tool-install/xdp_pass_count.c \
 *     -o docs/tool-install/xdp-pass-count.o
 * Built with Ubuntu clang 18.1.3. bpftool on Johnny is 7.7.0 (step 7).
 */

typedef unsigned int __u32;
typedef unsigned long long __u64;

#define SEC(name) __attribute__((section(name), used))
#define __uint(name, val) int (*name)[val]
#define __type(name, val) typeof(val) *name

/* BPF_MAP_TYPE_ARRAY == 2. One slot, zeroed by the kernel. */
struct {
	__uint(type, 2);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u64);
} pkt_cnt SEC(".maps");

static void *(*bpf_map_lookup_elem)(void *map, const void *key) = (void *)1;

struct xdp_md {
	__u32 data;
	__u32 data_end;
	__u32 data_meta;
	__u32 ingress_ifindex;
	__u32 rx_queue_index;
	__u32 egress_ifindex;
};

SEC("xdp")
int j_xdp_count(struct xdp_md *ctx)
{
	__u32 key = 0;
	__u64 *v;

	(void)ctx;
	v = bpf_map_lookup_elem(&pkt_cnt, &key);
	if (v)
		__sync_fetch_and_add(v, 1);
	return 2; /* XDP_PASS */
}

char _license[] SEC("license") = "GPL";
