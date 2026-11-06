#!/bin/bash
# shellcheck disable=SC2030,SC2031  # PATH is set inside subshells on purpose (command shims)
# Local checks for the Module 1 slice 1 probe. Does not touch a NIC, a BPF
# program, a sysctl, or Johnny. Fixtures are text; command shims are temp files.
# Fixture text is illustrative of each tool's output format. It is NOT a live
# capture from Johnny unless a comment says so.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
PROBE=$ROOT/docs/tool-install/module1-slice1-probe.sh
DOC=$ROOT/docs/tool-install/module1-slice1-span-xdp.md
# shellcheck source=docs/tool-install/module1-slice1-probe.sh
source "$PROBE"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "SELF-TEST-FAIL $*" >&2
  exit 1
}

expect_eq() { # name got want
  [ "$2" = "$3" ] || fail "$1: got [$2] want [$3]"
}

# ---------------------------------------------------------------- allowlist

allowed() { ro_allowed "$@" || fail "should be allowed: $*"; }
denied() {
  if ro_allowed "$@"; then fail "should be denied: $*"; fi
}

allowed ip -d link show eno1np0
allowed ip -br addr show eno1np0
allowed ethtool -i eno1np0
allowed ethtool -k eno1np0
allowed ethtool -g eno1np0
allowed ethtool -l eno1np0
allowed ethtool -x eno1np0
allowed ethtool -n eno1np0
allowed ethtool -S eno1np0
allowed ethtool --show-priv-flags eno1np0
allowed ss -f xdp -a
allowed systemctl is-enabled suricata
allowed systemctl is-active johnny-capture-irq.service
allowed systemctl show --property=DefaultLimitMEMLOCK
allowed journalctl -k -b --no-pager
allowed journalctl -k --no-pager
allowed sysctl -n kernel.unprivileged_bpf_disabled
allowed findmnt -n /sys/fs/bpf
allowed findmnt -n -o FSTYPE,OPTIONS /sys/fs/bpf
allowed dpkg-query -W "-f=${DPKG_FMT}" libbpf1
allowed apt-cache policy libxdp1
allowed bpftool version
allowed bpftool feature probe kernel
allowed bpftool -j feature probe kernel
allowed bpftool -j net show
allowed bpftool -j prog show

# Writes, other verbs, option injection, extra args.
denied ip link set eno1np0 down
denied ip link set eno1np0 xdpdrv off
denied ip -d link show
denied ip -d link show eno1np0 extra
denied ip -d link show -eno1
denied ip addr add 10.0.0.1/24 dev eno1np0
denied ip -br addr show ../x
denied ethtool -K eno1np0 gro off
denied ethtool -L eno1np0 combined 4
denied ethtool -G eno1np0 rx 4096
denied ethtool -X eno1np0 equal 4
denied ethtool -N eno1np0 flow-type tcp4 action -1
denied ethtool -s eno1np0 speed 10000
denied ethtool -C eno1np0 adaptive-rx off
denied ethtool --set-priv-flags eno1np0 legacy-rx on
denied ethtool -i
denied ethtool -i -eno1
denied ethtool -i eno1np0 extra
denied ss -f xdp
denied ss -K
denied systemctl start suricata
denied systemctl stop suricata
denied systemctl enable suricata
denied systemctl disable --now suricata
denied systemctl is-active -x
denied systemctl is-active suricata extra
denied systemctl show --property=Environment
denied journalctl -k -b --no-pager --rotate
denied journalctl --vacuum-size=1M
denied sysctl -w net.core.busy_poll=50
denied sysctl -n net.core.busy_poll=50
denied sysctl net.core.busy_poll=50
denied sysctl -n net
denied findmnt -n /
denied dpkg-query -W libbpf1
denied dpkg-query -W "-f=\${Package}\n" libbpf1
denied dpkg-query -L libbpf1
denied apt-cache policy -a
denied apt-cache install libbpf1
denied apt-get install libbpf1
denied bpftool net attach xdpdrv id 1 dev eno1np0
denied bpftool net detach xdpdrv dev eno1np0
denied bpftool prog load a.o /sys/fs/bpf/x
denied bpftool prog show
denied bpftool -j prog show id 1
denied bpftool map update id 1 key 0 value 1
denied bpftool feature probe kernel full
denied bpftool -j feature probe kernel full
denied bpftool feature probe
denied sh -c true
denied tee /sys/class/net/eno1np0/mtu
denied rm -rf /
denied sudo true
denied tc qdisc add dev eno1np0 clsact
denied nft list ruleset
denied ufw status
denied netplan apply
denied modprobe ice

for verb in -K -L -G -X -N -s -C -E -f -t -p -r -W -A -a -m -T -P -u -U -F --change --set-ring --set-channels --features --set-priv-flags; do
  denied ethtool "$verb" eno1np0
done
for verb in start stop restart enable disable mask reload daemon-reload kill; do
  denied systemctl "$verb" suricata
done

# ro() must refuse before running anything. A shim records any call.
SHIM=$TMP/shim
mkdir -p "$SHIM"
for c in ip ethtool bpftool sysctl systemctl tee; do
  cat >"$SHIM/$c" <<EOF
#!/bin/sh
echo "\$0 \$*" >> "$TMP/shim-calls"
echo shim-output
EOF
  chmod +x "$SHIM/$c"
done
: >"$TMP/shim-calls"
rc=0
(
  PATH=$SHIM:$PATH
  ro ip link set eno1np0 down
) >"$TMP/ro.out" 2>"$TMP/ro.err" || rc=$?
expect_eq "ro refusal exit code" "$rc" 97
grep -q 'STOP-not-readonly ip link set eno1np0 down' "$TMP/ro.err" || fail "ro refusal message"
[ ! -s "$TMP/shim-calls" ] || fail "ro ran a refused command: $(cat "$TMP/shim-calls")"
rc=0
(
  PATH=$SHIM:$PATH
  ro ethtool -K eno1np0 gro off
) >"$TMP/ro.out" 2>"$TMP/ro.err" || rc=$?
expect_eq "ro refusal exit code (ethtool -K)" "$rc" 97
[ ! -s "$TMP/shim-calls" ] || fail "ro ran ethtool -K"
rc=0
(
  PATH=$SHIM:$PATH
  ro ethtool -i eno1np0
) >"$TMP/ro.out" 2>"$TMP/ro.err" || rc=$?
expect_eq "ro allowed exit code" "$rc" 0
# N1: a refusal that fires through save() must show STOP-not-readonly on stderr,
# not only in the saved .err file.
mkdir -p "$TMP/saveout"
rc=0
(
  PATH=$SHIM:$PATH
  OUT=$TMP/saveout
  save refused.txt ip link set eno1np0 down
) >"$TMP/save.out" 2>"$TMP/save.err" || rc=$?
expect_eq "save refusal exit code" "$rc" 97
grep -q 'STOP-not-readonly ip link set eno1np0 down' "$TMP/save.err" || fail "N1: save() hid STOP-not-readonly: $(cat "$TMP/save.err")"
grep -q 'ethtool -i eno1np0' "$TMP/shim-calls" || fail "ro did not run an allowed command"
grep -q shim-output "$TMP/ro.out" || fail "ro did not pass output through"

