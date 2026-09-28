#!/usr/bin/env bash
# Publishes every Extension in extensions.toml whose version is not yet in the
# index: clones its repository at the tag, builds grammar.wasm when the
# checkout has none, packs the archive, creates the GitHub Release
# `<id>-v<version>` with it, and appends the line to index/<id>.json.
#
#   scripts/publish.sh [--dry-run] [<id>...]
#
# Needs `gh` logged in with write access to this repository (CI: the
# workflow's GITHUB_TOKEN), `git`, and for Language Extensions without a
# checked-in grammar.wasm the tree-sitter CLI. `--dry-run` packs and prints
# the index lines without releasing or writing the index.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dry=0
ids=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    *) ids+=("$arg") ;;
  esac
done
repo_slug="${GITHUB_REPOSITORY:-LawsonLamb/slop-scanner-extensions}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Reads `key` of the [id] table in extensions.toml.
entry() { # <id> <key>
  awk -v section="[$1]" -v key="$2" '
    /^\[/ { in_section = ($0 == section) }
    in_section && $1 == key { gsub(/"/, "", $3); print $3; exit }
  ' "$root/extensions.toml"
}
if [ ${#ids[@]} -eq 0 ]; then
  while read -r id; do ids+=("$id"); done < <(sed -n 's/^\[\([a-z0-9.-]*\)\]$/\1/p' "$root/extensions.toml")
fi

for id in "${ids[@]}"; do
  repo="$(entry "$id" repository)"
  tag="$(entry "$id" tag)"
  rev="$(entry "$id" rev)"
  path="$(entry "$id" path)"
  [ -n "$repo" ] && { [ -n "$tag" ] || [ -n "$rev" ]; } \
    || { echo "$id: extensions.toml needs repository and a tag or rev" >&2; exit 2; }
  clone="$work/$id"
  # A private source repository is cloned with SLOP_SOURCE_TOKEN (a
  # fine-grained token with read access to it), never asked for a password.
  clone_url="$repo"
  if [ -n "${SLOP_SOURCE_TOKEN:-}" ]; then
    clone_url="${repo/https:\/\/github.com\//https://x-access-token:$SLOP_SOURCE_TOKEN@github.com/}"
  fi
  if [ -n "$tag" ]; then
    GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 --branch "$tag" "$clone_url" "$clone"
  else
    # A commit id cannot be cloned shallowly by name.
    GIT_TERMINAL_PROMPT=0 git clone --quiet "$clone_url" "$clone"
    git -C "$clone" checkout --quiet --detach "$rev"
    tag="$rev"
  fi
  src="$clone${path:+/$path}"
  [ "$(basename "$src")" = "$id" ] || { echo "$id: $src is not named after the extension" >&2; exit 2; }
  if grep -q '^kind *= *"language"' "$src/extension.toml" && [ ! -f "$src/grammar.wasm" ]; then
    # The Extension ships no .wasm: build it from grammar_source.
    g_repo="$(sed -n 's/^grammar_source *= *{.*repository *= *"\([^"]*\)".*/\1/p' "$src/extension.toml")"
    g_rev="$(sed -n 's/^grammar_source *= *{.*rev *= *"\([^"]*\)".*/\1/p' "$src/extension.toml")"
    g_path="$(sed -n 's/^grammar_source *= *{.*[{ ,]path *= *"\([^"]*\)".*/\1/p' "$src/extension.toml")"
    [ -n "$g_repo" ] && [ -n "$g_rev" ] || { echo "$id: no grammar.wasm and no grammar_source" >&2; exit 2; }
    git clone --quiet "$g_repo" "$work/$id-grammar"
    git -C "$work/$id-grammar" checkout --quiet --detach "$g_rev"
    (cd "$work/$id-grammar${g_path:+/$g_path}" && tree-sitter build --wasm -o "$src/grammar.wasm" .)
  fi
  version="$(sed -n 's/^version *= *"\([^"]*\)".*/\1/p' "$src/extension.toml" | head -1)"
  index_file="$root/index/$id.json"
  if [ -f "$index_file" ] && grep -q "\"version\":\"$version\"" "$index_file"; then
    echo "$id $version is already published"
    continue
  fi
  line="$("$root/scripts/pack.sh" "$src" "$work/dist" "https://github.com/$repo_slug/releases/download/{id}-v{version}/{file}")"
  echo "$line"
  if [ "$dry" = 1 ]; then
    continue
  fi
  gh release create "$id-v$version" "$work/dist/$id-$version.tar.gz" \
    --repo "$repo_slug" --title "$id $version" \
    --notes "Extension \`$id\` $version, from $repo at $tag. Install with \`slop extension install $id\`." >/dev/null
  echo "$line" >>"$index_file"
  if ! grep -Eq "\"id\": *\"$id\"" "$root/index/extensions.json"; then
    description="$(sed -n 's/^description *= *"\([^"]*\)".*/\1/p' "$src/extension.toml" | head -1)"
    kind="$(sed -n 's/^kind *= *"\([^"]*\)".*/\1/p' "$src/extension.toml" | head -1)"
    printf '{"id":"%s","kind":"%s","description":"%s"}\n' "$id" "$kind" "$description" >>"$root/index/extensions.json"
  fi
  echo "published $id $version"
done
