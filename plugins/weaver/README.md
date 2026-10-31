# @roc-syntax/weaver

The [Weaver](https://github.com/lukewilliamboswell/weaver) command-line argument
parser, as a corpus [roc-syntax-mcp](https://github.com/Karakatiza666/roc-syntax-mcp)
can serve: the package's public modules, its worked examples, topic programs
written against the release, and an overview page on which every claim was
compiled.

Weaver is a package rather than a platform, so this plugin adds no scope. It
serves the `lukewilliamboswell/weaver` namespace. When an app's header pins
weaver, a search covers weaver's names together with the builtins. The page,
topics and examples answer even before any app pins weaver.

```bash
roc-syntax-mcp plugin add @roc-syntax/weaver
```

Then `get_roc_syntax(topic: "weaver")` for the page, `get_roc_syntax(topic: "weaver_cli")`
for a complete program, `search_symbols Opt.flag` for one signature.

| Path | Is |
|---|---|
| `index.json` | The release's own modules, parsed by `plugin index`. No source is vendored |
| `examples/` | Upstream's examples, repinned to the release tarball and moved onto the basic-cli this server bundles |
| `topics/` | Five programs written for this corpus, answerable by name |
| `verify/` | Every snippet the overview shows, compiled as one app |
| `overview.md` | What `get_roc_syntax(topic: "weaver")` returns |
| `UPSTREAM` | What was vendored, from where, and what was changed |

Weaver is UPL-1.0 from 0.9.1, and so is this package. [`LICENSE`](LICENSE) says
whose copyright each file carries.

Checked with `roc-syntax-mcp plugin validate .` against the nightly the
`compiler` line in `plugin.json` names.
