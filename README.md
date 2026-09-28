# slop-scanner-plugins

The **Extension Index** for [Slop-Scanner](https://github.com/LawsonLamb/slop-scanner): the list of Language Extensions that `slop extension install <id>` reads, with the Extension archives attached to this repository's [Releases](../../releases). There is no server. `slop` fetches `index/extensions.json` and `index/<id>.json` from this repository's `main` branch through `raw.githubusercontent.com`, downloads the archive an entry names, checks its SHA-256 and unpacks it into the user's Extension directory.

## Layout

```
extensions.toml        every Extension's source repository, published tag and directory
index/extensions.json  one line per Extension:  {"id":"python","kind":"language","description":"…"}
index/<id>.json     one line per version: {"id":"python","version":"0.1.0","kind":"language","slop_api":1,"grammar_abi":15,
                                           "url":"…/releases/download/python-v0.1.0/python-0.1.0.tar.gz","sha256":"…","yanked":false}
scripts/pack.sh     packs one Extension directory reproducibly and prints its index line
scripts/publish.sh  publishes what extensions.toml names and index/ lacks (what CI runs)
```

A version line is never removed. To withdraw one, set `"yanked": true` on its line; `slop` then skips it.

## Publishing an Extension

1. Put the Extension in a git repository: a directory named after its id holding `extension.toml` and, for a Language Extension, `adapter.toml` and the `*.scm` queries, with `grammar_source` pinned in `extension.toml` (a checked-in `grammar.wasm` is fine too; without one CI builds it with the pinned tree-sitter CLI). See `docs/extensions/` in the Slop-Scanner repository.
2. Tag the repository.
3. Open a pull request here adding or bumping the Extension's table in `extensions.toml`:

   ```toml
   [zig]
   repository = "https://github.com/you/slop-lang-zig"
   tag = "v0.1.0"   # or rev = "<commit id>"
   # path = "…"   only when the Extension directory is not the repository root
   ```

   The pull request's check packs the archive and prints the index line without publishing.
4. On merge, the `Publish extensions` workflow (which reads private source repositories through the `SLOP_SOURCE_TOKEN` repository secret, a token with read access to them) creates the release `zig-v0.1.0` with `zig-0.1.0.tar.gz`, appends the line to `index/zig.json` and lists the Extension in `index/extensions.json`.

`slop` picks, for a requested id, the newest version that is not yanked, was built for its own `slop_api` and whose grammar ABI its tree-sitter reads; `slop extension install zig@0.1` narrows it.

## Trust

Review of the pull request plus the SHA-256 in the index. Archives are built by this repository's CI from the tagged source, never uploaded by hand. GitHub's artifact attestations can be added to the workflow for Sigstore provenance; a signed index is the next step should third-party Extensions appear.

## First-party Extensions

The five languages built into `slop` (Rust, TypeScript/JavaScript, Python, Go, Java) are also published as Extensions from the Slop-Scanner repository's `languages/<lang>/` directories, so a grammar or query fix can reach users before the next release: an installed Language Extension replaces the built-in language with its id.
