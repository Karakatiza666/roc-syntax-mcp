# Plan: third-party platform and package plugins

`docs/design/plugins.md` describes the behavior that these phases build: what a
plugin is, which provider answers a name, and what a caller sees when two
plugins disagree. This page gives the build order, the code that changes, and
the gates that check it.

## Verdict

Plugins are practical, because of a design decision that is already made. An
address space holds at most one platform, so two platforms never have to agree
about `Path.read_utf8!`. Plugins inherit that rule, so two plugins never have to
agree about the platform API.

Plugins add a second source of collisions that the current design did not have:
packages. `roc-lang/http` can come from the host, from a platform that vendors
its own copy, and from a package plugin. That needs a rule, and the rule needs a
namespace to attach to.

## Phases

| Phase | Scope |
|---|---|
| 0. Token budget | Done. The configured platform filters the topic enumeration. The ceiling is a baseline for the shipped configuration plus a budget per plugin |
| 1. Namespaces, in-repo only | Done. `ns` on every item, package pins read from each platform header, the boundary-crossing rule, host http moved off its special case. Behavior unchanged |
| 2. Manifest and loader | Done. `fromManifest()`, built-in scopes built through it, `ScopeName` becomes a string, explicit wiring, and one shared "it lives elsewhere" message across the eight sites that build one |
| 3. Package detection | Done. Detection reads the app header's package pins next to its platform, and both decide the space |
| 4. Developer tooling | Done. `plugin init` / `validate` / `inspect` / `doctor`, one binary, and the repo's own gates accept a plugin directory |
| 5. Authoring skill | Done. `.claude/skills/author-roc-plugin/`, the listing names who answers for each scope, and `force` is wired to its configuration |

The most important ordering decision is phase 1 before phase 2. Get namespaces
right against the two corpora that this repo compiles and tests, before any
foreign corpus loads. In each phase from 1 to 3, the host's own scopes run the
plugin code path, so that code cannot break unnoticed before a plugin exists.

## Phase 0: the token budget (done)

Measured, not estimated.

| Item | Tokens |
|---|---|
| `tools/list` before this phase | 2698 against the 2800 ceiling in `src/resources.test.ts` |
| Headroom | 102 |
| A scope name across 5 tool schemas | ~21 |
| All 44 topic names in `search_roc_syntax`'s description | 149 |
| Of those, the 31 language topics | 98 |
| basic-webserver's 6, basic-cli's 7 | 29 and 22 |

Two more platforms broke the ceiling, so the budget had to change before plugins
could use it.

### Keep the enumeration, filter it

The first answer was to drop the topic names entirely. That frees 149 tokens,
and `list_roc_index(kind: "topics")` already returns the same list filtered by
scope, so a model can still fetch every name. But the trade was wrong. It buys
headroom by removing the one place in `tools/list` where a model learns that
these topics exist. The only other pointers are `roc_overview` and the
`instructions` block.

The defect was that the list was not filtered. The description spelled out
`Object.keys(TOPICS)`, all 44, so a workspace on basic-cli paid 29 tokens for
basic-webserver topic names that no call in that workspace can use. Only one
platform is ever active, and the enumeration was the one part of the design that
did not apply that rule.

`enumeratedTopics()` in `src/server.ts:446` filters by `CONFIGURED_PLATFORM`. The
list is static, so it needs no `tools/list_changed`, and the topics of other
platforms add no tokens.

| Configuration | `tools/list` | Topics named |
|---|---|---|
| Before | 2698 | 44 |
| No `--scope` | 2666 | 31 |
| `--scope=basic-cli` | 2669 | 38 |
| `--scope=basic-webserver` | 2676 | 37 |

Filtering by the detected platform is not possible here. The SDK exposes
`update()` on a registered tool, so descriptions can change during a session.
But detection is async and runs on the first tool call, and by then the client
already holds the tool list. The configuration is known before `initialize`, but
the detection result is not.

Filtering is safe because the enumeration is only a hint and does not restrict
access. A model that needs another platform's topics still reaches them by
keyword or with an explicit `scope`.

### Two token limits

When users can install corpora, a single fixed number has no meaning. Two limits
replace it:

| Limit | Applies to |
|---|---|
| 2800 tokens | The shipped configuration, with no plugins. The existing test, unchanged |
| 60 tokens per plugin | Asserted by `plugin validate`, so one plugin with 40 topics cannot inflate every install |

### Tests

Three tests in `src/resources.test.ts`, each validated by reverting the behavior
it guards:

