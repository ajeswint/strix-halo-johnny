#!/usr/bin/env bash
# Build the Stage 1 johnny-daemon release binary, emit its SHA-256 digest,
# and emit a deterministic CycloneDX 1.5 JSON SBOM from Cargo.lock +
# cargo metadata (cargo-cyclonedx is not installed on Rock Box). Runs on
# Rock Box with no sudo and no network (--locked --offline).

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

if [ -d "$HOME/.cargo/bin" ]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

cargo build --release --locked --offline

BIN="target/release/johnny-daemon"
[ -f "$BIN" ] || { echo "STOP-release-binary-missing $BIN" >&2; exit 1; }

mkdir -p dist
cp -f "$BIN" dist/johnny-daemon
chmod 0755 dist/johnny-daemon

BIN_SHA=$(sha256sum dist/johnny-daemon | awk '{print $1}')
printf '%s  dist/johnny-daemon\n' "$BIN_SHA" > dist/johnny-daemon.sha256
sha256sum -c dist/johnny-daemon.sha256 >/dev/null

# cargo-cyclonedx is not installed on Rock Box (cargo --list). Keep the
# deterministic cargo-metadata-lockfile document and tool name rather than
# mixing two generators.
SBOM_TOOL="cargo-metadata-lockfile"

METADATA_JSON=$(cargo metadata --format-version 1 --locked --offline)
RUSTC_VER=$(rustc --version)

python3 -I - "$BIN_SHA" "$RUSTC_VER" "$SBOM_TOOL" "Cargo.lock" "johnny-daemon.cdx.json" "$METADATA_JSON" <<'PY'
import json, re, sys

bin_sha, rustc_ver, sbom_tool, lock_path, out_path, meta_raw = sys.argv[1:7]
meta = json.loads(meta_raw)

# Parse checksums from Cargo.lock
checksums = {}
cur_name = None
cur_ver = None
with open(lock_path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line == "[[package]]":
            cur_name = None
            cur_ver = None
        elif line.startswith('name = "'):
            cur_name = line.split('"')[1]
        elif line.startswith('version = "'):
            cur_ver = line.split('"')[1]
        elif line.startswith('checksum = "') and cur_name and cur_ver:
            checksums[(cur_name, cur_ver)] = line.split('"')[1]

# Collect reachable packages in the resolve graph starting from johnny-daemon
pkg_by_id = {p["id"]: p for p in meta["packages"]}
nodes_by_id = {n["id"]: n for n in meta["resolve"]["nodes"]}

root_id = next(
    p["id"] for p in meta["packages"] if p["name"] == "johnny-daemon"
)

reachable = set()
stack = [root_id]
while stack:
    cid = stack.pop()
    if cid in reachable:
        continue
    reachable.add(cid)
    for dep in nodes_by_id[cid].get("deps", []):
        # Exclude dev-only edges (e.g. test-only crates)
        kinds = [k.get("kind") for k in dep.get("dep_kinds", [])]
        if kinds and all(k == "dev" for k in kinds):
            continue
        stack.append(dep["pkg"])

def bom_ref(pkg):
    return f"pkg:cargo/{pkg['name']}@{pkg['version']}"

components = []
for cid in sorted(reachable, key=lambda i: (pkg_by_id[i]["name"], pkg_by_id[i]["version"])):
    if cid == root_id:
        continue
    p = pkg_by_id[cid]
    comp = {
        "type": "library",
        "bom-ref": bom_ref(p),
        "name": p["name"],
        "version": p["version"],
        "purl": bom_ref(p),
    }
    if p.get("license"):
        comp["licenses"] = [{"license": {"expression": p["license"]}}]
    ck = checksums.get((p["name"], p["version"]))
    if ck:
        comp["hashes"] = [{"alg": "SHA-256", "content": ck}]
    components.append(comp)

dependencies = []
for cid in sorted(reachable, key=lambda i: (pkg_by_id[i]["name"], pkg_by_id[i]["version"])):
    p = pkg_by_id[cid]
    deps_on = []
    for dep in nodes_by_id[cid].get("deps", []):
        if dep["pkg"] in reachable:
            deps_on.append(bom_ref(pkg_by_id[dep["pkg"]]))
    dependencies.append({
        "ref": bom_ref(p),
        "dependsOn": sorted(set(deps_on)),
    })

root_pkg = pkg_by_id[root_id]
doc = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "version": 1,
    "metadata": {
        "tools": [
            {"name": sbom_tool},
            {"name": "rustc", "version": rustc_ver},
        ],
        "component": {
            "type": "application",
            "bom-ref": bom_ref(root_pkg),
            "name": root_pkg["name"],
            "version": root_pkg["version"],
            "hashes": [{"alg": "SHA-256", "content": bin_sha}],
        },
    },
    "components": components,
    "dependencies": dependencies,
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY

cp -f johnny-daemon.cdx.json dist/johnny-daemon.cdx.json
echo "RELEASE-BINARY dist/johnny-daemon sha256=$BIN_SHA"
echo "RELEASE-SBOM johnny-daemon.cdx.json tool=$SBOM_TOOL"
echo "STAGE1-RELEASE-OK"