# ---------------------------------------------------------------- parsers

expect_eq "cpulist 1-4" "$(cpulist_expand 1-4 | tr '\n' ' ')" "1 2 3 4 "
expect_eq "cpulist 0-2,7" "$(cpulist_expand 0-2,7 | tr '\n' ' ')" "0 1 2 7 "
expect_eq "cpulist leading zero" "$(cpulist_expand 08-09 | tr '\n' ' ')" "8 9 "
expect_eq "cpulist single" "$(cpulist_expand 5 | tr '\n' ' ')" "5 "
for bad in '' x '1-' '-1' '3-1' '1;rm' '1,,2' '1 2'; do
  if cpulist_expand "$bad" >/dev/null 2>&1; then fail "cpulist accepted [$bad]"; fi
done
cpu_in_list 3 1,2,3,4 || fail "cpu_in_list hit"
if cpu_in_list 5 1,2,3,4; then fail "cpu_in_list miss"; fi
if cpu_in_list 1 bad; then fail "cpu_in_list bad list"; fi
# B1 regression (reviewer, PR #22 tip b5d71e1). This file runs under
# `set -o pipefail`. The old `cpulist_expand | grep -qx` returned 1 here every
# time: grep -q exits on the first match, the writer gets SIGPIPE, rc 141.
# A long list makes the writer still be printing when grep exits.
cpu_in_list 0 0-30000 || fail "B1: cpu_in_list 0 0-30000 must succeed under pipefail"
cpu_in_list 30000 0-30000 || fail "B1: cpu_in_list 30000 0-30000 (last element) must succeed"
if cpu_in_list 30001 0-30000; then fail "B1: cpu_in_list 30001 0-30000 must fail"; fi
for _ in 1 2 3 4 5 6 7 8 9 10; do
  cpu_in_list 0 0-30000 || fail "B1: cpu_in_list 0 0-30000 flaked on repeat"
done
cpu_in_list 08 7-9 || fail "cpu_in_list leading zero in cpu"
if cpu_in_list 1 '1;rm'; then fail "cpu_in_list accepted a bad list"; fi
if cpu_in_list '' 1,2; then fail "cpu_in_list accepted an empty cpu"; fi
if cpu_in_list 1x 1,2; then fail "cpu_in_list accepted a non-numeric cpu"; fi
# Substring safety: 1 is not in 10-12, 12 is not in 1-2.
if cpu_in_list 1 10-12; then fail "cpu_in_list substring match 1 in 10-12"; fi
if cpu_in_list 12 1-2; then fail "cpu_in_list substring match 12 in 1-2"; fi

# Same live flag values the step 11 self-test uses (0x1183 = UP,PROMISC,NOARP,BROADCAST,MULTICAST).
flag_set 0x1183 "$FLAG_UP" || fail "flag up"
flag_set 0x1183 "$FLAG_PROMISC" || fail "flag promisc"
flag_set 0x1183 "$FLAG_NOARP" || fail "flag noarp"
if flag_set 0x1003 "$FLAG_PROMISC"; then fail "0x1003 has no promisc"; fi
if flag_set 0x1003 "$FLAG_NOARP"; then fail "0x1003 has no noarp"; fi
if flag_set 0x1103 "$FLAG_NOARP"; then fail "0x1103 has no noarp"; fi
if flag_set xyz "$FLAG_UP"; then fail "bad flags accepted"; fi
flag_set 4483 "$FLAG_UP" || fail "decimal flags"

cat >"$TMP/ethtool-k.txt" <<'EOF'
Features for eno1np0:
rx-checksumming: on
tx-checksumming: on
	tx-checksum-ipv4: off [fixed]
generic-receive-offload: on
large-receive-offload: off [fixed]
rx-vlan-offload: on
rx-vlan-filter: on [fixed]
ntuple-filters: off
receive-hashing: on
hw-tc-offload: off
rx-gro-hw: off [fixed]
tx-gso-robust: off [requested on]
EOF
expect_eq "feature on" "$(ethtool_feature_state generic-receive-offload <"$TMP/ethtool-k.txt")" on
expect_eq "feature off-fixed" "$(ethtool_feature_state large-receive-offload <"$TMP/ethtool-k.txt")" off-fixed
expect_eq "feature on-fixed" "$(ethtool_feature_state rx-vlan-filter <"$TMP/ethtool-k.txt")" on-fixed
expect_eq "feature requested" "$(ethtool_feature_state tx-gso-robust <"$TMP/ethtool-k.txt")" off
expect_eq "feature indented" "$(ethtool_feature_state tx-checksum-ipv4 <"$TMP/ethtool-k.txt")" off-fixed
expect_eq "feature absent" "$(ethtool_feature_state no-such-feature <"$TMP/ethtool-k.txt")" absent
expect_eq "feature prefix is not a match" "$(ethtool_feature_state rx-vlan <"$TMP/ethtool-k.txt")" absent

cat >"$TMP/ethtool-l.txt" <<'EOF'
Channel parameters for eno1np0:
Pre-set maximums:
RX:		n/a
TX:		n/a
Other:		1
Combined:	64
Current hardware settings:
RX:		n/a
TX:		n/a
Other:		1
Combined:	12
EOF
expect_eq "channels max" "$(ethtool_sect_get max Combined <"$TMP/ethtool-l.txt")" 64
expect_eq "channels cur" "$(ethtool_sect_get cur Combined <"$TMP/ethtool-l.txt")" 12
expect_eq "channels rx na" "$(ethtool_sect_get cur RX <"$TMP/ethtool-l.txt")" "n/a"
expect_eq "channels absent" "$(ethtool_sect_get cur Nope <"$TMP/ethtool-l.txt")" absent
cat >"$TMP/ethtool-g.txt" <<'EOF'
Ring parameters for eno1np0:
Pre-set maximums:
RX:		8160
RX Mini:	n/a
RX Jumbo:	n/a
TX:		8160
Current hardware settings:
RX:		2048
RX Mini:	n/a
RX Jumbo:	n/a
TX:		2048
EOF
expect_eq "ring rx cur" "$(ethtool_sect_get cur RX <"$TMP/ethtool-g.txt")" 2048
expect_eq "ring tx max" "$(ethtool_sect_get max TX <"$TMP/ethtool-g.txt")" 8160
expect_eq "ring rx mini cur" "$(ethtool_sect_get cur 'RX Mini' <"$TMP/ethtool-g.txt")" "n/a"

cat >"$TMP/ethtool-i.txt" <<'EOF'
driver: ice
version: 7.0.0-42-generic
firmware-version: 4.70 0x80020f7f 1.3755.0
expansion-rom-version:
bus-info: 0000:01:00.0
supports-statistics: yes
EOF
expect_eq "driver" "$(ethtool_i_get driver <"$TMP/ethtool-i.txt")" ice
expect_eq "bus-info keeps colons" "$(ethtool_i_get bus-info <"$TMP/ethtool-i.txt")" 0000:01:00.0
expect_eq "fw keeps spaces" "$(ethtool_i_get firmware-version <"$TMP/ethtool-i.txt")" "4.70 0x80020f7f 1.3755.0"
expect_eq "i absent" "$(ethtool_i_get nope <"$TMP/ethtool-i.txt")" absent

