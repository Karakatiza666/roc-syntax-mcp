# @roc-syntax/roc-ray

A [roc-syntax-mcp](https://github.com/Karakatiza666/roc-syntax-mcp) plugin: the
corpus of [RocRay](https://github.com/lukewilliamboswell/roc-ray), so that a
model that writes a RocRay app reads the platform that it compiles against, and
does not recall one.

No JavaScript runs from this package. It is Roc source, prose and a manifest.

## Install

```bash
roc-syntax-mcp plugin add @roc-syntax/roc-ray
```

Then restart your AI harness. The server serves the plugin in every workspace.
To serve it from one client entry only, start the server with
`--plugin=@roc-syntax/roc-ray`, or set `ROC_MCP_PLUGINS=@roc-syntax/roc-ray`.

When the server detects an app header that pins a roc-ray release, it adds the
scope to the default working set, and nobody has to name it. Before there is a
header, the server reads nothing here until a caller asks for it.
`roc_overview` lists roc-ray as "games, graphics and sound" beside the bundled
platforms and asks the caller to pick one. `scope: "roc-ray"` on any tool picks
it. A search for a topic name finds the topic, whether the scope is chosen or
not.

## What it serves

| Part | Is |
|---|---|
| `overview.md` | What `roc_overview` returns for the scope: how a project is started and run, the callback contract, the phase rules, the shape a game takes, where to start reading, and the traps |
| `index.json` | The release's own modules, parsed by `plugin index`. No source is vendored |
| `examples/` | Complete programs from the release, all of which type-check |
| `topics/` | Programs `search_roc_syntax` answers with: how a project is started and run, how a game is put together, and the places a model gets this platform wrong |
| `scaffold.roc` | The app `roc_check` wraps bare source in, so a snippet can be checked without a header |

## Pinned to

The release in `plugin.json`, and the nightly its `compiler` line names. That
nightly is the release's supported compiler, and every app here was checked
under it. `UPSTREAM` records the tarball hashes and the upstream files that
this package does not include.

The platform bundle's own header pins that nightly with a `roc:` entry, so any
other compiler reports a "roc version mismatch" warning on every app that pins
this release. Nothing in an app can silence it. Upstream's example headers pin
the same nightly, and this package removes that entry from every app it bundles.

## What it does not ship, by choice

The platform's header also pins `kili-ilo/roc-random`, and this package
ships none of it. The server vendors that release itself, at
`corpus/packages/roc-random/`, so `plugin doctor` reports the namespace as
served by roc-syntax-mcp. The platform's `Random` module re-exports the
package's API with full signatures, so an app usually writes
`Random.bounded_i32` and never names the package. An app that does pin it, to
pass its `State` or `Generator` across the platform API, must pin the release
the platform pins.

The header also pins `roc-lang/http`. App code does use that package: an
app that builds a `Request` or reads a `Response` must pin the same release in
its own header, or `Request.from_method` "does not exist".
`topics/ray_tasks.roc` shows the shape.

## Checking it

```bash
npx roc-syntax-mcp plugin validate .
```

Set `ROC` to a Roc nightly first. If you do not, the two checks that need a
compiler report `skip`, and nothing is compiled.

## Licensing

`examples/` and the signatures and docstrings in `index.json` are RocRay's own,
copyright Luke Boswell and subsequent authors, under the Universal Permissive
License 1.0. `LICENSE` is an exact copy of upstream's. The manifest, the overview page
and the topic files are this package's own, under the same license.