| Test | Fails when |
|---|---|
| The enumeration names no platform when none is configured | The filter is removed |
| A configured platform is enumerated and the others still are not | The filter is removed, or the pointer is emitted unconditionally |
| The enumeration names exactly the topics `list_roc_index` offers | The two lists drift apart |

`rpc()` takes a `serverArgs` parameter, so a test can start the server under
`--scope=basic-cli`. A fourth test compared filtered and unfiltered token
counts, and it was discarded. It derived its baseline from the two numbers that
it compared, so it would pass for any input.

### What still grows

Only the scope names grow, at ~21 tokens per platform across five tool schemas.
With topics filtered, the headroom covers about six more platforms. After that,
`scope` becomes a `z.string()` that points at `list_roc_index(kind: "scopes")`,
and its cost is O(1). The price is that the model does not see valid scope names
in `tools/list`. `eval:agentic` can measure whether that costs accuracy. That
measurement is not necessary until the twelfth platform.

Do not add a third tool for topics. `list_roc_index(kind: "topics")` already
does that job, and a new tool would spend about 200 tokens of schema to
duplicate it.

## Phase 1: namespaces, in-repo only (done)

This phase adds no manifest, no loader, and no foreign directory. The namespace
model went in against basic-cli, basic-webserver and the vendored http package,
where the tests and 78 compiled programs already check it.

Nothing that a caller can see changed. A fingerprint of every address space, by
scope, origin, `fullName`, tier and signature, matched the registry from before
the migration:

| Address space | Items | Result |
|---|---|---|
| No platform | 2458 | Identical |
| basic-cli | 2980 | Identical |
| basic-webserver | 3868 | Identical |

That is why this phase came first: the new resolution code runs under corpora
whose every item is already asserted.

| Work | Where |
|---|---|
| `ns` on every indexed item, from the directory it was read out of | `ScopedItem.ns`, `indexModuleDir` |
| Package types: a dependency, a provider, a resolution, a refusal | `src/scopes.ts` |
| `HTTP_PACKAGE` deleted. The vendored copy is a tier 3 provider | `HOST_PACKAGES` |
| Dependencies read from the platform header, not declared beside it | `parsePackageDeps` |
| The boundary test computed from the corpus | `ScopeRegistry.crossing`, off `parseExposes` |
| One provider per namespace, resolved once and cached | `resolvePackage`, `ScopeRegistry.packages` |
| A name two namespaces claim keeps both claimants | `ScopeIndex.collisions`, `buildIndex` |
| The empty-namespace note | `formatPackageNote`, `unservedNote` in `src/index.ts` |

`origin` stays the display string (`http 1.0.0`) that `originSuffix` prints.
The namespace is the identity next to it. A package keeps one namespace across
releases, so two providers are two candidates for one namespace, not two
corpora.

### Read the pin from the header, do not declare it twice

The first plan was a `packages` field on the scope definition. But the
platform's own header already carries the pin that it was compiled against:

```
	packages {
		http: "https://github.com/roc-lang/http/releases/download/1.0.0/...",
	}
```

Reading the pin from the header is better, for the same reason that `exposes` is
read and not hardcoded. A refresh that repins the package cannot leave a second
copy of the version with a different value. The repo path in that URL is the
namespace identity, and the tag in the URL is the required release. Phase 2
adds a manifest version. That version is a convenience, and `plugin validate`
checks it against the header pin.

Two checks keep the pin correct. `check:platforms` compiles both scaffolds. A
new test asserts that each scaffold pins the release that its platform header
pins, as `src/upstream.test.ts:59` does for the platform tarball.

### The resolver is a pure function

`resolvePackage(dep, candidates, crossing, forced)` and
`formatPackageNote(platform, version, resolutions)` take all their inputs as
arguments, and the registry only supplies them. Both shipped platforms pin one
package that the host serves. So the shipped registry cannot produce the states
worth testing: a refusal at every tier, or a namespace that no provider fills.
With pure functions, those states are ordinary test inputs.

### Tests

Ten tests, each validated by reverting the behavior it guards.

| Test | Fails when |
|---|---|
| Every item carries its namespace | `ns` stops following the directory |
| Packages are read from the header | `parsePackageDeps` stops reading, which also drops 29 items per platform |
| The boundary is read off the exposed modules | The test stops excluding unexposed importers such as `InternalHttp` |
| A plugin at the pinned release wins | Tier order reverses |
| A release the API will not take is refused | The version check drops, or a refusal stops the search instead of falling through |
| A different release is taken off the boundary | The crossing condition drops and every difference is refused |
| `force` overrides, and the release is printed | `force` is ignored |
| An unserved namespace says so | The note goes quiet, or a refusal terminates the search |
| Two namespaces keep both claimants | `buildIndex` goes back to last write wins, or stops recording collisions |
| A scaffold pins what its header pins | A scaffold repins the package alone |

