# slop-scanner-plugins

The **Plugin Index** for [Slop-Scanner](https://github.com/LawsonLamb/slop-scanner): the list of Language and VCS Plugins that `slop plugin install <id>` reads, with the Plugin archives attached to this repository's [Releases](../../releases). There is no server. `slop` fetches `index/plugins.json` and `index/<id>.json` from this repository's `main` branch through `raw.githubusercontent.com`, downloads the archive an entry names, checks its SHA-256 and unpacks it into the user's Plugin directory.

## Layout

```
plugins.toml        every Plugin's source repository, published tag and directory
index/plugins.json  one line per Plugin:  {"id":"python","kind":"language","description":"…"}
index/<id>.json     one line per version: {"id":"python","version":"0.1.0","kind":"language","slop_api":1,"grammar_abi":15,
                                           "url":"…/releases/download/python-v0.1.0/python-0.1.0.tar.gz","sha256":"…","yanked":false}
scripts/pack.sh     packs one Plugin directory reproducibly and prints its index line
scripts/publish.sh  publishes what plugins.toml names and index/ lacks (what CI runs)
```

A version line is never removed. To withdraw one, set `"yanked": true` on its line; `slop` then skips it.

## Publishing a Plugin

1. Put the Plugin in a git repository: a directory named after its id holding `plugin.toml` and, for a Language Plugin, `adapter.toml` and the `*.scm` queries, with `grammar_source` pinned in `plugin.toml` (a checked-in `grammar.wasm` is fine too; without one CI builds it with the pinned tree-sitter CLI). For a VCS Plugin, the executable. See `docs/plugins/` in the Slop-Scanner repository.
2. Tag the repository.
3. Open a pull request here adding or bumping the Plugin's table in `plugins.toml`:

   ```toml
   [zig]
   repository = "https://github.com/you/slop-lang-zig"
   tag = "v0.1.0"   # or rev = "<commit id>"
   # path = "…"   only when the Plugin directory is not the repository root
   ```

   The pull request's check packs the archive and prints the index line without publishing.
4. On merge, the `Publish plugins` workflow (which reads private source repositories through the `SLOP_SOURCE_TOKEN` repository secret, a token with read access to them) creates the release `zig-v0.1.0` with `zig-0.1.0.tar.gz`, appends the line to `index/zig.json` and lists the Plugin in `index/plugins.json`.

`slop` picks, for a requested id, the newest version that is not yanked, was built for its own `slop_api`, and whose grammar ABI its tree-sitter reads; `slop plugin install zig@0.1` narrows it.

## Trust

Review of the pull request plus the SHA-256 in the index. Archives are built by this repository's CI from the tagged source, never uploaded by hand. GitHub's artifact attestations can be added to the workflow for Sigstore provenance; a signed index is the next step should third-party Plugins appear.

## First-party Plugins

The five languages that ship with `slop` (Rust, TypeScript/JavaScript, Python, Go, Java) are published from the Slop-Scanner repository's own tags, so a `slop` built from source can `slop plugin install rust typescript python go java` and get exactly the files a release archive bundles.
