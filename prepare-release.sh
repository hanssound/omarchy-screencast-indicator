#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

bash -n probe.sh prepare-release.sh
node Model.test.js
python3 probe.test.py
python3 qml.test.py
omarchy plugin validate "$PWD"

# The Git allowlist is also the archive allowlist; never package the whole folder.
mapfile -t files < <(sed -n 's/^!\///p' .gitignore)
python3 - "${files[@]}" <<'PY'
import json
from pathlib import Path
import re
import sys

files = sys.argv[1:]
assert files and len(files) == len(set(files)), "Invalid release allowlist"
patterns = [r"/(?:home|Users)/[A-Za-z0-9_.-]+/",
            r"(?:github_pat_|gh[pousr]_|sk-(?:proj-)?)[A-Za-z0-9_]{16,}",
            r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"]
for name in files:
    path = Path(name)
    assert re.fullmatch(r"[A-Za-z0-9._-]+", name) and path.is_file() and not path.is_symlink(), name
    text = path.read_text()
    assert not any(re.search(pattern, text) for pattern in patterns), "Privacy check failed: " + name
manifest = json.loads(Path("manifest.json").read_text())
assert manifest["id"] == "hanssound.screencast-indicator"
assert manifest["author"] == "hanssound" and manifest["license"] == "0BSD"
assert {"README.md", "LICENSE", "manifest.json"} <= set(files)
print("Release privacy check PASS (%d files)" % len(files))
PY

id=$(jq -r '.id' manifest.json)
version=$(jq -r '.version' manifest.json)
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid release version" >&2; exit 1; }
mkdir -p .release
bundle=".release/$id-$version.tar.gz"
tar --owner=0 --group=0 --numeric-owner --mtime=@0 --transform="s,^,$id/," \
  -czf "$bundle" -- "${files[@]}"
python3 - "$bundle" "$id" "${files[@]}" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1]) as archive:
    members = archive.getmembers()
    assert {m.name for m in members} == {sys.argv[2] + "/" + f for f in sys.argv[3:]}
    assert all(m.isfile() and m.uid == m.gid == m.mtime == 0 and not m.uname and not m.gname for m in members)
print("Archive contents and metadata PASS")
PY
printf 'Ready: %s\n' "$bundle"
