# @roc-syntax/cloudflare-workers

A [roc-syntax-mcp](https://github.com/Karakatiza666/roc-syntax-mcp) plugin: the
corpus of [roc-cloudflare-workers](https://github.com/Karakatiza666/roc-cloudflare-workers),
a Roc platform for Cloudflare Workers. A model that writes a Worker in Roc reads
the platform that it compiles against, and does not recall one.

No JavaScript runs from this package. It is Roc source, prose and a manifest.

## Status

The plugin documents release 0.0.1 of the platform
([tag](https://github.com/Karakatiza666/roc-cloudflare-workers/releases/tag/0.0.1)),
and it is checked with nightly-2026-10-19-601b54c. The helper `roc-cfw` is not
released, so the overview gives the manual project setup.

## Install

```bash
roc-syntax-mcp plugin add @roc-syntax/cloudflare-workers
```

## What it serves

| Part | Is |
|---|---|
| `overview.md` | What `get_roc_syntax(scope: "cloudflare-workers")` returns: the project files (the Talon setup, no npm), the `event!` contract, the core modules and the traps |
| `index.json` | The modules of the bundle, parsed by `plugin index`. No source is vendored |
| `examples/` | The `examples/hello` apps of the platform repo, with the platform line changed to the release URL |
| `topics/` | Programs that `get_roc_syntax(topic:)` answers with, one for each area that a model gets wrong |
| `verify/` | One app with each snippet of the overview |
| `scaffold.roc` | The app that `roc_check` wraps bare source in |
