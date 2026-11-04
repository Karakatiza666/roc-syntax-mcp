# @roc-syntax/roc-websocket

The [roc-websocket](https://github.com/Karakatiza666/roc-websocket) WebSocket
package (RFC 6455), as a corpus
[roc-syntax-mcp](https://github.com/Karakatiza666/roc-syntax-mcp) can serve: the
package's public modules, its worked example, topic programs written against the
release, and an overview page on which every claim was compiled.

roc-websocket is a package rather than a platform, so this plugin adds no scope.
It serves the `Karakatiza666/roc-websocket` namespace. When an app's header pins
the package, a search covers its names together with the builtins. The page,
topics and example answer even before any app pins it.

```bash
roc-syntax-mcp plugin add @roc-syntax/roc-websocket
```

Then `get_roc_syntax(topic: "roc-websocket")` for the page,
`get_roc_syntax(topic: "ws_client")` for a complete client program,
`search_symbols Client.open!` for one signature.

| Path | Is |
|---|---|
| `index.json` | The release's own modules, parsed by `plugin index`. No source is vendored |
| `examples/` | Upstream's two examples (`sans_io`, `echo_server`), repinned to the release tarball |
| `topics/` | Four programs written for this corpus, answerable by name |
| `verify/` | Every snippet the overview shows, compiled as one app |
| `overview.md` | What `get_roc_syntax(topic: "roc-websocket")` returns |
| `UPSTREAM` | What was vendored, from where, and what was changed |

The package does no I/O. A platform adapter, a separate package, supplies it:
`roc-basic-cli-websocket` (client and server for basic-cli 0.26.0),
`roc-basic-webserver-websocket` (a client for basic-webserver 0.20.0, which
cannot answer an upgrade) and
`roc-cloudflare-workers-websocket` (client and server for cloudflare-workers).
The overview has the table with their release URLs.

The package is UPL-1.0, and so is this plugin. [`LICENSE`](LICENSE) is upstream's
file.

Checked with `roc-syntax-mcp plugin validate .` against the nightly the
`compiler` line in `plugin.json` names. The topics pin basic-cli 0.26.0, the
platform this server bundles.