cat >"$TMP/priv.txt" <<'EOF'
Private flags for eno1np0:
link-down-on-close   : off
fw-lldp-agent        : off
legacy-rx            : off
EOF
expect_eq "priv flags" "$(priv_flags_lines <"$TMP/priv.txt" | tr '\n' ';')" "link-down-on-close off;fw-lldp-agent off;legacy-rx off;"

# Negative: output of `ip -d link show lo` on rock-box, copied as text (read of loopback only).
cat >"$TMP/iplink-quiet.txt" <<'EOF'
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00 promiscuity 0 allmulti 0 minmtu 0 maxmtu 0 netns-immutable addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 524280 tso_max_segs 65535 gro_max_size 65536 gso_ipv4_max_size 65536 gro_ipv4_max_size 65536
EOF
# Positive: iproute2's attached-program line as I remember it ([Assumption]; not a live capture).
cat >"$TMP/iplink-xdp.txt" <<'EOF'
3: eno1np0: <BROADCAST,MULTICAST,PROMISC,NOARP,UP,LOWER_UP> mtu 1500 xdp qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether 38:05:25:3a:ac:da brd ff:ff:ff:ff:ff:ff promiscuity 1 allmulti 0 minmtu 68 maxmtu 9702
    prog/xdp id 42 name j_xdp_count tag 0123456789abcdef jited
EOF
cat >"$TMP/iplink-xdp-generic.txt" <<'EOF'
3: eno1np0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 xdpgeneric qdisc mq state UP mode DEFAULT group default qlen 1000
EOF
expect_eq "xdp quiet" "$(xdp_attached_from_iplink <"$TMP/iplink-quiet.txt")" no
expect_eq "xdp attached" "$(xdp_attached_from_iplink <"$TMP/iplink-xdp.txt")" yes
expect_eq "xdp generic attached" "$(xdp_attached_from_iplink <"$TMP/iplink-xdp-generic.txt")" yes
expect_eq "xdp empty" "$(xdp_attached_from_iplink </dev/null)" no

cat >"$TMP/interrupts.txt" <<'EOF'
           CPU0       CPU1       CPU2       CPU3       CPU4
 187:          0          0          0          0          0  IR-PCI-MSIX-0000:01:00.0   0-edge      ice-0000:01:00.0:misc
 189:          0       1234          0          0          0  IR-PCI-MSIX-0000:01:00.0   1-edge      ice-eno1np0-TxRx-0
 190:          0          0       2345          0          0  IR-PCI-MSIX-0000:01:00.0   2-edge      ice-eno1np0-TxRx-1
 200:          0          0          0          0        999  IR-PCI-MSIX-0000:01:00.0  12-edge      ice-eno1np0-TxRx-11
 201:          0          0          0          0          0  IR-PCI-MSIX-0000:01:00.0  13-edge      ice-0000:01:00.0:ctrl-TxRx-0
 204:          0          0          0          0          0  IR-PCI-MSIX-0000:01:00.1   1-edge      ice-eno2np1-TxRx-0
 217:          0          0          0          0          0  IR-PCI-MSIX-0000:01:00.0   0-edge      irdma-0000:01:00.0-AEQCEQ-0
 230:          0          0          0          0          0  IR-PCI-MSIX-0000:01:00.0   1-edge      ice-eno1np0-TxRx-x
NMI:          0          0          0          0          0   Non-maskable interrupts
EOF
expect_eq "queue irqs" "$(queue_irqs_from_interrupts eno1np0 <"$TMP/interrupts.txt" | tr '\n' ';')" "189 ice-eno1np0-TxRx-0;190 ice-eno1np0-TxRx-1;200 ice-eno1np0-TxRx-11;"
expect_eq "queue irqs eno2" "$(queue_irqs_from_interrupts eno2np1 <"$TMP/interrupts.txt" | tr '\n' ';')" "204 ice-eno2np1-TxRx-0;"
expect_eq "queue irqs none" "$(queue_irqs_from_interrupts eno9 <"$TMP/interrupts.txt" | tr '\n' ';')" ""

expect_eq "addr none" "$(printf 'eno1np0          UP             \n' | addr_count_from_brief)" 0
expect_eq "addr one" "$(printf 'eno1np0          UP             192.168.1.5/24 \n' | addr_count_from_brief)" 1
expect_eq "addr two" "$(printf 'eno1np0          UP             192.168.1.5/24 fe80::1/64 \n' | addr_count_from_brief)" 2
expect_eq "addr empty" "$(addr_count_from_brief </dev/null)" 0

cat >"$TMP/kconfig.txt" <<'EOF'
CONFIG_BPF_SYSCALL=y
CONFIG_ICE=m
# CONFIG_XDP_SOCKETS_DIAG is not set
CONFIG_XDP_SOCKETS=y
CONFIG_BPF_JIT_ALWAYS_ON=y
EOF
expect_eq "kconfig y" "$(config_value "$TMP/kconfig.txt" CONFIG_BPF_SYSCALL)" y
expect_eq "kconfig m" "$(config_value "$TMP/kconfig.txt" CONFIG_ICE)" m
expect_eq "kconfig not set" "$(config_value "$TMP/kconfig.txt" CONFIG_XDP_SOCKETS_DIAG)" n
expect_eq "kconfig absent" "$(config_value "$TMP/kconfig.txt" CONFIG_NOPE)" absent
expect_eq "kconfig prefix is not a match" "$(config_value "$TMP/kconfig.txt" CONFIG_BPF)" absent
if config_value "$TMP/kconfig.txt" 'CONFIG_X;rm' >/dev/null 2>&1; then fail "kconfig bad key"; fi

expect_eq "lockdown integrity" "$(printf 'none [integrity] confidentiality\n' | bracketed_word)" integrity
expect_eq "lockdown none" "$(printf '[none] integrity confidentiality\n' | bracketed_word)" none
expect_eq "thp" "$(printf 'always [madvise] never\n' | bracketed_word)" madvise
expect_eq "bracket unknown" "$(printf 'garbage\n' | bracketed_word)" unknown
expect_eq "bracket empty" "$(bracketed_word </dev/null)" unknown

expect_eq "rate" "$(rate_per_sec 100 600 5)" 100
expect_eq "rate zero" "$(rate_per_sec 100 100 5)" 0
expect_eq "rate backwards" "$(rate_per_sec 600 100 5)" 0
if rate_per_sec x 1 5 >/dev/null 2>&1; then fail "rate non-numeric"; fi
if rate_per_sec 1 2 0 >/dev/null 2>&1; then fail "rate zero secs"; fi

# JSON fixtures. [Assumption] The key names follow my memory of bpftool's JSON
# schema; they are not a live capture. The probe prints NOTE-feature-key-absent
# when a key is missing, so a wrong name shows up as a NOTE, not a pass.
cat >"$TMP/feature.json" <<'EOF'
{"system_config":{"unprivileged_bpf_disabled":2},
 "syscall_config":{"have_large_insn_limit":true},
 "program_types":{"have_socket_filter_prog_type":true,"have_xdp_prog_type":true},
 "map_types":{"have_array_map_type":true,"have_xskmap_map_type":true,"have_devmap_map_type":false},
 "helpers":{"xdp_prog_type":["bpf_map_lookup_elem","bpf_redirect_map","bpf_xdp_adjust_head","bpf_ktime_get_ns"],
            "socket_filter_prog_type":["bpf_map_lookup_elem"]},
 "misc":{}}
