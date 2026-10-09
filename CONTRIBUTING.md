# Contributing

This file is for work on the server itself. To install and use the server, see
[`README.md`](README.md).

## Contribution license

Each commit needs this line in its message, on a line of its own:

```
Contribution-License: UPL-1.0 (CLA.md v1)
```

With this line, you keep the copyright of your code, and you let everyone use
it. The maintainer may also license it as part of the project. The full terms
are in [`CLA.md`](CLA.md).

Before you open a pull request, run `scripts/sign-branch.sh`. It adds the line
to each commit on your branch that does not have it.

## Repository layout

| Path | Is |
|---|---|
| `src/`, `bin/`, `scripts/`, `corpus/`, `docs/` | The server, the corpora it bundles, and its design notes. One npm package, the one the README is about |
| `corpus/language/` | The language and builtin scopes: `Builtin.roc`, `topics/`, `overview/` and `langref/`. The server does not serve `langref/`. The topics carry its ideas, and `langref-map.txt` names the topics that carry each section |
| `corpus/platforms/` | One directory per bundled platform: `plugin.json`, `UPSTREAM`, the release's examples, and `index.json` |
| `corpus/packages/` | One directory per bundled package: `plugin.json`, `UPSTREAM`, `index.json`, and for roc-parser and roc-random an `overview.md`, `topics/` and `verify/`. roc-parser also has the release's `examples/` and the `patches/` that repin them |
| `index.json` | The parsed signatures of the release a manifest names, written by `npm run build:index`. No release is vendored as source |
| `plugins/` | Child packages: corpora published separately, each with its own version. They are not in the server's published tarball. An install of the root package does not build them, and the server loads one only when it is declared. [`plugins/README.md`](plugins/README.md) |
| `docs/design/` | The design of the server. [`packaging.md`](docs/design/packaging.md), [`plugins.md`](docs/design/plugins.md), [`symbol-search.md`](docs/design/symbol-search.md) |

## From a clone

```bash
npm install
npm run build:ts
```

The build script is `build:ts` and not `build`. Read the reason before you
rename it. If the manifest of a git dependency declares `workspaces` or a
script named `build`, npm builds the dependency before it installs it. When
install scripts are blocked, that build leaves a link to a temporary clone, and
npm then deletes the clone. `src/package.test.ts` quotes this npm rule and
checks the manifest against it.
[`docs/design/packaging.md`](docs/design/packaging.md) gives measurements for
each install layout and explains why the package runs with no build step.

## The gates

```bash
npm test                          # the suite; no compiler needed
ROC=/path/to/roc npm run check:index       # every index.json matches its release
ROC=/path/to/roc npm run check:roc         # examples/ against a real compiler
ROC=/path/to/roc npm run check:platforms   # every bundled platform and package program
ROC=/path/to/roc npm run check             # every gate, in one go
```

A gate is one of these named check scripts. `npm run check` runs all of them
and does not stop at the first failure. When no compiler is on `PATH`, it
reports a check as skipped, not as passed. No install hook runs `npm run check`,
for two reasons. Most machines that install this server have no Roc toolchain,
and installers do not run the hook by default.

`check:roc` covers `corpus/language/examples/all_roc_syntax.roc` and the
language topic files under `corpus/language/topics/`. Topic files are
fragments, so `scripts/check-topics.roc` appends a minimal `main!` to each one,
and runs `roc check` and `roc test` on it. A topic states that some code is an
error or a warning with a `# @rejects <title>` or `# @warns <title>` comment
block, and the script compiles that block and checks the title. This check
found three errors that hand review did not find. Two of them are examples
from upstream's own langref that do not compile (see the notes in `numbers.roc`
and `app_header.roc`).

`roc fmt` truncates a module that contains only comments to zero lines. For
this reason, `app_header.roc`, `imports.roc`, and `platforms.roc` are not
formatted. All other topic files pass `roc fmt` with no change.

## Refreshing from upstream

The bundled language content tracks the commit recorded in
[`corpus/language/UPSTREAM`](corpus/language/UPSTREAM). To find what changed,
diff against that commit. Do not guess.

The platform and package corpora come from separate upstreams, each with its
own release schedule. Each one records its source in an `UPSTREAM` file:

| `UPSTREAM` file | Corpus |
|---|---|
| [`corpus/platforms/basic-webserver/UPSTREAM`](corpus/platforms/basic-webserver/UPSTREAM) | The basic-webserver platform |
| [`corpus/platforms/basic-cli/UPSTREAM`](corpus/platforms/basic-cli/UPSTREAM) | The basic-cli platform |
| [`corpus/packages/http/UPSTREAM`](corpus/packages/http/UPSTREAM) | The package that both platforms re-export |
| [`corpus/packages/roc-parser/UPSTREAM`](corpus/packages/roc-parser/UPSTREAM) | The multi-format parser that the `scripting` topic pins |