The collision test guards a property that is currently luck. The http package
contributes 29 `fullName`s and basic-cli 303, with zero in common. The package
uses `Header`, `Method`, `Request` and `Response`, but each platform's client
module is `Http`. A plugin that exposes a module named `Request` breaks that
property. Before this phase, `buildIndex` resolved such a collision by last
write wins, with no warning.

`src/testdata/http-fork/` is the only new corpus. It has two modules that stand
in for a package plugin, and one of them claims `Http.send!` against basic-cli's
own. No app pins it, so no gate compiles it. The vendored http package has the
same status, and `corpus/packages/http/UPSTREAM` records it.

### What was not covered end to end (closed in phase 2)

Phase 1 wired `unservedNote` into both miss branches of `lookup_builtin` and
`get_builtin_module`, and tested its message. But no test ran it through the
server, because `src/index.ts` builds one registry from the shipped
configuration, where every namespace resolves.

Phase 2 closed this gap without a flag. A plugin whose platform header pins a
release that nothing serves reaches that state directly. So the test declares
such a plugin and asks four tools for a name that is not there.

## Phase 2: the manifest and the loader (done)

### `fromManifest()` builds every scope (done)

| Work | Result |
|---|---|
| `fromManifest(dir, manifest, opts) -> LoadedPlugin` | The only constructor of a `ScopeDef` |
| `plugin.json` for builtin, basic-webserver, basic-cli, http | The host's scopes are not hand-written |
| `CORE_PLUGINS` read with `readFileSync` at module load | Synchronous, so `SCOPES` is final before `index.ts` runs |
| `detectPattern(repo)` | No regex ever comes from a manifest |
| `PLUGINS`, `SCOPE_DEFS`, `HOST_PACKAGES` derived once | No tool call derives a resolution again |

Load order is the main risk. `server.registerTool` runs as a top-level side
effect, so plugin loading is synchronous, and `index.ts` needed no
restructuring. For the same reason, plugin resolution reads the workspace from
the environment and not from the client's `roots` handshake, which arrives
after the tools are registered.

A manifest cannot state three things, on purpose. Each removes a possible error:

| Cannot state | Source | Because |
|---|---|---|
| A detection regex | `detect.repo` | A release URL pins every Roc platform, so a repo path is sufficient. A pattern from a manifest adds only a ReDoS risk |
| A tier or a shipper | Both come from how the manifest arrived | A plugin that could name its own tier could outrank the platform it loads beside |
| A namespace or an origin, unless overriding | Derived from name and version | A typo there splits a corpus in two with no warning |

The work differs from the first version of this section in two ways, both on
purpose:

- `SCOPE_DEFS` stays a record and does not become a `Map`. The ~30 sites that
  index it are unchanged, and a `Map` would not give back the safety of the
  union type.
- `ScopeDef.overview` is a path relative to the registry root, not a bare name
  under `corpus/language/overview`, so a plugin can ship its own page.

### `ScopeName` is a string, not a union (done)

`SCOPES` is `readonly ScopeName[]` and `ScopeName` is `string`. As expected, the
change stayed small, because nearly every use of `SCOPES` iterates over it.

The cost is that the compiler does not catch a mistyped scope name. Startup
validation does that job: `RESERVED` rejects a manifest that claims `language`
or `builtin`, and a second claim on a loaded name loses to the first.

### Declaring a plugin (done)

| Source | Result |
|---|---|
| `--plugin=<pkg-or-path>`, repeatable | `declarations()`, `src/plugins.ts` |
| `ROC_MCP_PLUGINS`, comma or colon separated | The same, for clients that pass env more easily than args |
| `roc-syntax-mcp.json` at the workspace root | `readWorkspaceConfig()`, which also names the default scope |

The three sources add to each other, and the first mention wins. A package spec
resolves through its `plugin.json`, not an entry point, because a plugin ships
no JavaScript and does not need a `main`.

The failure table from the design page, as implemented:

