// SPDX-License-Identifier: GPL-2.0
/*
 * Johnny Stage 2 (Paste S2-1): minimal BPF LSM cgroup-scoping feasibility test.
 * Runbook: docs/stage2/cgroup-scoping-test-runbook.md (Section 4)
 *
 * Proves O28 C on Rock Box (kernel 7.3.0-10-generic): deny a throwaway sentinel
 * binary inside one dedicated cgroup subtree (/sys/fs/cgroup/johnny-stage2-test)
 * while observing (never denying) outside it.
 *
 * Per AJ's 2026-11-22 3:18 PM CT decision, this object contains BOTH mechanisms
 * so Paste S2-1 probes the kernel verifier against both before selecting one:
 *   - j_s2_cgtest_m1  (Mechanism 1): SEC("lsm/bprm_check_security") +
 *       bpf_current_task_under_cgroup(&j_s2_cgtest_cg, 0). Returns 0 (allow)
 *       outside the test cgroup and -EPERM (-1) inside its subtree.
 *   - j_s2_cgtest_m2  (Mechanism 2): SEC("lsm_cgroup/bprm_check_security")
 *       attached to the test cgroup directory fd. Inverted return convention:
 *       returns 1 (allow) on fail-open / non-sentinel, 0 (deny -> -EPERM) for
 *       the sentinel inside the attached cgroup subtree.
 *   - j_s2_cgtest_obs (Mechanism 2 observe companion): global
 *       SEC("lsm/bprm_check_security") with no cgroup helpers; always returns 0
 *       (never denies), used only when M1 is rejected and M2 is selected so
 *       Case A still proves global observe-only outside the test cgroup.
 *
 * Safety invariants:
 *   1. Fail-open whenever config is uninitialized (enabled == 0, sentinel_ino
 *      == 0, or target_cgid == 0) or on any map/helper error.
 *   2. Double-gated deny: only the throwaway sentinel binary matching both
 *      i_ino and kernel-encoded s_dev = (major << 20) | minor can ever be
 *      denied. Every other executable returns allow immediately.
 *   3. All map and program names are prefixed j_s2_cgtest_ and <= 15 chars
 *      (BPF_OBJ_NAME_LEN - 1) so kernel truncation never hides them.
 *
 * Build (unprivileged, on Rock Box): bash stage2/cgtest/build.sh
 * vmlinux.h is generated at build time from /sys/kernel/btf/vmlinux and is not
 * committed to git.
 */

#include "vmlinux.h"

#if __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error "little-endian only (Rock Box is x86_64)"
#endif

#define SEC(name) __attribute__((section(name), used))
#define __uint(name, val) int (*name)[val]
#define __type(name, val) typeof(val) *name
#define __always_inline inline __attribute__((always_inline))

#define EPERM 1

/* BPF helpers declared directly by kernel helper ID (no libbpf-dev required). */
static void *(*bpf_map_lookup_elem)(void *map, const void *key) = (void *)1;
static long (*bpf_current_task_under_cgroup)(void *map, __u32 index) = (void *)37;
static __u64 (*bpf_get_current_cgroup_id)(void) = (void *)80;

/* Runtime config (key 0). All-zero defaults fail open. */
struct j_s2_cgtest_cfg {
	__u64 sentinel_ino;
	__u64 target_cgid;
	__u32 sentinel_sdev; /* kernel MKDEV(major, minor) = (major << 20) | minor */
	__u32 enabled;
};

_Static_assert(sizeof(struct j_s2_cgtest_cfg) == 24, "j_s2_cgtest_cfg size");
_Static_assert(__builtin_offsetof(struct j_s2_cgtest_cfg, sentinel_ino) == 0, "sentinel_ino off");
_Static_assert(__builtin_offsetof(struct j_s2_cgtest_cfg, target_cgid) == 8, "target_cgid off");
_Static_assert(__builtin_offsetof(struct j_s2_cgtest_cfg, sentinel_sdev) == 16, "sentinel_sdev off");
_Static_assert(__builtin_offsetof(struct j_s2_cgtest_cfg, enabled) == 20, "enabled off");

/* Stat slots in j_s2_cgtest_st (keep in sync with stage2/cgtest/loader.py). */
enum {
	ST_OBSERVED_OUTSIDE = 0,
	ST_DENIED_INSIDE = 1,
	ST_DENIED_OUTSIDE = 2, /* defensive; expected unreachable (fmod_ret short-circuits on ret != 0) */
	ST_CG_HELPER_ERR = 3,
	ST_LAST_CGID_OUT = 4,
	ST_LAST_CGID_IN = 5,
	ST_M2_SEEN = 6,
	ST_OBS_SEEN = 7,
	ST_MAX = 8,
};

/* Map names: prefixed j_s2_cgtest_ and <= 15 chars total (PR #50 N12). */
struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, struct j_s2_cgtest_cfg);
} j_s2_cgtest_cfg SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, ST_MAX);
	__type(key, __u32);
	__type(value, __u64);
} j_s2_cgtest_st SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_CGROUP_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u32);
} j_s2_cgtest_cg SEC(".maps");

static __always_inline void st_inc(__u32 slot)
{
	__u32 key = slot;
	__u64 *v = bpf_map_lookup_elem(&j_s2_cgtest_st, &key);

	if (v)
		__sync_fetch_and_add(v, 1);
}