Each of these files names the compiler nightly that its gates ran under.
Refresh all of them together. Each bundled app pins its platform by tarball
URL, so `check:platforms` measures the nightly and the releases as one set.
You cannot validate one of them while another one changes.

Sometimes a release does not build on the pinned nightly, and upstream has a
fix that it has not released. Such a release can get an entry in
[`scripts/gate-overrides.json`](scripts/gate-overrides.json). When a file fails
against the release, `check:platforms` compiles it again against a patched copy
of the release, and counts each such file in its summary. The corpus continues
to pin the real release. Remove the entry when upstream releases the fix. A
test fails while an entry names a release that no corpus file pins.
`.claude/skills/refresh-roc-upstream/` has the full procedure.

Three trees come directly from upstream:

```bash
ROC=https://raw.githubusercontent.com/roc-lang/roc/main

curl -fsSL $ROC/test/echo/all_syntax_test.roc -o corpus/language/examples/all_roc_syntax.roc
curl -fsSL $ROC/src/build/roc/Builtin.roc     -o corpus/language/Builtin.roc

# The language reference is a directory, so clone it. Before the copy, list
# the sections that changed since the pinned commit, and the topics that carry them.
git clone --depth 1 https://github.com/roc-lang/roc /tmp/roc
roc scripts/langref-diff.roc -- /tmp/roc > /tmp/langref-diff.md
cp /tmp/roc/docs/langref/*.md corpus/language/langref/
```

Work through `/tmp/langref-diff.md`. For each section, update the topics that it
names, and add, remove or rename the line of the section in
`corpus/language/langref-map.txt`.

Then write the new commit into `corpus/language/UPSTREAM` and run `npm test`.
The suite tests the `Builtin.roc` parser against known record-field leaks and
against builtins that upstream deleted. Thus a refresh that breaks the index
fails the suite. The suite also asserts that every key in
[`src/builtin_hints.ts`](src/builtin_hints.ts) names a real builtin. Thus an
upstream rename fails the suite, and no hint disappears without a failure.

### Curated content and its checks

| Tree | Is | Checked by |
|---|---|---|
| `corpus/language/topics/` | Hand-curated snippets, one file per topic. They carry every non-trivial idea of `corpus/language/langref/` | `check:roc` compiles and tests each topic and checks its `@rejects` and `@warns` claims |
| `corpus/language/langref-map.txt` | One line per langref section: the topics that carry its ideas, or `skip: <reason>` | `npm test` and `check:roc` fail when a section has no line, or a line names no section or no language topic |
| `corpus/language/overview/` | The first page that a client reads, so a stale page here does the most harm | `src/overview.test.ts`. It checks that the builtins page quotes no counts, that every builtin the pages name exists, and that both pages stay in a token budget |
| `src/builtin_hints.ts` | One-line hints for builtins whose name and signature mislead. Each hint comes from the docstring of that builtin or from `corpus/language/langref/` | `npm test` asserts that every key names a real builtin |

The hints appear only in the `get_roc_module` signature list, so upstream's
docstrings stay unchanged in `search_symbols` and `detail: "full"`.

Read the prose in `corpus/language/overview/` again on every refresh. The
constructs in `language.md` were verified in one file with `roc check`. Repeat
that check after a syntax change.
`.claude/skills/refresh-roc-upstream/reference/derived-content.md` has the
rules and the check that enforces each one.

## The MCP SDK

