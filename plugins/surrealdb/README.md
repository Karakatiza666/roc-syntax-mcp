# @roc-syntax/surrealdb

The [roc-reify-surrealdb](https://github.com/Karakatiza666/roc-reify-surrealdb)
SurrealDB ORM for Roc, as a corpus
[roc-syntax-mcp](https://github.com/Karakatiza666/roc-syntax-mcp) can serve: the
package's public module, five of its examples, four topic programs written
against it, and an overview page on which every claim was compiled.

## The compiler is a fork

The package needs the **reify fork of the Roc compiler**, not a nightly. `Code(f)`
is a type of that fork. Use the `reify` branch of
[Karakatiza666/roc](https://github.com/Karakatiza666/roc) at commit
`76ed44249ac086e593325c58f56d96d8dc4ffd47`, the commit of the package's
`.roc-version`. The release `nightly-reify-2026-11-07-76ed442` of
[Karakatiza666/roc-reify-nightlies](https://github.com/Karakatiza666/roc-reify-nightlies)
has prebuilt binaries of it. Unpack one and point this server at it:

```bash
gh release download nightly-reify-2026-11-07-76ed442 -R Karakatiza666/roc-reify-nightlies -p '*linux_x86_64*'
tar -xzf roc_nightly-reify-linux_x86_64-2026-11-07-76ed442.tar.gz
roc-syntax-mcp roc use $PWD/roc_nightly-reify-linux_x86_64-2026-11-07-76ed442/roc
```

A stock nightly rejects the package's programs with "missing method" errors,
and none of them mentions `Code`.

The plugin was validated with that release build. It documents package release
0.0.4, which needs SurrealDB 4.0.1 or later.
[`BUILD-PROOF`](BUILD-PROOF) records the compiler and the digest of the
validated files.

roc-reify-surrealdb is a package rather than a platform, so this plugin adds no
scope. It serves the `Karakatiza666/roc-reify-surrealdb` namespace. When an
app's header pins the package, a search covers its names together with the
builtins. The page, topics and examples answer even before any app pins it.

```bash
roc-syntax-mcp plugin add @roc-syntax/surrealdb
```

Then `get_roc_syntax(topic: "surrealdb")` for the page,
`get_roc_syntax(topic: "surreal_queries")` for a complete program,
`search_symbols Surreal.Table` for one signature.

| Path | Is |
|---|---|
| `index.json` | The release's modules, parsed by `plugin index`. No source is vendored |
| `examples/` | Upstream's `monitoring`, `search`, `client`, `watch` and `server` examples, repinned to the release URL |
| `topics/` | Four programs written for this corpus: schema, queries, a session and a live query |
| `verify/` | Every snippet the overview shows, compiled as one app |
| `overview.md` | What `get_roc_syntax(topic: "surrealdb")` returns |
| `UPSTREAM` | What was vendored, from where, the repin steps, and what was changed |
| `BUILD-PROOF` | The compiler that validated this content, and the digest of that content |

A session reaches SurrealDB over a WebSocket through a platform adapter from
[roc-websocket](../roc-websocket/README.md) (`roc-basic-cli-websocket` and
`roc-basic-webserver-websocket`); that plugin documents the adapters.

The package is UPL-1.0, and so is this plugin. [`LICENSE`](LICENSE) is upstream's
file.
