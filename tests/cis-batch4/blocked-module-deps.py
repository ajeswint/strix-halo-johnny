#!/usr/bin/env python3
"""Batch 4 review check: does any module that is NOT blocked depend on a blocked one?

Usage (Assurance, laptop only; nothing runs on Johnny):
  1. curl -O http://archive.ubuntu.com/ubuntu/pool/main/l/linux/linux-modules-7.0.0-42-generic_7.0.0-42.42_amd64.deb
  2. mkdir x && cd x && ar x ../linux-modules-7.0.0-42-generic_7.0.0-42.42_amd64.deb   (data.tar is uncompressed)
  3. pip install --target zst zstandard
  4. python3 -I blocked-module-deps.py zst x/data.tar docs/cis-fix/batch-4.md

Reads the `depends=` field from each .ko.zst `.modinfo` (what depmod would use) and
the blocked set from the draft (A1 twelve names, A2 sixty names, A2b overlay).
Exit 1 if a dependent outside the expected protocol / hardware families is found.
"""
import json, re, struct, sys, tarfile

zdir, tarpath, draft = sys.argv[1:4]
sys.path.insert(0, zdir)
import zstandard  # noqa: E402

dctx = zstandard.ZstdDecompressor()


def modinfo(data):
    shoff = struct.unpack_from('<Q', data, 0x28)[0]
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', data, 0x3A)
    secs = [struct.unpack_from('<IIQQQQ', data, shoff + i * shentsize) for i in range(shnum)]
    stroff = secs[shstrndx][4]
    for name, _t, _f, _a, offset, size in secs:
        n = data[stroff + name:data.index(b'\0', stroff + name)].decode()
        if n == '.modinfo':
            return [x.decode(errors='replace') for x in data[offset:offset + size].split(b'\0') if x]
    return []


mods = {}
with tarfile.open(tarpath) as tf:
    for m in tf:
        if not m.isfile() or '.ko' not in m.name:
            continue
        raw = tf.extractfile(m).read()
        if m.name.endswith('.zst'):
            raw = dctx.decompress(raw, max_output_size=200_000_000)
        base = m.name.rsplit('/', 1)[1].split('.ko')[0].replace('-', '_')
        dep = []
        for kv in modinfo(raw):
            k, _, v = kv.partition('=')
            if k == 'depends':
                dep += [x.replace('-', '_') for x in v.split(',') if x]
        mods[base] = dep

text = open(draft).read()
a2 = set(re.search(r"for m in ([^;]+); do printf", text).group(1).split())
a1 = {'cramfs', 'freevxfs', 'hfs', 'hfsplus', 'jffs2', 'firewire_core', 'usb_storage',
      'atm', 'can', 'rds', 'sctp', 'tipc'}
blocked = a1 | a2 | {'overlay'}
print('modules read:', len(mods), ' blocked names:', len(blocked),
      ' missing from kernel:', sorted(b for b in blocked if b not in mods))


def ancestors(m, seen):
    for d in mods.get(m, []):
        if d not in seen:
            seen.add(d)
            ancestors(d, seen)
    return seen


hits = {m: sorted(ancestors(m, set()) & blocked) for m in mods if m not in blocked}
hits = {m: s for m, s in hits.items() if s}
by_parent = {}
for m, s in hits.items():
    for p in s:
        by_parent.setdefault(p, []).append(m)
for p in sorted(by_parent):
    print(f'{p}: {len(by_parent[p])} dependents: {sorted(by_parent[p])}')
expected_parents = {'atm', 'can', 'rds', 'sctp', 'tipc', 'firewire_core', 'usb_storage', 'netfs', 'dlm'}
unexpected = {p: d for p, d in by_parent.items() if p not in expected_parents}
print('UNEXPECTED parents:', unexpected or 'none')
for keep in ('xfs', 'autofs4', 'binfmt_misc', 'ice', 'r8169', 'igc', 'nvme', 'dm_crypt',
             'nf_tables', 'nf_conntrack', 'xt_conntrack', 'nft_ct', 'ip_tables'):
    anc = ancestors(keep, set()) & blocked if keep in mods else None
    print('needed module', keep, '->', 'not a module' if anc is None else (sorted(anc) or 'no blocked ancestor'))
sys.exit(1 if unexpected else 0)
