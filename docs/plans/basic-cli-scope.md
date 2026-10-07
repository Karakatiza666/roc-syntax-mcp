# Plan: add basic-cli 0.22.0 as a second platform scope

## Status

| Phase | State |
|---|---|
| 0. Compile the release against the pinned nightly | Done. 31 of 31 upstream examples pass `roc check` under `db56022` before vendoring |
| 1. Provenance and vendoring | Done. One repin patch, no second patch needed |
| 2. Registry, and the shared http package | Done. Both scopes list `corpus/packages/http/`, and the merge folds it back |
| 3. Two platforms in one address space | Done. At most one platform is active, so the 197 shared names never compete |
| 4. Parser gaps the new corpus showed | Done. Unannotated members and space indentation, both fixes validated by reverting them |
| 5. Content | Done. 1 overview, 7 topics, 1 verify app, 1 scaffold, all compiling |
| 6. Gates and tests | Done. 149 tests, 78 bundled programs, 11 roc_check cases, 4 detection fixtures |

## What the existing design already handled

`docs/plans/basic-webserver-scope.md` designed the scope code for any number of
platforms. `SCOPE_DEFS` drives detection, scaffolding, examples, docs and
overviews from data, and `PLATFORM_SCOPES` already derived the platform list.
basic-cli needed no new tool, no new parameter on an existing tool, and no
change to the resolution order.

Four things named only one platform in hardcoded text. This plan derives them:
the topic scope union, the `search_roc_syntax` and `search_builtin_signatures`
enums, and the "unrecognized platform" message, which named basic-webserver as
the only index.

## A premise that two platforms break

The basic-webserver plan measured "zero `fullName` collisions and zero
module-name collisions between corpora" and built addressed lookups on it.
`lookup_builtin` and `get_builtin_module` resolve across every scope, because a
scope filter could only change a name the caller holds into "not found".

Two platforms with a common ancestor break that premise:

| Measure | Value |
|---|---|
| Module names in both platforms | 16, including `Cmd`, `Env`, `File`, `Http`, `IOErr`, `OsStr`, `Path`, `Sqlite`, `Tcp`, `Url` |
| `fullName`s in both | 197 |
| Of those, with identical signatures | 102 |
| Of those, with different signatures | 95 |

`Cmd.exec!` reports timeouts on basic-webserver and cannot on basic-cli.
`Env.dict!` returns records on one and tuples on the other. `Env.platform!`
returns a named type on one and an inline union on the other. A merged index that
keeps one arbitrary winner would answer about half of those questions from the
wrong platform, with no sign of it. The rest of this
design prevents that failure everywhere.

### What replaced it: one platform at a time

The first attempt kept the merge and showed the collision. It returned both
matches, labeled each with its origin, and let `scope` break the tie. That
design was wrong. It treats the other platform's `Cmd.exec!` as a second answer
to the same question. But an app header pins exactly one platform, and this
workspace cannot use the other platform's signature. A model that sees that
signature can use it.

So the working set holds at most one platform. The addressed lookups resolve
over an address space, not over the whole registry:

| Active platform | Address space |
|---|---|
| One, from an explicit `scope`, `--scope=`, or detection | Every non-platform corpus, plus that platform |
| None | Every non-platform corpus. No platform at all |

The second row needs a reason. The first answer was a fallback to every
platform. That answer is wrong for the same reason as the merge: two signatures
under one name are not an answer, and a model that gets one will use it. A guess
at a platform is worse. Only an empty platform slot keeps a signature that
cannot compile away from the caller.

Because a space holds at most one platform, collisions cannot occur.
`addressSpace` needs no code for them: no `allByFullName`, no per-origin
deduplication of the shared `http` package, and no tie-break.
`src/scopes.test.ts` asserts that every `fullName` in a space is unique.

| Situation | Answer |
|---|---|
| A name in the active platform | The item, as before |
| A name only another platform has | Not in the builtins or the pinned platform, so it will not compile here. Then `Found in:` with one line per platform, then a retry that names `scope: basic-webserver` |
| A name in a platform, with none pinned | Not in the builtins, and no platform is in scope. Then the same `Found in:` list, then a retry that points back at it |
| A name in none of them | Unknown, as before |

Out of scope and unknown are different answers, and each needs a different next
step. "No builtin matched" is false for a name that exists. Each note ends at a
`scope` value, so a model can act on it or ignore it. The optional `scope` on
both tools makes that retry possible. It names a platform, not any corpus,
because an addressed lookup narrowed to `builtin` has no meaning.

Search footers follow the same rule. With a platform pinned, a footer never
offers a retry in the other platform, because code from that platform does not
compile. With no platform pinned, a footer names where the matches are. A caller
needs only that to pick a scope.

### The shared package