static __always_inline void st_set(__u32 slot, __u64 val)
{
	__u32 key = slot;
	__u64 *v = bpf_map_lookup_elem(&j_s2_cgtest_st, &key);

	if (v)
		*v = val;
}

static __always_inline int is_sentinel(struct linux_binprm *bprm,
				       const struct j_s2_cgtest_cfg *cfg)
{
	struct file *f;
	struct inode *ino;
	struct super_block *sb;

	if (!bprm)
		return 0;
	f = bprm->file;
	if (!f)
		return 0;
	ino = f->f_inode;
	if (!ino)
		return 0;
	sb = ino->i_sb;
	if (!sb)
		return 0;
	if (ino->i_ino != cfg->sentinel_ino)
		return 0;
	if ((__u32)sb->s_dev != cfg->sentinel_sdev)
		return 0;
	return 1;
}

/*
 * Mechanism 1: global BPF_LSM_MAC hook + subtree helper
 * bpf_current_task_under_cgroup(&j_s2_cgtest_cg, 0).
 * Return convention: 0 = allow, -EPERM = deny.
 */
SEC("lsm/bprm_check_security")
int j_s2_cgtest_m1(u64 *ctx)
{
	struct linux_binprm *bprm = (struct linux_binprm *)(unsigned long)ctx[0];
	int ret = (int)ctx[1];
	__u32 zero = 0;
	struct j_s2_cgtest_cfg *cfg;
	long under;
	__u64 leaf_cgid;

	cfg = bpf_map_lookup_elem(&j_s2_cgtest_cfg, &zero);
	if (!cfg || cfg->enabled == 0 || cfg->sentinel_ino == 0 || cfg->target_cgid == 0)
		return ret;

	if (!is_sentinel(bprm, cfg))
		return ret;

	under = bpf_current_task_under_cgroup(&j_s2_cgtest_cg, 0);
	leaf_cgid = bpf_get_current_cgroup_id();

	if (under < 0) {
		st_inc(ST_CG_HELPER_ERR);
		return ret; /* fail open on cgroup helper / unpopulated map error */
	}
	if (under == 1) {
		st_inc(ST_DENIED_INSIDE);
		st_set(ST_LAST_CGID_IN, leaf_cgid);
		return ret != 0 ? ret : -EPERM;
	}

	/* Defensive check; expected unreachable (fmod_ret always passes ret=0 and short-circuits on non-zero). */
	if (ret != 0) {
		st_inc(ST_DENIED_OUTSIDE);
		st_set(ST_LAST_CGID_OUT, leaf_cgid);
		return ret;
	}

	st_inc(ST_OBSERVED_OUTSIDE);
	st_set(ST_LAST_CGID_OUT, leaf_cgid);
	return 0;
}

/*
 * Mechanism 2: cgroup-attached BPF_LSM_CGROUP hook.
 * Kernel invokes this program only for tasks inside the attached cgroup subtree.
 * Return convention is INVERTED: 1 = allow, 0 = deny (kernel returns -EPERM).
 */
SEC("lsm_cgroup/bprm_check_security")
int j_s2_cgtest_m2(u64 *ctx)
{
	struct linux_binprm *bprm = (struct linux_binprm *)(unsigned long)ctx[0];
	__u32 zero = 0;
	struct j_s2_cgtest_cfg *cfg;

	cfg = bpf_map_lookup_elem(&j_s2_cgtest_cfg, &zero);
	if (!cfg || cfg->enabled == 0 || cfg->sentinel_ino == 0 || cfg->target_cgid == 0)
		return 1; /* fail open (allow) */

	if (!is_sentinel(bprm, cfg))
		return 1; /* allow all non-sentinel binaries */

	st_inc(ST_M2_SEEN);
	st_inc(ST_DENIED_INSIDE);
	return 0; /* deny sentinel inside attached cgroup subtree */
}

/*
 * Mechanism 2 companion: global observe-only BPF_LSM_MAC hook with no cgroup
 * helpers. Always returns 0 (or prior ret). Loaded only when M1 is rejected and
 * M2 is selected so Case A still verifies global observation outside the cgroup.
 */
SEC("lsm/bprm_check_security")
int j_s2_cgtest_obs(u64 *ctx)
{
	struct linux_binprm *bprm = (struct linux_binprm *)(unsigned long)ctx[0];
	int ret = (int)ctx[1];
	__u32 zero = 0;
	struct j_s2_cgtest_cfg *cfg;

	cfg = bpf_map_lookup_elem(&j_s2_cgtest_cfg, &zero);
	if (!cfg || cfg->enabled == 0 || cfg->sentinel_ino == 0 || cfg->target_cgid == 0)
		return ret;

	if (!is_sentinel(bprm, cfg))
		return ret;

	st_inc(ST_OBS_SEEN);
	/* Defensive check; expected unreachable (fmod_ret always passes ret=0 and short-circuits on non-zero). */
	if (ret != 0) {
		__u32 m2_key = ST_M2_SEEN;
		__u64 *m2_cnt = bpf_map_lookup_elem(&j_s2_cgtest_st, &m2_key);

		/* Only attribute prior ret != 0 to outside denial when M2 has not fired. */
		if (!m2_cnt || *m2_cnt == 0)
			st_inc(ST_DENIED_OUTSIDE);
		return ret;
	}
	st_inc(ST_OBSERVED_OUTSIDE);
	return 0;
}

char _license[] SEC("license") = "GPL";