| Failure | Behavior |
|---|---|
| A declaration resolves to nothing | `process.exit(1)` with the reason on stderr. The only failure after which no plugin loads |
| A manifest is unreadable or malformed | Skipped, the rest load, diagnosed |
| A path in a manifest leaves the plugin directory | Skipped, diagnosed. The read would reach a file that the operator did not install |
| A reserved or already-claimed scope name | Skipped, diagnosed |
| A manifest with fields this host does not know | Loads |
| A plugin built against another nightly | Loads, named in `list_roc_index(kind: "scopes")` |

Diagnostics go to two places: stderr at startup, which an operator reads, and
the scope listing, which a model reads. They go nowhere else, because
provenance on every response costs tokens on calls that did not ask for it.

### One "it lives elsewhere" message (done)

The message has two renderings, and each is correct for its callers:

| Builder | Used by | Reads |
|---|---|---|
| `outOfScopeNote`, `src/server.ts:694` | The addressed lookups | `Found in:` per scope, then a retry naming `scope:` |
| `scopeFooter`, `src/server.ts:760` | Every listing and search | `(basic-cli: 3 other. Retry with scope= to see them.)` |

The duplicated part was the candidate list that each caller assembled first.
Eight sites built the same `{ scope, count }[]`, each with its own counting
rule. The counting rules differ for a good reason. What a caller would see in
another scope is a name match, a member count or a topic hit, not one number.

The rest is the same at every site, and `src/elsewhere.ts` holds it. A scope
that the answer already read is not a place to look again. A scope with no
matches never gets a retry, because the retry would come back empty.

#### A correction to an earlier version of this section

The earlier version said that the rule for which scopes to offer was one rule
in two places: `scopeFooter` applied it, and `outOfScopeNote` trusted its
callers. That was wrong, and the two tests that fix the behavior show it:

| Test, `src/detect_server.test.ts` | Asserts |
|---|---|
| a footer never offers the platform the workspace does not pin, 332 | `search` in a basic-cli workspace never names basic-webserver |
| a name from the platform not pinned is reported as out of scope, 275 | `lookup_builtin` in that same workspace names basic-webserver by name |

Both tests are correct. A footer is under an answer that already succeeded. A
retry into a corpus that the app cannot compile against pushes a model toward
code that will not build. An addressed miss is the opposite case. The caller
holds a name that exists, and "it is in basic-webserver, which this workspace
does not pin" explains the miss.

So the code names the two policies and does not merge them. `Reach` is `pinned`
or `anywhere`. Each site picks one, and the choice is visible at the call.

| Piece | Does |
|---|---|
| `elsewhere()`, `src/elsewhere.ts` | Candidates from a per-scope counting callback, under a named reach. Pure, so a platform with nothing in it and a workspace pinning a platform that is not here are ordinary arguments |
| `elsewhere()`, `src/server.ts:663` | The same, with the two facts every site would repeat: which platform is in the space, and which scopes are platforms |
| `trailingNotes()`, `src/server.ts:792` | Composes footer, host tier, detection and unserved in one order |

`unservedNote` is derived from the answer and not passed in, so no site can
forget it. The note appears exactly when nothing came back. In that case, an
unserved namespace explains why a name that exists is missing. The detection
note stays opt-in. It is the only note whose placement each tool decides,
because `list_roc_index(kind: "scopes")` reports detection in full and would
print it twice.

This was a refactor only, and a check showed it: 20 tool calls across 3
platform configurations gave byte-identical output before and after.

| Test | Asserts |
|---|---|
| `src/elsewhere.test.ts`, 6 tests | Each rule separately, including the two the live registry cannot reach |
| a namespace nothing serves is reported by every tool that comes up empty | The end-to-end case that phase 1 could not reach, through a plugin that pins a release nothing serves. Four tools, and one of them never got the note before |
| an answer that found something does not carry the unserved note | The other half of that rule |

### The compatibility test (done)

The design page has rules that a manifest schema must never break. A test
enforces them. `src/testdata/plugin-v1/` is a manifest with every v1 field, and
its test must always pass. The fixture can get new fields. No field in it can
change meaning or be removed.

A consequence: a parser improvement changes the item counts of an unchanged
plugin. That is desirable, but an unchanged plugin can then give changed output.
So plugin checks assert shape, never exact counts.

### Tests

All of these tests are in `src/scopes.test.ts`, `src/plugins.test.ts` and
`src/elsewhere.test.ts`. Each one was validated by reverting the behavior it
guards.

