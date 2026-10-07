# @roc-syntax/joy

A [roc-syntax-mcp](https://github.com/Karakatiza666/roc-syntax-mcp) plugin: the
corpus of the [Joy](https://github.com/niclas-ahden/joy) platform and of
[joy-html](https://github.com/niclas-ahden/joy-html), the package its
views are written in. A model that writes a Joy app reads the platform and the
HTML types that the app compiles against, and does not recall them.

No JavaScript runs from this package. It is Roc source, prose and a manifest.

## Install

```bash
roc-syntax-mcp plugin add @roc-syntax/joy
```

Then restart your AI harness. The server serves the plugin in every workspace.
To serve it from one client entry only, start the server with
`--plugin=@roc-syntax/joy`, or set `ROC_MCP_PLUGINS=@roc-syntax/joy`.

When the server detects an app header that pins a joy release, it adds the
`joy` scope to the default working set. Before there is a header, `roc_overview` lists joy as
"web apps in the browser" beside the bundled platforms. joy-html is a
documented package: an app that pins it gets its signatures, and any platform's
app can pin it.

## What it serves

| Part | Is |
|---|---|
| `joy-overview.md` | What `roc_overview scope="joy"` returns: how a project is started and built, the app contract, effects and subscriptions, HTTP, time, ports, testing and the traps |
| `html-overview.md` | What `search_roc_syntax("joy-html")` returns: element shapes, attributes, events, lazy regions and server rendering |
| `index.json` | Both releases' own modules, parsed by `plugin index`. No source is vendored |
| `examples/` | Complete programs from joy, all of which type-check |
| `topics/` | Programs `search_roc_syntax` answers with: `joy_app`, `joy_http`, `joy_subscriptions`, `html_views`, `html_ssr` |
| `scaffold.roc` | The app `roc_check` wraps bare source in, with joy-html imported |

## Pinned to

The two releases in `plugin.json`, and the nightly its `compiler` line names.
`UPSTREAM` records the commits, the tarball hashes and the upstream files that
this package does not include.

## License

Apache-2.0, as both upstream repositories are. `LICENSE` is an exact copy of
upstream's. The manifest, the overview pages and the topic files are this
package's own, under the same license.

Changed files, as Apache-2.0 section 4(b) asks: every file in `examples/` is
joy's, with one line changed. Upstream's platform pin is a relative path to the
platform in joy's own repository. This copy pins the release URL. `UPSTREAM`
records the commit that the files came from.