EOF
expect_eq "feature xdp prog" "$(bpf_feature_bool have_xdp_prog_type <"$TMP/feature.json")" yes
expect_eq "feature xskmap" "$(bpf_feature_bool have_xskmap_map_type <"$TMP/feature.json")" yes
expect_eq "feature devmap false" "$(bpf_feature_bool have_devmap_map_type <"$TMP/feature.json")" no
expect_eq "feature key absent" "$(bpf_feature_bool have_ringbuf_map_type <"$TMP/feature.json")" absent
if bpf_feature_bool have_xdp_prog_type <<<'not json' >/dev/null 2>&1; then fail "bad json accepted"; fi
expect_eq "xdp helper yes" "$(bpf_xdp_helper bpf_redirect_map <"$TMP/feature.json")" yes
expect_eq "xdp helper missing" "$(bpf_xdp_helper bpf_ringbuf_output <"$TMP/feature.json")" no
expect_eq "xdp helper no lists" "$(bpf_xdp_helper bpf_redirect_map <<<'{"helpers":{"socket_filter_prog_type":["bpf_redirect_map"]}}')" absent

# Same shape step 11's parser handled live on bpftool 7.7.0 (mode string "driver").
expect_eq "net modes live shape" "$(xdp_modes_from_net_json eno1np0 <<<'[{"xdp":[{"devname":"eno1np0","ifindex":3,"mode":"driver"}],"tc":[]}]')" driver
expect_eq "net modes other dev" "$(xdp_modes_from_net_json eno1np0 <<<'[{"xdp":[{"devname":"eno3","ifindex":2,"mode":"generic"}],"tc":[]}]')" ""
expect_eq "net modes none" "$(xdp_modes_from_net_json eno1np0 <<<'[{"xdp":[],"tc":[]}]')" ""
expect_eq "prog count" "$(prog_count_by_type xdp <<<'[{"id":1,"type":"cgroup_device"},{"id":2,"type":"xdp"},{"id":3,"type":"xdp"}]')" 2
expect_eq "prog count none" "$(prog_count_by_type xdp <<<'[]')" 0

# ---------------------------------------------------------------- gates (no NIC read)

rc=0
bash "$PROBE" >"$TMP/g.out" 2>"$TMP/g.err" || rc=$?
expect_eq "no-arg exit" "$rc" 2
rc=0
bash "$PROBE" bogus >"$TMP/g.out" 2>"$TMP/g.err" || rc=$?
expect_eq "bad-arg exit" "$rc" 2
if [ "$(id -u)" -ne 0 ] && [ "$(hostname --short)" != johnny ]; then
  rc=0
  bash "$PROBE" user >"$TMP/g.out" 2>"$TMP/g.err" || rc=$?
  expect_eq "user mode off-host exit" "$rc" 1
  grep -q '^STOP-host ' "$TMP/g.out" || fail "user mode off-host should print STOP-host: $(cat "$TMP/g.out")"
  rc=0
  bash "$PROBE" root >"$TMP/g.out" 2>"$TMP/g.err" || rc=$?
  expect_eq "root mode as non-root exit" "$rc" 1
  grep -q '^STOP-not-root$' "$TMP/g.out" || fail "root mode as non-root should print STOP-not-root"
else
  echo "SKIP-gates (running as root or on johnny)"
fi

# ---------------------------------------------------------------- end to end on fixtures
# Runs both modes of the real script against a fake /sys and /proc tree and a
# set of command shims. Nothing here reads a real NIC, real BPF state, or Johnny.

E2E=$TMP/e2e
mkdir -p "$E2E/bin" "$E2E/fix" "$E2E/sys/class/net/eno1np0/statistics" "$E2E/sys/kernel/security" \
  "$E2E/sys/kernel/mm/transparent_hugepage" "$E2E/sys/kernel/btf" "$E2E/proc/irq"

cp "$TMP/ethtool-k.txt" "$E2E/fix/ethtool-k"
cp "$TMP/ethtool-l.txt" "$E2E/fix/ethtool-l"
cp "$TMP/ethtool-g.txt" "$E2E/fix/ethtool-g"
cp "$TMP/ethtool-i.txt" "$E2E/fix/ethtool-i"
cp "$TMP/priv.txt" "$E2E/fix/ethtool-priv"
cp "$TMP/feature.json" "$E2E/fix/bpftool-feature.json"
cp "$TMP/iplink-quiet.txt" "$E2E/fix/iplink"
printf 'eno1np0          UP             \n' >"$E2E/fix/ipaddr"
printf 'RSS hash function:\n    toeplitz: on\n    xor: off\n    crc32: off\n' >"$E2E/fix/ethtool-x"
printf '1 RX rings available\nTotal 0 rules\n' >"$E2E/fix/ethtool-n"
printf '     rx_unicast.nic: 4242\n     rx_dropped: 0\n     rx_xdp_drop: 0\nother: 1\n' >"$E2E/fix/ethtool-S"
printf 'Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port\n' >"$E2E/fix/ss-xdp"
printf '[{"xdp":[],"tc":[],"flow_dissector":[],"netfilter":[]}]\n' >"$E2E/fix/bpftool-net.json"
printf '[{"id":1,"type":"cgroup_device"},{"id":2,"type":"cgroup_skb"}]\n' >"$E2E/fix/bpftool-prog.json"
printf 'bpftool v7.7.0\nusing libbpf v1.7\n' >"$E2E/fix/bpftool-version"
printf '[    1.0] ice 0000:01:00.0: The DDP package was successfully loaded: ICE OS Default Package (mc) version 1.3.43.0\n[    2.0] ice 0000:01:00.0: eno1np0: renamed\n' >"$E2E/fix/klog-boot"
printf 'martian source 1\nmartian source 2\nother\n' >"$E2E/fix/klog-all"
cat >"$E2E/fix/kconfig" <<'EOF'
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_BPF_JIT_ALWAYS_ON=y
CONFIG_XDP_SOCKETS=y
# CONFIG_XDP_SOCKETS_DIAG is not set
CONFIG_DEBUG_INFO_BTF=y
CONFIG_ICE=m
CONFIG_PACKET=y
CONFIG_PAGE_POOL=y
CONFIG_NET_CLS_BPF=m
CONFIG_HUGETLBFS=y
CONFIG_TRANSPARENT_HUGEPAGE=y
EOF

