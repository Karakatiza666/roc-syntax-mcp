# @roc-syntax/cloudflare-workers

A [roc-syntax-mcp](https://github.com/Karakatiza666/roc-syntax-mcp) plugin: the
corpus of [roc-cloudflare-workers](https://github.com/Karakatiza666/roc-cloudflare-workers),
a Roc platform for Cloudflare Workers. A model that writes a Worker in Roc reads
the platform that it compiles against, and does not recall one.

No JavaScript runs from this package. It is Roc source, prose and a manifest.

## Status

The plugin documents release 0.0.6 of the platform (see `UPSTREAM`). The plugin is checked with
nightly-2026-11-03-34bd006, the nightly of the 0.0.6 build. The overview gives
the project setup with Talon and the helper `roc-cfw` 0.0.1
([repository](https://github.com/Karakatiza666/roc-cloudflare-workers-cli)),
and the topic `cfw_testing` the test helper `startApp`.

Release 0.0.1 of the platform was documented by version 0.0.1 of this package
([tag](https://github.com/Karakatiza666/roc-cloudflare-workers/releases/tag/0.0.1)).
Releases 0.0.2 to 0.0.5 have no version of this package.

## Install

```bash
roc-syntax-mcp plugin add @roc-syntax/cloudflare-workers
```

## What it serves

| Part | Is |
|---|---|
| `overview.md` | What `get_roc_syntax(scope: "cloudflare-workers")` returns: the project steps (`tln` and `roc-cfw`, no npm), the `event!` contract, the core modules and the traps |
| `index.json` | The modules of the bundle, parsed by `plugin index`. No source is vendored |
| `examples/` | The `examples/hello` apps of the platform repo, with the platform line changed to the release URL |
| `topics/` | Programs that `get_roc_syntax(topic:)` answers with, one for each area that a model gets wrong |
| `verify/` | One app with each snippet of the overview |
| `scaffold.roc` | The app that `roc_check` wraps bare source in |