| Test | Asserts |
|---|---|
| Frozen v1 fixture | A v1 manifest loads on this host, field for field, forever |
| Frozen v1 corpus | It indexes into the shape its manifest describes. Shape, never a count: a parser improvement changes an unchanged plugin's counts, and that is desirable |
| Unknown fields | A manifest with a field from a newer host loads, and the field is ignored |
| Duplicate scope name | First wins, second skipped, diagnosed, server still serves |
| Malformed manifest | That plugin is skipped and the rest load |
| Unresolvable explicit plugin | Exit non-zero with the reason on stderr |
| Reserved scope name | Rejected at startup |
| Escaping path | A manifest reaching outside its own directory is rejected |
| Detection from `detect.repo` | Matches the same headers the hand-written pattern did |
| Manifest cannot promote itself | A tier or shipper written into a manifest is ignored |
| Every checked-in scope | Built from a manifest on disk, with the fields spelled out rather than read back |
| The shared "elsewhere" message | Six unit tests over `elsewhere`, plus the unserved note reaching four tools |

Behavior did not change across the whole phase. Two checks show this:

- After the manifest migration, a fingerprint of every address space matched
  item by item.
- After the shared "elsewhere" message went in, 20 tool calls across 3 platform
  configurations gave byte-identical output.

## Phase 3: package detection (done)

Before this phase, `src/detect.ts` read only `pf: platform "..."` from the app
header. The header also carries the app's package pins, and
`corpus/platforms/basic-webserver/examples` already has apps that pin `http:`
next to `pf:`. When detection reads both, the app header is the single source of
truth for what belongs in the space. The platform already follows that rule.

`appPins()` reads the pins in the same header read that found the platform, so
one app's platform is never paired with another app's packages. An app header
binds packages inline, not in the `packages { ... }` block of a platform header,
so `appPins()` is a separate reader. The two readers share the shape of a pin,
and `pinFromUrl()` defines that shape in one place.

### Two headers, two authorities

| Says | Which header | Because |
|---|---|---|
| What must compile across the platform's API | The platform's | It is the release the platform was built against |
| What the app imports at all | The app's | The platform has no opinion about a package it never declares |

Where both headers name a package, the platform's pin decides the required
release. If the app pins a different release, that is a conflict to report, not
a second requirement. `ScopeRegistry.spacePackages()` does that merge. Its
result is the list for the space, not for a scope. `packages(scope)` returns only
the pins in the platform header, so the dependency of one workspace never enters
a corpus that this server ships.

A package that only the app pins gets its own namespace as its tag, not a
scope, because no scope owns it. A space can hold such a package with no
platform at all. A package plugin together with an app pin reaches that case,
and neither reaches it alone.

### A diagnostic the compiler cannot give

Two copies of a package with different content give two nominal types. The
compiler's diagnostic names both sides `Request` and does not say which package
each comes from. With both pins, `formatPinConflict()` can name them:

| App pin vs what is served | Message |
|---|---|
| Differs, and the package crosses the platform's API | This app will not compile, which modules carry the types, and the release to move the pin to |
| Differs, off the boundary | It compiles. The signatures shown are from the other release. Verify with `roc_check` |
| Agrees | Nothing |

It shares the once-per-root limit with the version-mismatch note, because both
notes say that a pin in the workspace differs from what this server serves.

The note for an unserved pin names the app, not the platform.
`formatPackageNote` said "basic-webserver 0.16.0 requires 1.0.0". For a package
that the platform never declares, that names a dependency the platform does not
have. So for a namespace that the app requires, the note reads "Your app header
pins 1.0.0".

### Tests

Tests in `src/detect.test.ts`, `src/scopes.test.ts`, `src/detect_server.test.ts`
and `src/plugins.test.ts`, each validated by reverting the behavior it guards.

| Test | Asserts |
|---|---|
| Pins beside the platform | The header's packages are read and the platform entry is not one of them |
| A pin that is not a release URL | A local path has no namespace, and a file with no header pins nothing |
| One header, one read | The pins belong to the app whose platform was detected, not to a neighbour |
| An app-only package | Joins the space, and enters no scope's own corpus |
| Cache invalidation | A space built before detection lands does not outlive it |
| No platform in the space | An app's pin still reaches it, tagged with its namespace, and is still reported when unserved |
| The requirer | An unserved app-only pin reads as the app's requirement, not the platform's |
| A refused release | Named as a compile error, with the crossing modules and the release to move to |
| An off-boundary release | Named as a documentation gap, not a compile error |
| The shipped case | An app pinning what its platform requires is told nothing new |
| Plugin plus app pin | A package plugin serves a namespace only the app's header pins |
| `check:detection` | The extra namespace survives the trip through a real client |