# One generic shim, dispatched on its own name and arguments.
cat >"$E2E/bin/shim" <<'EOF'
#!/bin/bash
F=$E2E_FIX
name=$(basename "$0")
args="$*"
case "$name $args" in
  "sleep "*)
    if [ -n "${E2E_BUMP:-}" ]; then
      d=$E2E_SYSDIR/class/net/eno1np0/statistics
      echo $(($(cat "$d/rx_packets") + 1000)) >"$d/rx_packets"
      echo $(($(cat "$d/rx_bytes") + 125000000)) >"$d/rx_bytes"
    fi
    ;;
  "hostname --short") echo "${E2E_HOST:-johnny}" ;;
  "id -u") echo "${E2E_UID:-1000}" ;;
  "id -un") echo "${E2E_USERNAME:-aj}" ;;
  "ip -d link show "*) cat "$F/iplink" ;;
  "ip -br addr show "*) cat "$F/ipaddr" ;;
  "ethtool -i "*) cat "$F/ethtool-i" ;;
  "ethtool -k "*) cat "$F/ethtool-k" ;;
  "ethtool -l "*) cat "$F/ethtool-l" ;;
  "ethtool -g "*) cat "$F/ethtool-g" ;;
  "ethtool -x "*) cat "$F/ethtool-x" ;;
  "ethtool -n "*) cat "$F/ethtool-n" ;;
  "ethtool -S "*) cat "$F/ethtool-S" ;;
  "ethtool --show-priv-flags "*) cat "$F/ethtool-priv" ;;
  "ss -f xdp -a") cat "$F/ss-xdp" ;;
  "systemctl is-enabled suricata") echo disabled; exit 1 ;;
  "systemctl is-active suricata") echo "${E2E_SURICATA_ACTIVE:-inactive}"; [ "${E2E_SURICATA_ACTIVE:-inactive}" = active ] || exit 3 ;;
  "systemctl is-enabled irqbalance") echo not-found; exit 4 ;;
  "systemctl is-active irqbalance") echo inactive; exit 3 ;;
  "systemctl is-enabled "*) echo enabled ;;
  "systemctl is-active "*) echo active ;;
  "systemctl show --property=DefaultLimitMEMLOCK") echo "DefaultLimitMEMLOCK=8388608" ;;
  "journalctl -k -b --no-pager") cat "$F/klog-boot" ;;
  "journalctl -k --no-pager") cat "$F/klog-all" ;;
  "sysctl -n "*) echo 2 ;;
  "findmnt -n -o FSTYPE,OPTIONS /sys/fs/bpf") echo "bpf rw,nosuid,nodev,noexec,relatime,mode=700" ;;
  "dpkg-query -W "*) case "${*: -1}" in libbpf1|bpftool) echo "${*: -1} 1:1.6.3-1ubuntu1 install ok installed" ;; *) echo "dpkg-query: no packages found" >&2; exit 1 ;; esac ;;
  "apt-cache policy "*) printf '%s:\n  Installed: (none)\n  Candidate: 9.9-1\n' "${*: -1}" ;;
  "bpftool version") cat "$F/bpftool-version" ;;
  "bpftool -j feature probe kernel") cat "$F/bpftool-feature.json" ;;
  "bpftool -j net show") cat "$F/bpftool-net.json" ;;
  "bpftool -j prog show") cat "$F/bpftool-prog.json" ;;
  *) echo "shim: unexpected call: $name $args" >&2; exit 99 ;;
esac
EOF
chmod +x "$E2E/bin/shim"
for c in hostname id sleep ip ethtool ss systemctl journalctl sysctl findmnt dpkg-query apt-cache bpftool; do
  ln -sf shim "$E2E/bin/$c"
done

set_fake_link() { # flags mtu speed carrier oper
  printf '%s\n' "$1" >"$E2E/sys/class/net/eno1np0/flags"
  printf '%s\n' "$2" >"$E2E/sys/class/net/eno1np0/mtu"
  printf '%s\n' "$3" >"$E2E/sys/class/net/eno1np0/speed"
  printf '%s\n' "$4" >"$E2E/sys/class/net/eno1np0/carrier"
  printf '%s\n' "$5" >"$E2E/sys/class/net/eno1np0/operstate"
}
set_fake_link 0x1183 1500 10000 1 up
printf '100\n' >"$E2E/sys/class/net/eno1np0/statistics/rx_packets"
printf '1000\n' >"$E2E/sys/class/net/eno1np0/statistics/rx_bytes"
printf 'none [integrity] confidentiality\n' >"$E2E/sys/kernel/security/lockdown"
printf 'always [madvise] never\n' >"$E2E/sys/kernel/mm/transparent_hugepage/enabled"
: >"$E2E/sys/kernel/btf/vmlinux"
printf '1\n2\n3\n4\n' >"$E2E/capture-cores"
printf 'MemAvailable:   26000000 kB\nHugePages_Total:       0\nHugePages_Free:        0\nHugepagesize:       2048 kB\n' >"$E2E/proc/meminfo"
{
  printf '           CPU0       CPU1       CPU2       CPU3       CPU4\n'
  i=0
  for irq in 189 190 191 192 193 194 195 196 197 198 199 200; do
    printf ' %s:  0 0 0 0 0  IR-PCI-MSIX-0000:01:00.0  %s-edge  ice-eno1np0-TxRx-%s\n' "$irq" "$((i + 1))" "$i"
    mkdir -p "$E2E/proc/irq/$irq"
    cpu=$((i % 4 + 1))
    printf '%s\n' "$cpu" >"$E2E/proc/irq/$irq/effective_affinity_list"
    printf '%s\n' "$cpu" >"$E2E/proc/irq/$irq/smp_affinity_list"
    i=$((i + 1))
  done
} >"$E2E/proc/interrupts"

run_probe() { # mode [extra env as VAR=value ...]; sets E2E_RC, writes $E2E/out.txt
  local mode=$1
  shift
  rm -rf "$E2E/outdir"
  E2E_RC=0
  env -i PATH="$E2E/bin:$PATH" HOME="$HOME" E2E_FIX="$E2E/fix" E2E_SYSDIR="$E2E/sys" \
    M1S1_SYS="$E2E/sys" M1S1_PROC="$E2E/proc" M1S1_CORES_FILE="$E2E/capture-cores" \
    M1S1_KCONFIG="$E2E/fix/kconfig" M1S1_SAMPLE_SECS=1 M1S1_OUT="$E2E/outdir" "$@" \
    bash "$PROBE" "$mode" >"$E2E/out.txt" 2>"$E2E/err.txt" || E2E_RC=$?
}
rc_is() { # name want
  [ "$E2E_RC" = "$2" ] || fail "$1: rc $E2E_RC want $2; stdout: $(cat "$E2E/out.txt"); stderr: $(cat "$E2E/err.txt")"
}
has() { grep -qE "$1" "$E2E/out.txt" || fail "e2e: output missing /$1/: $(cat "$E2E/out.txt" "$E2E/err.txt")"; }
hasnt() { if grep -qE "$1" "$E2E/out.txt"; then fail "e2e: output has /$1/: $(grep -E "$1" "$E2E/out.txt")"; fi; }

