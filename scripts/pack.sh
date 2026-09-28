#!/usr/bin/env bash
# Packs one Extension directory into <id>-<version>.tar.gz and prints the
# index line for it.
#
#   scripts/pack.sh <extension dir> <out dir> <download url template>
#
# The template may use {id}, {version} and {file}; the default is this
# repository's GitHub Releases. Prints one JSON object (an index/<id>.json
# line) on stdout. The archive is reproducible: entries sorted, mtimes
# zeroed, no owner, so the same Extension files always give the same SHA-256.
set -euo pipefail

dir="$(cd "$1" && pwd)"
out="$2"
template="${3:-}"
# Braces in a `${3:-default}` would end the expansion early, so the default is set apart.
[ -n "$template" ] || template='https://github.com/LawsonLamb/slop-scanner-plugins/releases/download/{id}-v{version}/{file}'
mkdir -p "$out"

manifest="$dir/extension.toml"
[ -f "$manifest" ] || { echo "$dir: no extension.toml" >&2; exit 2; }
field() { sed -n 's/^'"$1"' *= *"\([^"]*\)".*/\1/p' "$manifest" | head -1; }
num() { sed -n 's/^'"$1"' *= *\([0-9][0-9]*\).*/\1/p' "$manifest" | head -1; }
id="$(field id)"
version="$(field version)"
kind="$(field kind)"
slop_api="$(num slop_api)"
grammar_abi="$(num grammar_abi)"
[ -n "$id" ] && [ -n "$version" ] && [ -n "$kind" ] && [ -n "$slop_api" ] \
  || { echo "$manifest: id, version, kind and slop_api are required" >&2; exit 2; }
[ "$(basename "$dir")" = "$id" ] || { echo "$dir: directory is not named after its id '$id'" >&2; exit 2; }
case "$kind" in
  language)
    grammar="$(field grammar)"; grammar="${grammar:-grammar.wasm}"
    for f in "$grammar" adapter.toml; do
      [ -f "$dir/$f" ] || { echo "$dir: missing $f" >&2; exit 2; }
    done
    [ -n "$grammar_abi" ] || { echo "$manifest: grammar_abi is required" >&2; exit 2; }
    ;;
  *) echo "$manifest: unknown kind $kind" >&2; exit 2 ;;
esac

file="$id-$version.tar.gz"
archive="$out/$file"
python3 - "$dir" "$archive" "$id" <<'EOF'
import gzip, io, os, sys, tarfile
src, dest, top = sys.argv[1:4]
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w") as tar:
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(root, name)
            rel = os.path.relpath(path, src)
            info = tar.gettarinfo(path, arcname=f"{top}/{rel}")
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mtime = 0
            with open(path, "rb") as f:
                tar.addfile(info, f)
with open(dest, "wb") as f:
    with gzip.GzipFile(fileobj=f, mode="wb", mtime=0) as gz:
        gz.write(buf.getvalue())
EOF
sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
url="$(python3 -c 'import sys; t, i, v, f = sys.argv[1:]; print(t.replace("{id}", i).replace("{version}", v).replace("{file}", f))' "$template" "$id" "$version" "$file")"
abi_field=""
[ -n "$grammar_abi" ] && abi_field=",\"grammar_abi\":$grammar_abi"
printf '{"id":"%s","version":"%s","kind":"%s","slop_api":%s%s,"url":"%s","sha256":"%s","yanked":false}\n' \
  "$id" "$version" "$kind" "$slop_api" "$abi_field" "$url" "$sha256"