Every bundled example pins exactly what its platform requires, so the shipped
case does not change. A check confirmed this: 20 tool calls across 3 workspaces
gave output byte-identical to the previous commit.

## Phase 4: developer tooling (done)

One binary does two jobs. `roc-syntax-mcp` with no arguments is the MCP server,
and `roc-syntax-mcp plugin <command>` is the tooling for plugin authors. The
dispatch is in `bin/roc-syntax-mcp.js`. It never imports the server, because the
import starts a server.

| Command | Does |
|---|---|
| `plugin init <dir>` | Manifest, layout, `scaffold.roc` with its markers, a handler fixture, an overview page and the verify app that compiles its snippets |
| `plugin validate <dir>` | Everything in the table below |
| `plugin inspect <dir>` | What this host would index: namespaces, counts by tier, what each provider fills, and which overrides a bundled platform would refuse |
| `plugin doctor` | The declarations a server launched here would read, where each one ends up, and the frozen resolution table. Exits non-zero if anything is not served |

### What `validate` checks

| Check | Fails when |
|---|---|
| `manifest` | `fromManifest` cannot read it. No other check runs, because every other check needs the manifest |
| `name` | It is reserved, or a scope this server already ships, and the host's copy wins |
| `paths` | A declared path leaves the plugin, or is not there. The loader skips such a plugin, and the author gets no message |
| `corpus` | The declared module directories parsed to no items at all |
| `duplicates` | One namespace claims a name twice, which is a parser gap and not a legitimate collision |
| `collisions` | Never. Across namespaces a collision is legitimate, and it is counted because one lookup returns both |
| `packages` | Never. It names which bundled platform's API each declared package crosses, and which release that platform requires |
| `overview` | The page is over 2500 tokens. `roc_overview` returns it whole, and the host's own pages are 1500 to 2000 |
| `snippets` | A fenced Roc block on the overview page is in no app under `checks:` |
| `budget` | The plugin adds more than 60 tokens to `tools/list`, measured against a server not carrying it |
| `roc check` | `scripts/check-platform-examples.sh <dir>` fails |
| `roc_check` | `scripts/check-roc-check.mjs --plugin=<dir>` fails |

The last three checks start child processes. `--offline` drops them. When no
`roc` is on PATH, both compiler gates report `skip`, not `ok`, because a gate
that did not run did not pass.

### The gate scripts accept a plugin directory

`check-platform-examples.sh` took no arguments and globbed `corpus/platforms/*/`.
It takes plugin directories, with that glob as the default, and each manifest
says what to compile. Two fields hold that list:

| Field | Is |
|---|---|
| `handler` | A bare handler with no header, which is the shape that `roc_check` submits. The script wraps it with `scaffold` and compiles it, so the check covers the prelude together with a handler, not alone |
| `checks` | Directories of complete programs, other than `examples`, that the gate compiles: topic files, and the app that holds every overview snippet |

`HANDLER` was a bash associative array with one entry per platform. A foreign
plugin could not add an entry to it, and the script failed with an error for a
platform that had no entry. The manifest field keeps that error, and moves the
entry to the manifest, which describes the platform.

`check-roc-check.mjs` takes `--plugin=<dir>`, which runs the one case that its
fixtures cannot: a foreign platform's handler, through detection, the scaffold
and the compiler, on the real server. The option replaces the script's own
fixtures and does not add to them, because those fixtures test this repo's two
platforms.

### Two bugs the tooling found on its first run

Both bugs affected every declared plugin, and both are the same mistake:

| Site | Was | A plugin got |
|---|---|---|
| `template`, `src/roc_check.ts:62` | `path.join(ROOT, def.scaffold)` | The server did not find its scaffold, so it returned bare code unwrapped, with no error |
| `loadOverview`, `src/overview.ts:14` | `path.join(dir, page)` | `# Overview unavailable` from `roc_overview` |

Every path in a manifest is absolute for a declared plugin and relative for a
plugin that this server ships. So `join` pointed both sites at
`<repo>/<absolute path>`, with no error. The host's own scopes did not show the
bug. Phase 2 builds every scope through `fromManifest`, but that rule did not
catch the bug, because the host's manifests are the relative case.

### Where `doctor` had to be allowed to run

The server exits non-zero on a declaration that resolves to nothing, and
`doctor` exists to explain that configuration. If the CLI loaded the plugin set
at module load, it would exit before it printed anything.