# Happy path, user mode.
run_probe user E2E_UID=1000
rc_is "e2e user rc" 0
has '^M1S1-PROBE-DONE$'
has '^LINK eno1np0 flags=0x1183 mtu=1500 speed=10000 carrier=1 oper=up$'
has '^OK-mtu-1500$'
has '^OK-no-address$'
has '^OK-no-xdp-attached$'
has '^DRIVER ice$'
has '^BUS 0000:01:00.0$'
has '^OK-ddp-loaded$'
has '^MARTIAN-COUNT 2$'
has '^FEATURE large-receive-offload off-fixed$'
has '^NOTE-rxvlan-on'
has '^QUEUES-COMBINED max=64 cur=12$'
has '^RING rx=2048/8160 tx=2048/8160$'
has '^RSS-HASH toeplitz: on$'
has '^PRIV legacy-rx off$'
has '^STAT rx_unicast.nic 4242$'
has '^RX-RATE-1S pps=0 mbit=0$'
has '^NOTE-span-quiet$'
has '^CAPTURE-CORES 1,2,3,4$'
has '^IRQ-PER-CORE cpu1=3$'
has '^IRQ-PER-CORE cpu4=3$'
has '^OK-irq-pins total=12$'
has '^ZC-QUEUES queues=12 cores=4$'
has '^KCONFIG CONFIG_XDP_SOCKETS y$'
has '^KCONFIG CONFIG_XDP_SOCKETS_DIAG n$'
has '^LOCKDOWN integrity$'
has '^BPFFS bpf rw'
has '^SYSCTL kernel.unprivileged_bpf_disabled 2$'
has '^HUGEPAGES total=0 free=0 size=2048 kB$'
has '^MEM-AVAILABLE-MB 25390$'
has '^THP madvise$'
has '^NOTE-xsk-socket-list-unreliable \(CONFIG_XDP_SOCKETS_DIAG=n;'
has '^TOOL-ABSENT '
has '^PKG libbpf1 1:1.6.3-1ubuntu1 install ok installed$'
has '^PKG-ABSENT libxdp1$'
has '^APT-CANDIDATE libxdp1 9.9-1$'
has '^UNIT suricata enabled=disabled active=inactive$'
has '^UNIT johnny-capture-irq.service enabled=enabled active=active$'
hasnt '^STOP-'
[ -s "$E2E/outdir/summary.txt" ] || fail "e2e: no summary.txt"
[ -s "$E2E/outdir/ethtool-k.txt" ] || fail "e2e: no raw ethtool-k.txt"
grep -q '^M1S1-PROBE-DONE$' "$E2E/outdir/summary.txt" || fail "e2e: summary lacks the token"
[ ! -s "$E2E/err.txt" ] || fail "e2e: unexpected stderr: $(cat "$E2E/err.txt")"

# Traffic: the sleep shim moves the counters by 1000 packets and 125000000 bytes during the window.
run_probe user E2E_UID=1000 E2E_BUMP=1
rc_is "e2e traffic rc" 0
has '^RX-RATE-1S pps=1000 mbit=1000$'
has '^OK-span-traffic$'
hasnt '^NOTE-span-quiet$'
printf '100\n' >"$E2E/sys/class/net/eno1np0/statistics/rx_packets"
printf '1000\n' >"$E2E/sys/class/net/eno1np0/statistics/rx_bytes"

# Gates before any read.
run_probe user E2E_HOST=rock-box
rc_is "e2e wrong host rc" 1
has '^STOP-host rock-box$'
hasnt '^LINK '
[ ! -e "$E2E/outdir" ] || fail "e2e: wrong host created an output dir"
run_probe user E2E_UID=0
rc_is "e2e root rc" 1
has '^STOP-root$'
[ ! -e "$E2E/outdir" ] || fail "e2e: root created an output dir"

# Each precondition failure prints its STOP, withholds the token, still runs to the end.
stop_case() { # name expect_regex  (state already mutated by caller)
  run_probe user E2E_UID=1000 "${@:3}"
  rc_is "e2e $1 rc" 1
  has "$2"
  hasnt '^M1S1-PROBE-DONE$'
  has '^M1S1-PROBE-STOPS [1-9]'
  has '^UNIT suricata '
}
set_fake_link 0x1003 1500 10000 1 up
stop_case "no promisc" '^STOP-eno1-not-promisc flags=0x1003$'
has '^STOP-eno1-not-noarp'
set_fake_link 0x1183 9000 10000 1 up
stop_case "jumbo mtu" '^STOP-mtu-over-3000 9000$'
set_fake_link 0x1183 2000 10000 1 up
run_probe user E2E_UID=1000
rc_is "e2e mtu 2000 rc" 0
has '^NOTE-mtu-not-1500 2000$'
set_fake_link 0x1183 1500 1000 1 up
stop_case "slow link" '^STOP-link-not-10g-up speed=1000'
set_fake_link 0x1183 1500 10000 0 down
stop_case "link down" '^STOP-link-not-10g-up speed=10000 carrier=0 oper=down'
set_fake_link 0x1183 1500 10000 1 up
stop_case "suricata active" '^STOP-suricata-active$' E2E_SURICATA_ACTIVE=active
cp "$E2E/fix/iplink" "$E2E/fix/iplink.good"
cp "$TMP/iplink-xdp.txt" "$E2E/fix/iplink"
stop_case "xdp attached" '^STOP-xdp-attached-already$'
cp "$E2E/fix/iplink.good" "$E2E/fix/iplink"
printf 'eno1np0          UP             192.168.5.5/24 \n' >"$E2E/fix/ipaddr"
stop_case "has address" '^STOP-eno1-has-address count=1$'
printf 'eno1np0          UP             \n' >"$E2E/fix/ipaddr"
cp "$E2E/fix/klog-boot" "$E2E/fix/klog-boot.good"
printf '[    1.0] ice 0000:01:00.0: The DDP package could not be loaded, device is in Safe Mode\n' >"$E2E/fix/klog-boot"
stop_case "safe mode" '^STOP-ddp-safe-mode$'
cp "$E2E/fix/klog-boot.good" "$E2E/fix/klog-boot"
printf 'driver: i40e\nversion: 1\n' >"$E2E/fix/ethtool-i.bad"
cp "$E2E/fix/ethtool-i" "$E2E/fix/ethtool-i.good"
cp "$E2E/fix/ethtool-i.bad" "$E2E/fix/ethtool-i"
stop_case "wrong driver" '^STOP-driver-not-ice i40e$'
cp "$E2E/fix/ethtool-i.good" "$E2E/fix/ethtool-i"
printf '1\n2\n3\n4\n' >"$E2E/capture-cores"
printf '2\n' >"$E2E/proc/irq/190/effective_affinity_list"
printf '9\n' >"$E2E/proc/irq/191/effective_affinity_list"
stop_case "irq outside cores" '^STOP-irq-baseline-outside-capture-cores count=1$'
printf '2\n' >"$E2E/proc/irq/191/effective_affinity_list"
printf '1\n' >"$E2E/proc/irq/190/effective_affinity_list"
# B2 regression (reviewer, PR #22 tip b5d71e1): every queue IRQ outside the
# capture cores leaves per_core empty. The old loop hit `bad array subscript`
# and later sections never printed. Move all 12 IRQs to CPU 9 (cores are 1-4).
for irq in 189 190 191 192 193 194 195 196 197 198 199 200; do
  printf '9\n' >"$E2E/proc/irq/$irq/effective_affinity_list"