The server uses
[`@modelcontextprotocol/server`](https://www.npmjs.com/package/@modelcontextprotocol/server)
v2, the package that replaced the monolithic `@modelcontextprotocol/sdk`. This
package needs Node 20 or newer, and Zod 4. A tool schema written with Zod 3
compiles with no error. At runtime, `tools/list` then sends a schema with no
properties, and the server accepts a bad argument. Thus
`src/resources.test.ts` asserts that the schemas arrive complete in
`tools/list` and that the server rejects an invalid argument.

Tool schemas use the v2 form, `inputSchema: z.object({ ... })`. The v1
raw-shape form (`inputSchema: { field: z.string() }`) also works, through a
deprecated overload that wraps it automatically. Because of this overload, a
v1 schema gives no error when it fails. Use the explicit wrap.

The server uses only stdio, so some v2 features are not available to it. The
SDK serves the 2026-07-28 protocol revision, and with it the `cacheHints`
option for cacheable results, only through the HTTP entry. Here,
`LATEST_PROTOCOL_VERSION` is `2025-11-25`. A test pins the server to this
version, so that the suite cannot test only the 2024-11-05 protocol without a
failure.

## Size of the tool list

Every tool advertises `readOnlyHint: true` and `openWorldHint: false`. No tool
changes user data. The tools read bundled reference files, and `roc_check` and
`roc_fmt` run the compiler over a scratch copy in a temporary directory.
Clients read `readOnlyHint` to decide whether a call needs an approval prompt.
The hints cost a few tokens per tool, and the user gets lookups with no
prompts. `destructiveHint` and `idempotentHint` have a meaning only when
`readOnlyHint` is false, so the tools do not declare them.
`src/resources.test.ts` asserts that every tool has both hints and that the
whole list stays under its size ceiling.

No tool declares an `outputSchema`, and every tool returns text. When a reply
has both `structuredContent` and `content` text, Claude Code gives the model
the `structuredContent` and drops the text. With output schemas, the model did
not get the scope footers, the detection note, or the markdown formatting.
Without the schemas, `tools/list` is 2,569 tokens, and with them it was 3,968.

## Evaluating the tool surface

The test suite checks that the server answers correctly. It cannot tell you if
a model calls the right tool, sets `scope`, or writes Roc that compiles.
`scripts/eval-agentic.mjs` runs a real `claude -p` session against a fixture
basic-webserver app and reads those results from the transcript.

```bash
ROC=/path/to/roc npm run eval:agentic -- --arm=<label>
npm run eval:agentic -- --report        # re-render from saved runs
```

The script appends each run to `docs/evals/runs.jsonl` and writes the report to
[`docs/evals/agentic.md`](docs/evals/agentic.md). The eval uses real model
tokens, so `npm test` does not run it. An arm is one labeled set of runs. Label
each arm with the design that it measures. To compare two designs, run the
eval, change the server, and run the eval again.

## Writing a plugin

A plugin is an ordinary npm package that contains no JavaScript. The plugin
tools are the server binary with a `plugin` argument. In this mode, the binary
does not speak JSON-RPC and does not connect to the network:

```bash
roc-syntax-mcp plugin init ./roc-ray       # a skeleton, ready to fill in
roc-syntax-mcp plugin init ./weaver --kind=package   # the other skeleton
roc-syntax-mcp plugin index ./roc-ray      # index.json, from the release plugin.json names
roc-syntax-mcp plugin validate ./roc-ray   # this server's own gates, on it
roc-syntax-mcp plugin inspect ./roc-ray    # what this host would index
roc-syntax-mcp plugin doctor               # the set a server here would load
```

`validate` does these steps in sequence:

1. It reads the manifest and indexes the corpus.
2. It checks that no declared path is outside the plugin.
3. It checks that the overview page stays under its token ceiling, and that
   every snippet on the page appears in an app that the gate compiles.
4. It measures what the plugin adds to each tool in `tools/list`, against the
   180-token allowance that all plugins share per tool.
5. It runs the compiler over every program that the plugin ships, and over the
   sample in its own scaffold.

Add `--offline` to stop before the two compiler gates. An operator uses
`doctor` to debug a plugin set.

The gates check only mechanical properties. A corpus is useful because of the
traps that its author found and wrote down, and no script can check that.
`.claude/skills/author-roc-plugin/` describes the method. Find the traps with a
compiler, not from what you recall about Roc. Then document each trap at the
place where a reader meets it. `list_roc_index(kind: "scopes")` names the
maintainer of every scope, or says "not named". This design lets anyone publish
a plugin, and the maintainer name tells the reader who is responsible for it.

[`plugins/README.md`](plugins/README.md) lists the rules for a child package.
[`docs/design/plugins.md`](docs/design/plugins.md) describes the full behavior.

## Try the packaged build

Try the changes as the tarballs that would be uploaded to npm:

```bash
scripts/try-tarball.sh                 # the server, and every plugin under plugins/
scripts/try-tarball.sh --claude joy    # one plugin, and a `roc-syntax` entry in Claude Code
scripts/try-tarball.sh --cleanup       # remove what it installed
```

The script packs each package in the same way as its publish workflow. Then it
removes every installed server and plugin, installs the server with
`npm install -g`, and installs the plugins with `plugin add`.

## Licensing a new file

[`REUSE.toml`](REUSE.toml) records the license of each path. No file carries a
license header, because most of the corpus must stay byte-identical to an
upstream release. A new top-level tree needs an entry in `REUSE.toml` and a
line in [`LICENSE`](LICENSE). If the server reads the tree at runtime, the tree
also needs a line in the `files` list in `package.json`. `files` is a
whitelist, and `src/package.test.ts` asserts both directions against
`npm pack --dry-run`.