`inspectDeclarations()` resolves and evaluates every declaration, but does not
act on the result. The startup path acts on the result, and `doctor` prints it,
so an operator sees the same rule that ran. `useCliMode()` in `src/plugins.ts`
tells the loader not to act. It is a module-level flag and not an environment
variable. The CLI starts servers and gates that must load declarations
normally, and each of those processes would inherit a variable.

### Tests

25 tests in `src/plugin_cli.test.ts` and 1 in `src/plugins.test.ts`, each
validated by reverting the behavior it guards.

| Test | Fails when |
|---|---|
| What `init` writes passes every offline check | The skeleton ships a defect to every author at once |
| `init`'s snippets are in the app `init` writes for them | The skeleton's own verify app stops carrying them |
| `init` refuses a directory holding a plugin | It overwrites an author's work |
| An unreadable manifest is the only thing reported | A later check runs on a manifest that did not load |
| A name the host ships, and a reserved name | Either is accepted, and the plugin is never served, with no message |
| An escaping path, a missing path, a `handler` outside the plugin | The escaping check stops covering a field |
| A corpus that parsed to nothing | An empty scope is reported as a loaded one |
| An overview over the ceiling | The ceiling stops binding |
| A snippet in no compiled app, and one in a compiled app | The page is allowed to drift from what compiles |
| Fenced Roc blocks and nothing else | A bash block is read as Roc |
| A refused package release, and one no platform declares | A refusal is reported as a service |
| `inspect` names the namespace and the tier | Provenance drops out of the report |
| `inspect` reports rather than throws | A bad manifest kills the command |
| `doctor` fails over a declaration resolving to nothing | Its exit code stops agreeing with the server's |
| `doctor` names every declaration's source | The fix stops being findable where it was written |
| `doctor` prints the resolution table, and says so when nothing is declared | The command reports less than it resolved |
| `doctor` fails over a namespace no provider serves | The conflict an operator came to find is printed as a row like any other |
| `doctor` runs where the server refuses to start | The loader acts under the CLI, and the command dies before printing |
| A plugin's scaffold is read from the plugin | `roc_check` uses `join` again |
| A plugin's overview page is read from the plugin | `roc_overview` uses `join` again |
| The frozen v1 manifest carries `handler` and `checks` | A v1 field added later stops loading |

The shipped case did not change. A check confirmed this: 20 tool calls across 3
workspaces gave output byte-identical to the previous commit.

One change to what a caller reads is on purpose. `roc_check` said `Wrapped in
the bundled <platform> <version> app`. But `roc_check` verifies a declared
plugin's platform the same way, and that platform is not bundled. So the message
is `Wrapped in the <platform> <version> app`.

## Phase 5: the authoring skill (done)

The code is the easy half. The value of this server is in findings such as the
seven at `docs/plans/basic-cli-scope.md:155`. A model would get each of them
wrong without help, and each was found by writing a program and watching the
compiler reject it. `validate` enforces the mechanical parts. It cannot enforce
that someone noticed that `Utc.now!` returns nanoseconds.

`.claude/skills/author-roc-plugin/` is the skill, in the shape of
`.claude/skills/refresh-roc-upstream/`: `SKILL.md` plus four reference pages.

| Page | Holds |
|---|---|
| `SKILL.md` | The orientation, the nine steps, the `validate` table, and the invariants |
| `reference/finding-traps.md` | The method, ten probes, and the seven findings as calibration |
| `reference/overview-page.md` | The budget, the six-part anatomy, and what to leave out |
| `reference/manifest.md` | Field by field, and the compatibility contract |
| `reference/package-plugin.md` | The tier-1 track: crossing, refusal, and the empty namespace |

The probes are the most useful part. Each probe describes a pattern, not a
single fact, so it applies beyond basic-cli. Examples are what a decoy module
name looks like, what an unannotated upstream member costs an app, and which
types an app cannot name and so must leave unannotated. Six of the seven
findings were type errors that the compiler reported to the program's author.
The seventh, nanoseconds, is one that no type checker catches, so it most needs
to be written down.

### Maintainer attribution

This is the other half of this phase. `maintainer` is a manifest field.
`ScopeDef` carries it, and `list_roc_index(kind: "scopes")` prints it for every
scope. The default is whoever loaded the plugin, so this server is the
maintainer of the four scopes it ships. A declared plugin that names no
maintainer is listed as naming nobody, and is not attributed to itself.

`validate` fails a manifest with no maintainer, and the loader never does. They
answer different questions. The loader decides whether to serve a corpus that
is already installed. `validate` decides whether a corpus is ready to publish.
For every other optional field, `validate` reports and does not refuse. So this
is the only place where the author's check is stricter than the host. `init`
writes the field, so the skeleton still passes.