done
stop_case "all irqs outside cores" '^STOP-irq-baseline-outside-capture-cores count=12$'
has '^IRQ-PER-CORE none-inside-capture-cores$'
has '^ZC-QUEUES queues=12 cores=4$'
has '^M1S1-PROBE-STOPS [1-9]'
hasnt '^M1S1-PROBE-DONE$'
hasnt '^IRQ-PER-CORE cpu'
if grep -q 'bad array subscript' "$E2E/err.txt"; then fail "B2: bad array subscript on empty per_core"; fi
# Later sections still ran after the IRQ section.
has '^KCONFIG CONFIG_BPF_SYSCALL y$'
has '^UNIT johnny-capture-irq.service '
# Restore: the eight IRQs the earlier cases left alone go back to cores 1-4.
i=0
for irq in 189 190 191 192 193 194 195 196 197 198 199 200; do
  printf '%s\n' "$((i % 4 + 1))" >"$E2E/proc/irq/$irq/effective_affinity_list"
  i=$((i + 1))
done
run_probe user E2E_UID=1000
rc_is "e2e irqs restored rc" 0
has '^OK-irq-pins total=12$'
has '^IRQ-PER-CORE cpu1=3$'
mv "$E2E/capture-cores" "$E2E/capture-cores.good"
stop_case "no cores file" '^STOP-no-capture-cores$'
printf '1\nfoo\n' >"$E2E/capture-cores"
stop_case "bad cores file" '^STOP-capture-cores-form$'
mv "$E2E/capture-cores.good" "$E2E/capture-cores"
sed -i 's/^CONFIG_BPF_SYSCALL=y/# CONFIG_BPF_SYSCALL is not set/' "$E2E/fix/kconfig"
stop_case "no bpf syscall" '^STOP-kconfig-bpf-syscall n$'
sed -i 's/^# CONFIG_BPF_SYSCALL is not set/CONFIG_BPF_SYSCALL=y/' "$E2E/fix/kconfig"
sed -i 's/^CONFIG_XDP_SOCKETS=y/# CONFIG_XDP_SOCKETS is not set/' "$E2E/fix/kconfig"
run_probe user E2E_UID=1000
rc_is "e2e no xsk rc (a NOTE, not a STOP)" 0
has '^NOTE-no-af-xdp '
sed -i 's/^# CONFIG_XDP_SOCKETS is not set/CONFIG_XDP_SOCKETS=y/' "$E2E/fix/kconfig"

sed -i 's/^# CONFIG_XDP_SOCKETS_DIAG is not set/CONFIG_XDP_SOCKETS_DIAG=y/' "$E2E/fix/kconfig"
run_probe user E2E_UID=1000
rc_is "e2e diag y rc" 0
has '^OK-no-xsk-sockets$'
hasnt '^NOTE-xsk-socket-list-unreliable'
printf 'Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port\nxdp   UNCONN 0 0 *:eno1np0 *:*\n' >"$E2E/fix/ss-xdp"
run_probe user E2E_UID=1000
rc_is "e2e xsk present rc" 0
has '^NOTE-xsk-sockets-present count=1$'
printf 'Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port\n' >"$E2E/fix/ss-xdp"
sed -i 's/^CONFIG_XDP_SOCKETS_DIAG=y/# CONFIG_XDP_SOCKETS_DIAG is not set/' "$E2E/fix/kconfig"

# Back to the happy path once more: the mutations above were all undone.
run_probe user E2E_UID=1000
rc_is "e2e user rc again" 0
has '^M1S1-PROBE-DONE$'

# Root mode.
run_probe root E2E_UID=0
rc_is "e2e root-mode rc" 0
has '^M1S1-PROBE-ROOT-DONE$'
has '^BPFTOOL bpftool v7.7.0$'
has '^BPF-FEATURE have_xdp_prog_type yes$'
has '^BPF-FEATURE have_xskmap_map_type yes$'
has '^NOTE-feature-missing have_devmap_map_type$'
has '^NOTE-feature-key-absent have_ringbuf_map_type'
has '^BPF-XDP-HELPER bpf_redirect_map yes$'
has '^NOTE-helper-missing bpf_ringbuf_output$'
has '^OK-no-xdp-on-eno1np0$'
has '^PROG-XDP-COUNT 0$'
hasnt '^STOP-'
[ -s "$E2E/outdir/feature-probe.json" ] || fail "e2e: no raw feature-probe.json"
run_probe root E2E_UID=1000
rc_is "e2e root-mode as non-root rc" 1
has '^STOP-not-root$'
cp "$E2E/fix/bpftool-net.json" "$E2E/fix/bpftool-net.json.good"
printf '[{"xdp":[{"devname":"eno1np0","ifindex":3,"mode":"driver"}],"tc":[]}]\n' >"$E2E/fix/bpftool-net.json"
run_probe root E2E_UID=0
rc_is "e2e root-mode xdp attached rc" 1
has '^STOP-xdp-attached-on-eno1np0 modes=driver$'
hasnt '^M1S1-PROBE-ROOT-DONE$'
cp "$E2E/fix/bpftool-net.json.good" "$E2E/fix/bpftool-net.json"
printf '{"program_types":{"have_xdp_prog_type":false}}\n' >"$E2E/fix/bpftool-feature.json"
run_probe root E2E_UID=0
rc_is "e2e root-mode no xdp type rc" 1
has '^STOP-no-xdp-prog-type no$'
printf 'not json\n' >"$E2E/fix/bpftool-feature.json"
run_probe root E2E_UID=0
rc_is "e2e root-mode bad json rc" 1
has '^STOP-feature-json-parse$'
echo "E2E-OK"

# ---------------------------------------------------------------- static checks on the probe

bash -n "$PROBE" || fail "bash -n"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -s bash "$PROBE" || fail "shellcheck probe"
  shellcheck -x -s bash "$ROOT/docs/tool-install/module1-slice1-self-test.sh" || fail "shellcheck self-test"
else
  echo "SKIP-shellcheck (not installed)"
fi
grep -q '^set -euo pipefail$' "$PROBE" || fail "missing set -euo pipefail"

# Non-comment lines only.
grep -vE '^[[:space:]]*#' "$PROBE" >"$TMP/probe-code.txt"
forbidden='sudo|NOPASSWD|apt-get|apt[[:space:]]+(install|update|upgrade|remove)|ip[[:space:]]+(link|addr|route|neigh)[[:space:]]+(set|add|del|change|replace|flush)|sysctl[[:space:]]+-w|modprobe|rmmod|insmod|net[[:space:]]+(attach|detach)|prog[[:space:]]+(load|loadall|attach|detach|pin)|map[[:space:]]+(update|delete|create|pin)|probe[[:space:]]+kernel[[:space:]]+full|--legacy|systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload)|iptables|nft[[:space:]]|ufw[[:space:]]|netplan|networkctl|setpci|dracut|update-initramfs|update-grub|reboot|shutdown|chown|chmod|pci=noaer|[^a-z_]tc[[:space:]]+(qdisc|filter)|>[[:space:]]*/(sys|proc|etc|boot|root)/|tee[[:space:]]+-a[[:space:]]+/(sys|proc|etc)'
if grep -nE "$forbidden" "$TMP/probe-code.txt"; then
  fail "forbidden text in probe code (above)"