Both platforms re-export `roc-lang/http` 1.0.0 and pin the same tarball. This
plan vendors it once in `corpus/packages/http/`, moved from
`corpus/platforms/basic-webserver/http/`, and lists it in the `modules` of both
scopes. A space holds one platform, so the package is never in a space twice
and needs no deduplication.

The alternative was a third scope for the package. The basic-webserver plan
folded the package into basic-webserver, and its reason also rejects a third
scope. A third scope costs enum tokens on three tools, for a distinction that
no caller needs. No app can use either platform without the package.

## Parser gaps that this corpus showed

Both gaps existed before this plan, and both also dropped basic-webserver items.
Neither was visible before a corpus whose main API falls into them.

| Gap | What was missing | Fix |
|---|---|---|
| Only annotated values were indexed | `Sqlite.query_many!`, every row decoder, `Tcp.connect!`, `File.open_reader!`, and 35 `Html` element helpers | Indexed with the lambda head as signature and `unannotated: true`. That flag keeps them out of signature search and prints them with `=`, not `:` |
| Only tab indentation was counted | All of `InternalSqlite.roc`, which upstream indents with four spaces | The parser detects the indent unit per file. A file with any tab indentation counts tabs |

As a result, basic-webserver app-facing items went from 427 to 469, and the host
tier went from 138 to 141.

## Bundle inventory

| Content | Bundle |
|---|---|
| 18 exposed platform modules | Yes, indexed and sliced |
| 4 internal modules (`Host`, `Internal*`) plus `main.roc` | Yes, host tier |
| 31 examples | Yes, repinned to 0.22.0 by patch `0001` |
| `roc-lang/http` | Already bundled. Shared with basic-webserver |
| `README.md` | No. Curated into `corpus/platforms/basic-cli/overview.md` |
| `CONTRIBUTING.md`, `docs/index.html`, `src/`, `ci/` | No. Contributor-facing or the Rust host |
| `examples/todos*.db` | No. Binary fixtures |

basic-cli ships no prose pages, so the scope declares no `docs` directory. This
is asserted, not assumed, because an empty directory and a missing directory
look the same in a diff.

## Item counts

| Corpus | Public | Host | Private |
|---|---|---|---|
| `basic-webserver` | 469 | 141 | 2 |
| `basic-cli` | 243 | 89 | 0 |

## Content

| File | Note |
|---|---|
| `corpus/platforms/basic-cli/overview.md` | ~1.7k tokens, under the 2000 ceiling asserted for a platform page |
| `corpus/platforms/basic-cli/topics/` | 7 apps: `cli_app`, `cli_files`, `cli_command`, `cli_http`, `cli_sqlite`, `cli_terminal`, `cli_net` |
| `corpus/platforms/basic-cli/verify/overview-snippets.roc` | Every snippet in the overview, in one app, so the page cannot drift from what compiles |
| `corpus/platforms/basic-cli/scaffold.roc` | One `@default`, `main!`, because the platform requires exactly one function |

Findings to keep. Without them, a model would get each of these wrong:

| Finding | Where it landed |
|---|---|
| `File` holds only the buffered reader. The whole filesystem API is on `Path` | Overview lead, `cli_files`, and a trap in the reference page |
| A string literal is a `Path` only where an annotation makes it one | Overview and `cli_files` |
| `Url.ParseErr` is a closed union and will not merge with the open `[..]` that every effect returns | `cli_net`. The compiler found it when it rejected the first draft |
| `Sqlite.query!` and `query_many!` are unannotated upstream, so the result type does not flow out of the decoder | `cli_sqlite`, which annotates every binding and says why |
| A row decoder's inner stage has a type over a host handle that an app cannot name, so the app must leave it unannotated | `cli_sqlite` |
| `Http.send_json!` returns a `Response`, not the decoded reply | `cli_http` |
| `Utc.now!` returns nanoseconds, not seconds or milliseconds | Overview trap list, `cli_terminal` |

## Gates

| Gate | Before | After |
|---|---|---|
| `npm test` | 131 | 149 |
| `check:platforms` (was `check:webserver`) | 37 programs | 78 |
| `check:roc-check` | 8 cases | 11 |
| `check:detection` | 3 fixtures | 4 |
| `tools/list` | 2,569 tokens | 2,698, against a 2,800 ceiling |

This plan renames `check-webserver-examples.sh` to `check-platform-examples.sh`.
The script finds platforms with the glob `corpus/platforms/*/platform/` and does
not list them. With a hardcoded array, a platform added to the tree but not to
the array would look checked, but the script would never check it.

The rename is the only breaking change to a documented command. The name
`check:webserver` is wrong for a script that checks both corpora.

## Low headroom

`tools/list` has 102 tokens of headroom below its ceiling. Most of the growth
comes from `search_roc_syntax`, because its description lists every topic name,
and this plan adds seven names. A third platform does not fit unless someone
raises the ceiling or removes the topic list from the tool description. Whoever
adds the third platform should make that decision on purpose, not discover it.
