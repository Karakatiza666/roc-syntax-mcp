# Plan: add basic-webserver 0.16.0 as a second scope

## Status

| Phase | State |
|---|---|
| 0. Provenance and fixtures | Done. 28 of 28 bundled programs pass `roc check` |
| 1. Parser changes | Done. Types and the host tier are indexed, both guards validated by reverting them |
| 2. Corpus registry and scope plumbing | Done. 12 tools, no new ones |
| 3. Detection | Done. 3 of 3 fixtures pass against Claude Code CLI 2.1.241 |
| 4. Content | Done. 6 topics, 27 examples, 2 doc pages, all reachable |
| 5. `roc_check` scaffolding | Done. 8 of 8 acceptance cases pass against nightly db56022 |
| 6. Verification and docs | Done. 127 tests, 4 acceptance scripts, README Scopes section, and a basic-webserver track in the refresh skill |
| 7. Agentic evaluation | Done. See "Phase 7: agentic evaluation" |

Measurements during implementation corrected these figures:

| Claim | Planned | Measured |
|---|---|---|
| Types in `Builtin.roc` | 59 | 27, after excluding `[]`, `{}`, and `[ProvidedByCompiler]` namespaces |
| Host tier | 138 | 138 |
| Host items hidden by `get_builtin_module("Server")` | 24 | 20. The other 4 are under `Sse` |
| `tools/list` after the scope parameter | under 4000 | 3968, from 3612. Phase 4 added a topic set and an index kind, and Phase 5 added a `scope` on `roc_check`. A test asserts the figure, so nobody measures it by hand |
| basic-webserver public items | 429 | 427. `Html.HtmlNode` and `MultipartFormData.ParsedFormData` are declared outside their module block, so no app can name them. They form a third tier, `private` |
| Examples exposed through `search_roc_syntax` | planned | Exposed through `search` (an `example` hit kind), `list_roc_index(kind: "examples")`, and the resource template. `search_roc_syntax` returns exactly one topic and its whole file. The largest example is ~3.7k tokens, too large for a snippet |
| `roc_check` timeout raised when `scope != "builtin"` | planned | Raised when the header pins a remote package, because a download depends on that condition. The rule also covers `path` input, which carries no scope. Source with no package keeps the 30s ceiling, so a hung compiler still returns |
| `roc_check(code)` worked before Phase 5 | assumed | It did not. `roc check` deletes every `/tmp/roc-*` directory at startup, and the server wrote its scratch file into `/tmp/roc-check-XXXX`. Every `code` call got "file not found" for source written a moment earlier. The fix names the directory `mcp-roc-check-XXXX`. `roc version` and `roc fmt` do not delete these directories, so `roc_fmt` was unaffected |
| A non-zero exit with no diagnostic | not considered | The server reported it as `roc check` passed. Because of this, the first acceptance run showed four false passes. For a silent failure, the server says that it did not check the code, and quotes what the compiler wrote |
| The footer, the detection note, and the mismatch warning reached the model | assumed | They did not. When a reply has both `structuredContent` and `content`, Claude Code gives the model `structuredContent` and drops the `content` text, with or without an `outputSchema`. All twelve tools return text only. `tools/list` fell from 3,968 to 2,569 tokens, and tool output per task fell by 21%. Phase 7 found this |
| `tools/list` after the scope parameter, final | under 4000 | 2,569 after the output schemas were removed. The test asserts a ceiling of 2,800 |

## Decision

Serve basic-webserver from this server under a new exclusive `scope` parameter.
Do not build a second MCP server, and do not use runtime tool registration.

One server keeps the tool count at 12. A per-platform server would:

- duplicate about 8 of the 12 tools (+2.5k to 3k tokens on `tools/list`),
- duplicate the `instructions` block,
- add a config entry per user,
- give two tools named `lookup_builtin`, which the model must tell apart by
  server prefix.

Measurements show that too many tools is the main failure mode for agents. So
the scarce resource is the tool surface, not disk.

Runtime tool registration through `notifications/tools/list_changed` does not
work on enough clients:

- Claude Desktop ignores it (anthropics/claude-code#50339).
- VS Code updates its UI, but the agent cannot call new tools until the next
  turn (microsoft/vscode#303012).
- Gemini CLI and the Vercel AI SDK do not implement it.

So this server applies progressive disclosure to content, not to tools, as it
already does.

## Settled decisions

| Decision | Value | Why |
|---|---|---|
| Parameter name | `scope` | The parameter covers a language, a stdlib, a platform, and a package. "platform" is wrong for three of the four |
| Scope values | `language`, `builtin`, `basic-webserver` | Each value selects one corpus exclusively. `roc_overview` loses its `part` parameter |
| Semantics | Omitted means the default working set, passing one means only that one | Address spaces are disjoint and demand is asymmetric. See "Scope model" |
| `--scope=` flag | Sets the default only, never restricts | An explicit argument must always reach any corpus |
| Vendored source | `corpus/platforms/basic-webserver/` | The name says what it holds |
| Version | Pinned bundle at 0.16.0 | Matches the existing `UPSTREAM` practice and lets the server work offline |
| Mismatch | Warn once per root per 24h | The detected pin often differs. Every 0.16.0 example pins 0.15.0 |
| Detection | roots, then cwd, then walk up | Verified under Claude Code CLI |
| Detection cache | 24h TTL, 5 s when no app header was found, plus invalidate on `roots/list_changed` | The client declares `listChanged: true`. An agent with no app header writes one next |
| Examples | Bundle all 27 through a patch series, verified | Repinning needs a patch series anyway. All 27 then pass `roc check` |
| Host tier | Keep and index it, but not as a scope | Addressed lookups are already scope-free, so a scope value would add ~70 tokens and give only undirected search |
| `design.md` | Curate, do not bundle | 13.7k tokens of architecture prose for contributors, not app authors |

## Source study findings

Measured against tag `0.16.0` (commit `23bb50c`) with the bundled nightly
`db56022`. These findings shape the phases below.

| # | Finding | Consequence |
|---|---|---|
| 1 | `src/builtin_parser.ts` parses platform modules unmodified: 426 items across 25 files | No new parser, only extensions |
| 2 | The parser does not see type declarations. `Server.roc` has 21. `IOErr.roc` and `Method.roc` yield zero items | Parser change 1a, highest priority |
| 3 | `Method := [OPTIONS, GET, POST, ...]` uses uppercase tags | A model writes `Get` and fails. Needs a hint |
| 4 | `Host`, `Internal*`, `SplitList` are absent from `exposes`. 24 `to_host`/`from_host` glue methods are inside exposed modules | Visibility tier, parser change 1b |
| 5 | `Request`, `Response`, `Method`, `Header` come from roc-lang/http 1.0.0, not the platform | Bundle both under one scope |
| 6 | All 27 examples at tag 0.16.0 pin platform 0.15.0. Repinned to 0.16.0, they check clean (3 verified) | Bundle them repinned and verified, not unchanged |
| 7 | `gregorian` fails under nightly `db56022`: 14 errors in `Date.roc`, missing `range_exclusive_to` for `..<` | 6 examples affected. Patch 2 removes it, and all 27 then pass. The scaffold must avoid it |
| 8 | `roc check` on a repinned example: 14.7s cold (downloads 29MB), 38 to 56ms warm | Raise the scoped timeout or warm the cache |
| 9 | Zero `fullName` collisions and zero module-name collisions between corpora | Addressed lookups need no scope. True for one platform only. `docs/plans/basic-cli-scope.md` records what replaced it |
| 10 | 32 of 285 bare names collide (11%), mostly in the derived-method protocol | Scope only breaks ties on unqualified lookups |
| 11 | All 27 examples touch both corpora, but 21 touch exactly one builtin module (`Str`) | Demand is asymmetric, so exclusive scopes cost little |
| 12 | 17 distinct builtin calls across all 27 examples, led by `Str.inspect` (61x) and `Str.to_utf8` (51x) | The names a model needs to search for are on the platform side |

### Pins to record

```
platform  roc-lang/basic-webserver  0.16.0  commit 23bb50c
          42jC1JT3auhHSmv2Ah8mW5F2MXiAakq1UQQ4NQceQjXw.tar.zst
package   roc-lang/http             1.0.0
          6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst
compiler  nightly-2026-08-22-db56022  (identical to this repo's bundled nightly)
```

`main` is already past the tag (`03e3f3f`). Pin to the tag.

## Bundle inventory

| Content | Raw | Bundle |
|---|---|---|
| 19 exposed platform modules | ~67.1k tok | Yes, indexed and sliced |
| 6 internal modules (`Host`, `Internal*`, `SplitList`) | ~5.9k tok | Yes, host scope |
| `platform/main.roc` | ~2.2k tok | Yes, host scope. It is the platform header |
| http package, 4 modules | ~1.7k tok | Yes, folded into `basic-webserver` |
| 27 examples | ~23.8k tok | Yes, repinned to 0.16.0 |
| `docs/sse.md`, `docs/benchmarking.md` | ~4.0k tok | Yes, unchanged |
| `design.md` | ~13.7k tok | No. Curate lines 109 to 213 only |
| `README.md` | ~2.8k tok | No. This server's overview replaces it |

Apply the same rule as for `Builtin.roc`: bundle the source, but never serve it
whole.

### Item counts

Counts after Phase 1a makes type declarations indexable.

| Corpus | Values | Types | Total |
|---|---|---|---|
| `builtin` | 2185 | 27 | 2212 |
| `basic-webserver`, app-facing (19 exposed modules plus the http package) | 348 | 81 | 429 |
| Host tier (6 internal modules, plus 24 glue). Indexed, not a scope | 101 | 37 | 138 |

The `instructions` string said "2185 builtins". It must say 2212, the count that
the index holds.

## Scope model

`scope` names one corpus. There are three:

| Scope | Contents |
|---|---|
| `language` | `corpus/language/overview/language.md`, `corpus/language/langref/`, `all_roc_syntax.roc`, language topics |
| `builtin` | `Builtin.roc` index, `corpus/language/overview/builtins.md` |
| `basic-webserver` | 19 exposed platform modules, the http package, examples, platform topics, platform overview |

The host tier is indexed but is not a scope. See "The host tier".

A separate `language` scope removes the need for the `part` parameter on
`roc_overview`. One parameter covers what took two. The main case, "I know the
builtins, I need to write an endpoint", is one explicit
`scope: "basic-webserver"`.

### Omitted versus explicit

The rule:

| Call | Behaviour |
|---|---|
| `scope` omitted | The default working set: `language` + `builtin`, plus the detected platform |
| `scope` passed | That corpus only |

With `scope` omitted, every existing caller gets the same behaviour as before
this plan. A caller that passes `scope` narrows on purpose, so the model always
knows that it narrowed.

The alternative was an implicit exclusive default. With three scopes it is
worse. The model gets a narrowed result set with no signal, and each added scope
makes a wrong implicit pick more likely.

### Scope applies per tool class

| Class | Tools | Semantics |
|---|---|---|
| Addressed | `lookup_builtin`, `get_builtin_module` | Ignore scope. Resolve globally, report origin. Accept `scope` only as a tie-breaker for unqualified names. Replaced when a second platform arrived: they resolve over the active platform, per `docs/plans/basic-cli-scope.md` |
| Undirected | `search`, `search_builtin_signatures`, `search_roc_syntax` | Omitted means working set, passed means exclusive |
| Bulk | `roc_overview`, `list_roc_index` | Same, but an omitted scope costs many tokens, so the footer must tell the model that it can narrow |
| No scope parameter | `get_roc_langref`, `get_roc_syntax`, `roc_fmt`, `search_project_signatures` | Unchanged. The first two are `language` by definition |

Scope-free addressed lookups prevent the worst failure: the model holds the
right name, has the wrong scope set, and gets "not found" for a name that exists.
With zero `fullName` collisions, no name needs a tie-break.

### Accepted values per tool

Each tool declares only the scopes that mean something for it. Smaller enums
cost fewer tokens on `tools/list` and make an invalid value impossible.

| Tool | Accepts |
|---|---|
| `roc_overview` | all three |
| `list_roc_index` | all three |
| `search` | all three |
| `search_roc_syntax` | `language`, `basic-webserver` |
| `search_builtin_signatures` | `builtin`, `basic-webserver` |
| `roc_check` | `basic-webserver`. Omitted means no app header is scaffolded |
| `lookup_builtin`, `get_builtin_module` | all three, as a tie-breaker only. After basic-cli, a platform name, to reach the platform that the workspace does not pin |

### roc_overview is an exception

With `scope` omitted, `roc_overview` returns `language` + `builtin` (~3.1k
tokens), the same as the current first call. It must not add the platform page,
even when detection found a platform, because that causes the duplication this
design must avoid. The response ends with this pointer:

```
Platform detected: basic-webserver 0.16.0.
roc_overview(scope: "basic-webserver") adds ~1.5k tokens.
```

So a model that already knows the builtins calls
`roc_overview(scope: "basic-webserver")` once and pays 1.5k, not 4.6k.

### The host tier

The host tier is the ABI boundary, where the platform flattens Roc types into
shapes that a Rust host can write. Three signatures show why it is a different
corpus and not only a private one:

```roc
Host.sqlite_open! : RawPath, U64, U64, U64, U64, I64, I64 => Try(SqliteDb, SqliteError)
Server.Config.to_host : Config -> { ...55 flat fields... }
InternalServer.from_host_request : RequestFromHost -> Server.Request
```

The first takes seven positional primitives, not a record. The second returns a
55-field flat record, not the nested `Config` that an app author sees. The third
is a hand-written conversion between the two. An app author must never call any
of these. A platform author needs exactly these, and also the rules for them:

- closed `Try` unions at the FFI boundary,
- record field order, which matters,
- the discriminant byte of a single-variant tag.

`corpus/language/topics/platforms.roc` already teaches those rules from
basic-cli fragments quoted by hand. basic-webserver gives them a complete corpus
that type-checks.

The host tier is indexed and fully reachable, but it is not a scope. Addressed
lookups are scope-free, so `get_builtin_module("Host")` and
`lookup_builtin("Server.Config.to_host")` work with no new code. A scope value
would cost ~70 tokens across three enums. It would also be easy to confuse with
the platform scope, and it would give only undirected search across 138 items.
The footer tells a searcher that hidden host items exist, and a searcher needs
only that.

| Rejected alternative | Cost |
|---|---|
| A `tier: "app" \| "host"` parameter | ~90 tokens, and a second parameter for the model to reason about |
| No host tier | Loses the platform authors that `corpus/language/topics/platforms.roc` already serves |

### The footer rule

Every undirected and bulk response ends with the match count in the other
scopes. The footer lists only non-zero counts, and at most two:

```
6 matches in scope=basic-webserver.
(builtin: 3 other matches, language: 1. Retry with scope= to see them.)
```

For the host tier, the footer names the tier and not a scope, because there is
no scope to retry with:

```
24 host-boundary items hidden. Address them directly, for example
get_builtin_module("Host") or lookup_builtin("Server.Config.to_host").
```

The footer costs about 12 tokens, and without it a model has no reason to retry.
A footer only on empty results is not enough. The dangerous case is a plausible
hit in the wrong corpus, because the model stops there and never retries.

An exclusive scope saves no tokens on the search tools, because `limit`
(default 10) caps them in both cases. Scope changes which ten results come back,
not how many. All of the token saving is in the bulk tools.

### Defaults for the detected platform

| Situation | Working set |
|---|---|
| Explicit `scope` argument | That corpus alone, always wins |
| `--scope=` passed at config time | Adds that corpus to the working set |
| Detection finds a basic-webserver app header | Adds `basic-webserver` to the working set |
| Detection finds nothing, or fails | `language` + `builtin` |

## Detection

Resolution order, first hit wins: explicit argument, config-time `--scope=`,
workspace detection, `builtin`.

Workspace detection takes these steps:

1. Read `roots/list` (the SDK exposes `listRoots()`).
2. Fall back to `process.cwd()` and `CLAUDE_PROJECT_DIR`.
3. Walk up to the git root, and look for a `.roc` file with an
   `app [...] { pf: platform "..." }` header.

The walk up is necessary. A CLI started from `src/` reports `src/` as both cwd
and root, so without the walk, detection misses an app file at the repo root.

```
cache key    resolved root path
cache value  { scope, sourceFile, detectedVersion, detectedAt, warned }
TTL          24h, then re-walk. 5 s when no app header was found
invalidate   on notifications/roots/list_changed
```

Every scoped response states the outcome, for example
`scope=basic-webserver (detected from ./main.roc, pins 0.16.0)` or
`no platform detected, pass scope= explicitly`. A silent wrong default is worse
than no default.

### Mismatch messages

The server emits a mismatch message once per root per 24h, and appends it to the
first scoped response. Four cases give three messages.

If the detected pin equals the bundle, there is no message.

The detected pin is older. This is the common case, because every 0.16.0 example
pins 0.15.0:

```
Note: your app pins basic-webserver 0.15.0, this server bundles 0.16.0.
Anything added after 0.15.0 appears here but will not compile against your
pin. Verify with roc_check, or move the pin to 0.16.0.
```

The detected pin is newer, so the user tracks a later release or `main`:

```
Note: your app pins basic-webserver 0.17.0, this server bundles 0.16.0.
APIs added after 0.16.0 are missing here and existing signatures may have
changed. Treat this index as a lower bound and verify with roc_check.
```

The detected platform is a local path or an unrecognized URL. A platform author
who works inside their own checkout sees this message:

```
Note: your app points at a local or unrecognized platform
(../platform/main.roc). This server's basic-webserver index describes 0.16.0
and may not match it. Use search_project_signatures to index the platform in
your workspace instead.
```

The third message points to an existing tool that is correct for that situation.
That is better than suppressing the scope or guessing.

### Measured client behaviour

Measured with a temporary stdio server under Claude Code CLI 2.1.241:

| Signal | Result |
|---|---|
| `client_capabilities` | `{"roots":{"listChanged":true},"elicitation":{}}` |
| `roots/list` | the launch directory |
| `process.cwd()`, `CLAUDE_PROJECT_DIR` | the launch directory |

Detection fails in some of these modes. That is why the config flag is the
primary mechanism, and detection is a convenience:

| Mode | cwd | roots | Detection |
|---|---|---|---|
| Claude Code CLI | launch dir | yes | works |
| Claude Code desktop app | `$HOME` | not sent | fails (anthropics/claude-code#75266) |
| Claude Desktop | unreliable | unconfirmed | assume it fails |
| VS Code, Cursor | workspace folder | Cursor advertises roots | likely works |
| Remote HTTP | none | none | impossible |

This adds no new deployment constraint. `roc_check` and `roc_fmt` already run a
local `roc`, and `search_project_signatures` already reads the local
filesystem. So part of the tool surface already cannot work in a remote
deployment. `cwd` in `.mcp.json` is documented but ignored
(anthropics/claude-code#17565), so it cannot replace detection.

The config flag can also do something that detection cannot. The server sends
`instructions` during `initialize`, before any tool call and before the client
can answer `roots/list`. With a config flag, the server can state the active
scope in that block, which clients inject at connect time. That steers the model
more strongly than a parameter default that the model never sees.

---

## Phase 0: provenance and fixtures

- Add `corpus/platforms/basic-webserver/UPSTREAM`, which records the repo, tag,
  commit, both tarball hashes, the nightly, and every derived file.
- Vendor the upstream files unchanged into
  `corpus/platforms/basic-webserver/{platform,http,examples,docs}/`.
- Add a patch series on top of the unchanged vendored files. Then a refresh
  reapplies the patches to a new tag and reports conflicts, and loses no edit:

```
corpus/platforms/basic-webserver/patches/
  0001-repin-examples-to-0.16.0.patch   all 27 examples
  0002-drop-gregorian-timestamps.patch  6 examples, 2 hunks each
```

  Patch 1 is necessary, because every example at tag 0.16.0 pins platform
  0.15.0. Patch 2 then costs almost nothing. All six gregorian examples use
  gregorian in the same way, for one log timestamp:

```diff
-	gregorian: "https://cdn.jasperwoudenberg.com/roc-gregorian-v1.0.0-rc.2/...",
-import gregorian.Time
-	datetime = (Time.unix_epoch + UnixTime.now!().seconds_since_epoch()).iso8601()
+	datetime = UnixTime.now!().seconds_since_epoch().to_str()
```

- Store per-example provenance in the index: upstream path, patches applied,
  and `roc check` status.

Acceptance, measured and not projected: with both patches applied, 27 of 27
examples pass `roc check` under nightly `db56022`. A refresh script can diff one
tag against the next and reapply the series.

## Phase 1: parser changes

Both changes go in `src/builtin_parser.ts`, with tests in
`src/builtin_parser.test.ts`.

### 1a. Capture type declarations

The `declMatch` branch at `src/builtin_parser.ts:82` pushes a scope and discards
the declaration. Emit a `BuiltinItem` with `kind: "type"` that carries the
declaration body. Then lookups find `Server.Request`, `Server.Outcome`,
`Server.ShutdownReason`, `IOErr`, and `Method` with their variants.

Emit an item only when the declaration is exactly one level deeper than its
enclosing module (`indent === stack[top].indent + 1`). Without that rule, the
index gets 20 duplicate items, because local annotations inside function bodies
match the same pattern. `Shape : a` at `corpus/language/Builtin.roc:237` is the
clearest case. It appears five times inside `expect` blocks, and each would
become a duplicate type named `Encoding.Json.Shape`. Add this trap to
`.claude/skills/refresh-roc-upstream/reference/parser-traps.md`.

Acceptance:
- `lookup_builtin("Method")` returns all 11 variants, including the uppercase
  spelling.
- `IOErr` returns its 8 variants.
- `Builtin.roc` yields 2185 values and 27 types, with no duplicate `fullName`.
- The `instructions` string reads 2212, not 2185.

### 1b. Visibility tier

Mark each item `public` or `host` from two sources: the `exposes` list in
`platform/main.roc`, and a name rule for `to_host`, `from_host`, and
`*_for_host!`. Exclude `host` items from app-facing search and from
`get_builtin_module` output, but keep them addressable by name.

Acceptance:
- `search` for "respond" in `scope=basic-webserver` does not return
  `Server.Outcome.to_host`.
- `get_builtin_module("Server")` reports 20 hidden host-boundary items across
  its subtree.
- `lookup_builtin("Server.Config.to_host")` still resolves.

## Phase 2: corpus registry and scope plumbing

- Add `src/scopes.ts`: a registry that maps a scope name to its directories,
  pinned version, and package origins. Register `language` and `builtin` the
  same way, so they are not special cases.
- Add `scope` to the undirected and bulk tools, with the per-tool enums from
  "Accepted values per tool". Remove `part` from `roc_overview`.
- Add `kind: "scopes"` to `list_roc_index` as the entry point for discovery.
- Fold the http package into `basic-webserver`, and do not make it a fifth
  value. An app cannot use the platform without it, and its types appear in
  platform signatures. Tag each item with its origin, so that the output can
  show `Response.from_status (http 1.0.0)`.

Acceptance: `node .claude/skills/refresh-roc-upstream/scripts/tool-cost.mjs`
reports under 4000 tokens for 12 tools, up from 3612.

## Phase 3: detection

Implement the resolution order, cache, and footer described in "Detection".

Warn once on a version mismatch. When `detectedVersion` differs from the bundled
`0.16.0`, append one warning to the first scoped response and set
`warned: true`. Because of the 24h TTL, the warning repeats at most once a day.
The case is real, because every example in the 0.16.0 tag pins 0.15.0.

Acceptance uses Claude Code as the MCP client, not a custom harness.
`claude -p --mcp-config <file>` starts a stdio server, declares
`roots.listChanged: true`, and answers `roots/list` with the launch directory.
All three behaviours were verified against CLI 2.1.241.

1. Create a fixture directory that holds an app header that pins basic-webserver.
2. Run `claude -p "..." --mcp-config` from that directory.
3. Assert on what the server recorded about its own detection, not on model
   output.

The assertion is deterministic because it never reads the model's reply. A
second fixture, started from a subdirectory, proves the walk-up. A third fixture
with no app header proves the fallback to `language` + `builtin`.

## Phase 4: content

- `corpus/platforms/basic-webserver/overview.md`, which
  `roc_overview(scope: "basic-webserver")` returns. Budget ~1.5k tokens. The
  page must contain:
  - the application contract (`program = { init!, respond!, shutdown! }` with
    all three signatures),
  - the app header, including the `[Context : context] for program` clause,
  - `Server.Config` builder chaining,
  - the `Server.respond`, `stream`, `file_response`, and `stop_after` outcomes,
  - the uppercase `Method` tags.
- New scope-tagged topics under `corpus/language/topics/`: `webserver_handler`,
  `webserver_sqlite`, `webserver_sse`, `webserver_html`, `webserver_forms`,
  `webserver_static`.
- Expose examples through `search_roc_syntax` and a
  `roc-syntax://platform/basic-webserver/example/{name}` resource template.
  Resources cost nothing on `tools/list`.
- Curate `design.md` lines 109 to 213 into the overview. Leave the other 800
  lines out.
- Bundle `docs/sse.md` and `docs/benchmarking.md` unchanged.
- Extend `corpus/language/topics/platforms.roc` to cite basic-webserver. It is a
  better worked example than the basic-cli fragments that the topic quotes.

## Phase 5: roc_check scaffolding

- `roc_check(code, scope: "basic-webserver")` wraps a bare handler in a verified
  app header pinned to 0.16.0 plus http 1.0.0, with no `gregorian`.

  The app is `corpus/platforms/basic-webserver/scaffold.roc`, not TypeScript,
  so `scripts/check-platform-examples.sh` compiles it with the examples.
  Everything above its `@user-code` marker is the prelude. `roc_check` appends
  each `@default` block below the marker only when the submission does not
  declare that name. So a bare `respond!` gets `Context`, `program`, `init!` and
  `shutdown!`, and a submission with its own `Context` keeps it. The prelude
  imports all 19 exposed modules plus the four from http. An unused import gives
  no diagnostic, so a snippet that uses `Sqlite` compiles as submitted. The
  default `init!` builds its context with `crash`. `crash` has the bottom type,
  so it type-checks against any `Context` that the submission declares.

  The server shifts line numbers back by the prelude length and rewrites the
  temporary path to `main.roc`. So the caller reads positions in the source they
  wrote, with a filename that is not a deleted temporary directory.
- Separate compiler errors in the user's file from errors under
  `~/.cache/roc/packages/`. Report the user's errors first, and summarize
  dependency errors as a note. Without this, every project that uses gregorian
  shows 14 `Date.roc` errors that are not in the user's code, and the model
  tries to fix them.
- Raise the `roc check` timeout (`timeoutFor`, `src/roc_check.ts:388`) to 120s when `scope != "builtin"`, or
  warm the package cache once at first scoped use. The 14.7s cold path is
  acceptable. A 29MB download on a slow network is not.

## Phase 6: verification and docs

- Add `src/scopes.test.ts` and extend `src/resources.test.ts`. Cover the
  omitted-versus-explicit rule and the footer counts. Per repo
  convention, validate each new test by reverting the change it guards.
- Add a script that repins all 27 examples to 0.16.0, runs `roc check` on each,
  and fails the bundle if any example fails. This check matters most, because it
  proves that the bundled corpus matches the pinned release, not only that
  someone copied the corpus from that release.
- Extend `.claude/skills/refresh-roc-upstream/` with a basic-webserver track.
  Add the type-declaration and `to_host` traps to `reference/parser-traps.md`.
- README: a Scopes section, the `--scope` flag (default only, never a
  restriction), and the detection and fallback rules.

---

## Phase 7: agentic evaluation. Done

Unit tests cannot measure the three behaviours that this design depends on:

- whether the model sets `scope` correctly,
- whether the footer causes a retry,
- whether the model narrows when it should.

Anthropic's tool-writing guidance recommends agentic evals over unit tests for
tool surfaces. The harness is the same `claude -p --mcp-config` that Phase 3
uses.

`scripts/eval-agentic.mjs` runs four tasks against a fixture basic-webserver
project that already compiles. Each task edits `main.roc` in place, so
`roc check` on the result is a real end-to-end measurement. Three tasks need the
platform corpus (SQLite, SSE, forms). The fourth task needs only builtins, and
it detects a model that reads the platform corpus without a need for it. The run
denies `Bash` and the web tools, so the MCP server is the only source of Roc
knowledge. Every number comes from the transcript or from `roc check`.

The script does not switch arms (the server variants under comparison). To
compare two designs, run the script, change the server, and run it again with a
different `--arm` label. This keeps eval-only branches out of `src/`. Results
accumulate in `docs/evals/runs.jsonl`, and the script renders them to
`docs/evals/agentic.md`.

The plan called for a comparison before and after Phase 2. Phase 2 had shipped
before this run, so the arms are `baseline` (the surface after Phase 6) and
`text-only` (the fix that the baseline run found, described below).

| | baseline | text-only |
|---|---|---|
| `tools/list` | 3,968 tok | 2,569 tok |
| Tool output returned to the model | 107,902 ch | 85,157 ch |
| Emitted Roc passes `roc check` | 4/4 | 4/4 |
| Called `roc_check` before finishing | 4/4 | 4/4 |
| Scope footers the model saw | 0 | 0 |
| Host-tier footers seen, and followed | 0 | 1, followed 1 |

### What the run found

`structuredContent` hid every advisory note from the model. Claude Code 2.1.241
gives the model a tool's `structuredContent` and drops the `content` text when
both are present. It does this with or without an `outputSchema`. The text holds
every scope footer, the host-tier footer, the version-mismatch note, the
detection line in `list_roc_index(kind: "scopes")`, and all the markdown
formatting. None of it had ever reached a model. The schemas cost 1,345 tokens
of `tools/list`, 34% of the surface, and gave nothing for it. JSON escaping also
made every response larger: by 2% on a long markdown page, and by an order of
magnitude on a short one. The reply `` `roc check` passed. `` costs 19
characters as text and 232 in a schema.

All twelve tools return text only. That is the `text-only` arm. It cuts the tool
list by 35% and the tool output per task by 21%. The advisory notes reach the
model for the first time, and the only end-to-end measurement stays at 4/4. A
test asserts that no tool adds either field back.

The model calls `roc_overview` first in 8 runs out of 8, as its description
asks. On a platform task, the model then follows the pointer to
`roc_overview(scope: "basic-webserver")` in 5 of 6 runs. The design works as
intended here, and the overviews cost ~5.2k tokens per platform task.

The model called `roc_check` before it finished in 8 runs out of 8. Every run
that got an error called it again until the code passed. The `builtin-only` task
took two rounds.

The model passes `scope` to `roc_overview` and almost nothing else. Of the 6
scoped calls across both arms, 5 were `roc_overview` and 1 was
`search_builtin_signatures`. The model called `search_roc_syntax`,
`get_builtin_module`, and `lookup_builtin` without a scope every time. So the
working-set default does the narrowing, not the parameter.

### The two deferred decisions

The footer rule: keep it, but do not depend on it. Across 8 runs the model never
saw a scope footer. The footer appears on `search`, `search_builtin_signatures`,
the `list_roc_index` kinds, and a `search_roc_syntax` miss, and the model got no
hit from any of those calls. The footer costs nothing when it does not appear,
and it is not in `tools/list`, so its removal saves no tokens. The working-set
default does the narrowing.

The host tier needs no scope. Its footer appears on `get_builtin_module` as well
as on `search`, so it reached the model, but the scope footer did not. After the
one host-tier footer, the next call was an addressed `lookup_builtin`. That is
the behaviour the tier was designed for. One observation is not proof. But it is
the only evidence, and it supports not spending the ~70 tokens.

### What the eval cannot measure

Cost per task changed little ($1.87 to $1.79 across the four tasks). Most tokens
in a Claude Code session go to reading its own context again, not to what this
server returns. This server controls only the tool surface, and the table above
measures that surface directly. The dollar figure is not sensitive to it.

The eval used four tasks, one run each, and one model. That is enough to find a
channel that the model never read, and to answer two design questions that had
no evidence before. It is not enough to rank two surfaces that differ by a few
percent.

## Risks

| Risk | Mitigation |
|---|---|
| A model sets a scope early and never changes it | The footer on every undirected response, scope-free addressed lookups, and detection, which usually picks correctly |
| The app header shape is changing upstream. `main` adds a `roc:` pin field that 0.16.0 examples do not have | Verify the scaffold against the pinned release only. Verify it again on every refresh |
| Third-party packages break under the pinned nightly, as `gregorian` does | `roc_check` separates dependency errors. Never put a third-party package in the scaffold |
| The bundled 0.16.0 becomes stale, because the platform changes fast | The mismatch warning, once per root, plus the basic-webserver track in the refresh skill |
| Type items make the `builtin` index larger and change ranking | Count and rank `kind: "value"` first. Guard the 2185 figure with a test |

## Open questions

No question blocks the plan. All earlier questions have answers:

| Question | Resolution |
|---|---|
| Builtin count | 2212 (2185 values, 27 types) |
| Directory name | `platforms/` |
| `--scope=` semantics | Sets the default, never restricts |
| `language` as a scope | Yes, and `part` is removed |
| Mismatch messages | Three, written above |
| The 6 gregorian examples | Patch 2 removes the dependency. All 27 pass `roc check` |
| Host tier as a scope | No. Indexed and addressable, excluded from app-facing search |
| Phase 3 test harness | `claude -p --mcp-config`, no custom client needed |

Phase 7 answers both decisions that the plan deferred to it: keep the footer
rule, and keep the host tier addressed, not searchable.