fi
# The only environment overrides are the documented test seams.
seams=$(grep -o 'M1S1_[A-Z_]*' "$PROBE" | sort -u | tr '\n' ' ')
expect_eq "env seams" "$seams" "M1S1_CORES_FILE M1S1_IFACE M1S1_KCONFIG M1S1_OUT M1S1_PROC M1S1_SAMPLE_SECS M1S1_SYS "
# Johnny-state commands never run bare: only through ro() / save().
if grep -nE '(^|[[:space:]]|\$\()(ip|ethtool|bpftool|systemctl|sysctl|journalctl|dpkg-query|apt-cache|findmnt|ss)[[:space:]]+-' "$TMP/probe-code.txt" |
  grep -vE '^[0-9]+:[[:space:]]*(\[|local )' |
  grep -vE '\b(ro|save [A-Za-z0-9._-]+)[[:space:]]+(ip|ethtool|bpftool|systemctl|sysctl|journalctl|dpkg-query|apt-cache|findmnt|ss)' |
  grep -vE '^[0-9]+:[[:space:]]*"(bpftool|ip|ethtool)'; then
  fail "a Johnny-state command is not routed through ro/save (above)"
fi

# Every ro/save invocation in the script must pass ro_allowed once its shell variables are filled in.
python3 -I - "$PROBE" "$TMP/invocations.txt" <<'PY'
import pathlib, re, shlex, sys
src = pathlib.Path(sys.argv[1]).read_text().splitlines()
subs = {
    '"$IFACE"': "eno1np0",
    '"$p"': "libbpf1",
    '"$u"': "suricata",
    '"$key"': "net.core.busy_poll",
}
pat = re.compile(
    r'(?:\bro|\bsave\s+\S+)\s+'
    r'((?:ip|ethtool|ss|systemctl|journalctl|sysctl|findmnt|dpkg-query|apt-cache|bpftool)\b[^|;&)<>]*)'
)
out = []
for line in src:
    if line.lstrip().startswith("#"):
        continue
    for m in pat.finditer(line):
        s = m.group(1)
        s = re.sub(r"\s+\d+$", "", s)  # a trailing 2 from `2>/dev/null`
        s = s.replace('-f="${DPKG_FMT}"', "-f=@DPKG@")
        for k, v in subs.items():
            s = s.replace(k, v)
        s = re.sub(r"\s+\d+$", "", s)
        if "$" in s:
            raise SystemExit(f"unresolved variable in invocation: {s!r}")
        out.append("\x1f".join(shlex.split(s)))
if len(out) < 25:
    raise SystemExit(f"only {len(out)} ro/save invocations found; extractor is broken")
pathlib.Path(sys.argv[2]).write_text("\n".join(out) + "\n")
PY
count=0
while IFS= read -r rec; do
  IFS=$'\x1f' read -ra args <<<"$rec"
  for i in "${!args[@]}"; do
    [ "${args[$i]}" = '-f=@DPKG@' ] && args[i]="-f=${DPKG_FMT}"
  done
  ro_allowed "${args[@]}" || fail "script invokes a command ro_allowed refuses: ${args[*]}"
  count=$((count + 1))
done <"$TMP/invocations.txt"
echo "STATIC-INVOCATIONS-OK $count"

# ---------------------------------------------------------------- runbook cross-checks

[ -f "$DOC" ] || fail "runbook missing: $DOC"
want_sha=$(sha256sum "$PROBE" | awk '{print $1}')
grep -q "$want_sha" "$DOC" || fail "runbook does not carry the probe sha256 $want_sha"
for tok in M1S1-PROBE-DONE M1S1-PROBE-ROOT-DONE; do
  grep -q "$tok" "$DOC" || fail "runbook missing token $tok"
  grep -q "$tok" "$PROBE" || fail "probe missing token $tok"
done

python3 -I - "$DOC" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
blocks = {}
for m in re.finditer(r"^## (Paste [12][^\n]*)\n(.*?)(?=^## )", text, re.M | re.S):
    code = re.search(r"```bash\n(.*?)\n```", m.group(2), re.S)
    if not code:
        raise SystemExit(f"no bash block under {m.group(1)!r}")
    blocks[m.group(1).split(" ")[1]] = code.group(1)
if set(blocks) != {"1", "2"}:
    raise SystemExit(f"expected Paste 1 and Paste 2, got {sorted(blocks)}")
p1, p2 = blocks["1"], blocks["2"]
if "sudo" in p1:
    raise SystemExit("Paste 1 must not use sudo")
# N2 (reviewer): a bare `sudo -v` line runs on rock-box, not Johnny. Every sudo
# in Paste 2 must sit inside the single `ssh -t` line that runs on Johnny.
for ln in p2.splitlines():
    if re.search(r"\bsudo\b", ln) and not ln.startswith("ssh -t aj@192.168.50.152 'sudo -v && "):
        raise SystemExit(f"Paste 2 has a sudo outside the Johnny ssh -t line: {ln!r}")
if not any(ln.startswith("ssh -t aj@192.168.50.152 'sudo -v && ") for ln in p2.splitlines()):
    raise SystemExit("Paste 2 must run sudo -v first inside the Johnny ssh -t command")
for name, b in blocks.items():
    if re.search(r"<[A-Za-z][^>\n]*>", b):
        raise SystemExit(f"placeholder in Paste {name}")
    if "sha256sum -c" not in b:
        raise SystemExit(f"Paste {name} does not verify the script hash")
    if "module1-slice1-probe.sh" not in b:
        raise SystemExit(f"Paste {name} does not name the script")
if " user" not in p1 or " root" not in p2:
    raise SystemExit("modes not wired into the pastes")
# All fenced bash blocks in the doc: no placeholders.
for i, b in enumerate(re.findall(r"```bash\n(.*?)\n```", text, re.S)):
    if re.search(r"<[A-Za-z][^>\n]*>", b):
        raise SystemExit(f"placeholder in bash block {i}")
PY

# The runbook's STOP table lists every STOP code the probe can print.
python3 -I - "$PROBE" "$DOC" <<'PY'
import pathlib, re, sys
probe = pathlib.Path(sys.argv[1]).read_text()
doc = pathlib.Path(sys.argv[2]).read_text()
codes = set(re.findall(r'\bstop "([a-z0-9-]+)', probe))
codes |= set(re.findall(r'"?STOP-([a-z0-9-]+)', probe))
codes -= {"not-readonly"}  # asserted separately below
missing = sorted(c for c in codes if f"`STOP-{c}" not in doc)
if missing:
    raise SystemExit(f"runbook STOP table is missing: {missing}")
if "`STOP-not-readonly" not in doc:
    raise SystemExit("runbook missing STOP-not-readonly")
PY

# Slice 1 must not drag in Suricata config, a sudoers change, or the DDP COMMS download.
for f in "$PROBE" "$DOC"; do
  if grep -nE 'NOPASSWD' "$f" | grep -viE 'no |not |never|without|does not|narrow'; then
    fail "NOPASSWD outside a negation in $f"
  fi
done
[ ! -e "$ROOT/etc/suricata" ] || fail "etc/suricata exists: Detection owns that, not this slice"
git -C "$ROOT" diff --quiet -- docs/agent-team.md || fail "docs/agent-team.md edited (Brain's file)"

echo SELF-TEST-OK