`inspect` prints the maintainer too. Every place where this server reports a
plugin's identity names its maintainer.

### `force` had no configuration source

This was found during work on `reference/package-plugin.md`. The resolver
honored a `force` list, and phase 3 tested it, but no code set the list. A
declaration was a string in all three sources, and the server built its
registry with no options. So the note that told an operator to force a
namespace pointed at a setting that nobody could change.

`forcedNamespaces()` reads the list from the same three sources as a
declaration, and never from a manifest. Keep that property: a plugin can never
force its own namespace.

| Source | Written | Why that shape |
|---|---|---|
| `--force=<id>`, repeatable | `--force=roc-lang/http` | A flag string cannot carry structure without a new separator |
| `ROC_MCP_FORCE` | Same separators as `ROC_MCP_PLUGINS` | Same contract, for a client that passes env more easily |
| `roc-syntax-mcp.json` | `{ "id": "...", "force": [...] }` | JSON can carry structure, so `force` is part of the declaration that it applies to |

So `WorkspaceConfig.plugins` is `(string | { id, force? })[]`, and the object
form exists only for `force`.

Three places show the override, because an invisible override is worse than a
refused one:

| Where | What |
|---|---|
| Every item of a forced namespace | `(http 1.2.0, forced over 1.0.0)`, per item rather than as a footer |
| `plugin doctor` | The namespaces forced and where each was written, plus `FORCED` on the row it changed |
| The unserved-namespace note | Names the switch: `run this server with --force=roc-lang/http` |

The per-item label is the most important choice. An override changes every
signature in that namespace. A caller who reads one signature and stops must
still learn about the override, and a footer reaches only a reader who reads to
the end.

An id that is not a repo path names no namespace. The server reports it with a
diagnostic and does not drop it. The operator wrote the id to change a
resolution, and a typo would change nothing and give no reason. It is the first
diagnostic that is not about a plugin, so `LoadDiagnostic` got a `kind`, and its
`plugin` field became `subject`. The diagnostic reads
`roc-syntax: force <id> (--force=)`, which is more accurate than calling the id
a plugin.

### Tests

Four tests in `src/skills.test.ts`, six in `src/plugins.test.ts`, and four in
`src/plugin_cli.test.ts`, each validated by reverting the behavior it guards.

| Test | Fails when |
|---|---|
| Every repo path the skill names is there | A rename breaks a path in the skill with no error, and an author's model reads the broken path as fact |
| Every reference page is linked, and every link resolves | A page is unreachable, or a link promises detail that is not there |
| Every `plugin` subcommand shown is one the CLI dispatches | The skill invents a command, or a command goes undocumented |
| Every check `validate` emits is explained in the skill | A check reports a failure the author has no way to read |
| The listing says who answers for every scope | The default drops and this server's own scopes go unattributed |
| A plugin is listed under the maintainer it names, or as naming nobody | A plugin that names nobody is attributed to itself |
| A manifest naming no maintainer is refused, and `inspect` says so | `validate` stops asking for a maintainer before publishing |
| A forced namespace is read from all three sources, first mention winning | A source drops, or the object form stops carrying `force` |
| A workspace config declares a plugin as a string or as an object | The object form stops yielding a declaration |
| A forced namespace is served, and every item says what it was forced over | The override stops applying, or applies with no label |
| A forced id that is not a repo path is reported where an operator looks | A typo changes nothing and says nothing |
| `doctor` names every forced namespace, and fails over one that names none | `doctor`, the only place where an operator can see an override without serving it, stops reporting it |
| `doctor` says nothing about forcing when nothing is forced | A default install prints a line about a setting that nobody changed |
| The resolution table marks the row an override changed | The table reads as a resolution the host arrived at itself |

The frozen v1 fixture carries `maintainer`, so the field-for-field test covers it.

The path test is scoped to this skill. `refresh-roc-upstream` names paths inside
the upstream repos it vendors from, which do not exist here.

This phase changes the shipped case in one way, on purpose: the scopes listing
has a maintainer line. Apart from that, 20 tool calls across 3 workspaces gave
output byte-identical to the previous commit, and all 12 lines that differ are
that maintainer line.

## Out of scope for these phases

The non-goals table in `docs/design/plugins.md` lists what the design rejects on
purpose: JS plugins, a downloaded registry, auto-scanning `node_modules`,
refusing stale plugins, packages as scopes, two platforms in one space, and
exiting on a plugin conflict. None of them is deferred work.
