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
`c1e6af27a29303f2e409b037aa1d4a32ebd68217`, the commit of the package's
`.roc-version`. Build it with Zig 0.17.0, as the package's README says, and
point this server at the build:

```bash
git clone https://github.com/Karakatiza666/roc.git && cd roc
git checkout c1e6af27a29303f2e409b037aa1d4a32ebd68217
zig build roc
roc-syntax-mcp roc use $PWD/zig-out/bin/roc
```

A stock nightly rejects the package's programs with "missing method" errors,
and none of them mentions `Code`.

The plugin was validated with a debug build of that commit.
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
