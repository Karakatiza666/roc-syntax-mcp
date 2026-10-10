---
name: refresh-roc-upstream
description: Refresh roc-syntax-mcp's bundled Roc content (all_roc_syntax.roc, Builtin.roc, corpus/language/langref/, and the basic-webserver and basic-cli platform corpora) to a newer upstream and reconcile everything derived from it - the builtin parser, hints, topic examples, overview, README, and tests. Use when the bundled Roc nightly moves, when any UPSTREAM file under corpus/ is stale, or when the bundled reference contradicts the current compiler. Each platform stays on the nightly of its release until it is repinned, because the gates check every program with the nightly it was written for.
---

# Refreshing roc-syntax-mcp from upstream

This server bundles a snapshot of the Roc language and serves it to agents. A
refresh has two halves, and each half fails in a different way:

| Half | Content | Failure mode |
|---|---|---|
| Copied | `corpus/language/examples/all_roc_syntax.roc`, `corpus/language/Builtin.roc`, `corpus/language/langref/` | A byte-for-byte copy matches upstream or it does not |
| Derived | `corpus/language/topics/`, `corpus/language/overview/`, `src/builtin_hints.ts`, `src/topics.ts` and `src/server.ts` metadata, `README.md` | It continues to teach what upstream reversed, and nothing reports an error |

The copied half is a `curl`. The derived half is the real work. If you skip it,
the server states the opposite of the truth with confidence. In the 2026-08
refresh, `static_dispatch.roc` and `operators.roc` both said that `|>` was
removed, months after upstream restored it.

A refresh is complete only when a real `roc` binary type-checks every bundled
`.roc` file. Hand review cannot replace this check. In the last refresh, hand
review missed five real errors.

In this skill, a gate is one of the repo's named check scripts: `bun run check`
(`scripts/check-all.sh`) and each `npm run check:*` script.

## Orientation

| Path | Role |
|---|---|
| `corpus/language/UPSTREAM` | The pinned language commit, the compiler nightly and the path mapping. Diff against it. Do not guess |
| `corpus/language/Builtin.roc` | Too large to serve. The server never serves it whole, and parses it at startup. It has no `index.json` (see Step 6) |
| `src/builtin_parser.ts` | A heuristic line parser, and the most fragile code here. See `reference/parser-traps.md` |
| `src/builtin_hints.ts` | Ours, not upstream's. One-line hints for builtins whose names mislead |
| `src/langref.ts` | Splits upstream `.md` pages into sections, for the test of `corpus/language/langref-map.txt`. `scripts/langref-diff.roc` splits them the same way |
| `src/overview.ts` | The two-page overview that `get_roc_syntax()` serves, under a strict token budget |
| `corpus/language/topics/*.roc` | Hand-written fragments. This is the derived content with the highest risk |
| `scripts/check-roc.sh` | Type-checks every bundled `.roc` against a real compiler |
| `corpus/platforms/<name>/UPSTREAM` | One file per platform corpus. Each platform is a separate upstream with its own release schedule and the nightly of its release. See `reference/basic-webserver.md` and `reference/basic-cli.md` |
| `corpus/packages/http/UPSTREAM` | One package that both platforms re-export. It is indexed once at `corpus/packages/http/` and listed under each platform |
| `corpus/*/*/index.json`, `plugins/*/index.json` | The parsed signatures of the release that the `release` URL of each manifest names. `npm run build:index` generates them for both trees. Never edit them. The repository contains no release source |
| `corpus/packages/roc-random/UPSTREAM` | No bundled platform pins it. It stays at the release that the roc-ray plugin pins, because the API of roc-ray uses its types |
| `corpus/packages/{roc-parser,roc-random}/overview.md`, `topics/` | Ours, derived from the release. Each page says what the package is for, and its topics are compiled (one per format for roc-parser). Read all of them again when the release changes. `src/scopes.test.ts` checks every name on the page, and checks that each snippet line is in a compiled topic |

Compare a refresh against the record of the last refresh: the builtin counts in
`corpus/language/UPSTREAM`, and the measurements in its commit message (Step 8).
Measure the new values. Do not read them from a file. `npm test` prints what the
parser found when a count changed, `tool-cost.mjs` prints the tool-list cost,
and `plugin inspect` prints the items of each corpus.

Two traps from past refreshes:

- On that nightly, `roc fmt` deletes a file that holds only comments, and it
  indents comment lines incorrectly. Never use it to rewrite bundled content.
- A nightly can hang or segfault `roc check` on one program.
  `check-platform-examples.sh` gives each file `ROC_CHECK_TIMEOUT` seconds
  (default 300) and reports a signal. Bisect the file that it names.

## Kinds of pin

| Pin | Recorded in | Changes when |
|---|---|---|
| Bundled nightly | The `compiler` line in `corpus/language/UPSTREAM` | You unpack a newer `roc_nightly-*` |
| Platform nightly | The `compiler` line in `corpus/platforms/<name>/UPSTREAM`: the nightly of that release, from upstream's `.roc-version` at the tag | That platform is repinned |
| Language snapshot | `corpus/language/UPSTREAM`: one roc-lang/roc commit | You copy `Builtin.roc`, `all_roc_syntax.roc` and `corpus/language/langref/` again |
| Platform release | `corpus/platforms/<name>/UPSTREAM`: a tag and tarball hash, one file per platform | That platform makes a release |
| Shared package | `corpus/packages/http/UPSTREAM`: a tag and tarball hash for `roc-lang/http` | roc-lang/http makes a release. Both platforms pin it, so it changes for both at the same time |
| Plugin's package | `corpus/packages/roc-random/UPSTREAM`: a tag and tarball hash | roc-ray changes to a new roc-random release. A new roc-random release alone is not a reason |

Each program is checked with the nightly that it was written for. The gates
(`scripts/nightlies.mjs`) take that nightly from the first of these:

1. The `roc:` line in the program's header. Upstream examples carry one, and
   the examples here keep upstream's line.
2. The `compiler` line in the `UPSTREAM` file of the platform release that the
   program pins by tarball URL. This covers the topics, `verify/` and the
   scaffold. A plugin names the nightly in the `compiler` field of its
   `plugin.json`.
3. The bundled nightly.

Unpack each nightly that the gates need at the repo root. A gate that lacks one
fails and names it. So a platform with no release for a new nightly stays on
the nightly of its release, and the refresh of the other corpora does not fail
on it. The agent that copies one of its examples gets the `roc:` line, and the
compiler warns and names that nightly when the agent runs another one.

A track is the set of steps for one kind of change: the language track or a
platform track. This file covers every track. The checklist for each platform
in `reference/` has its own repin table.

You cannot fix a nightly that breaks a platform in this repo. The `index.json`
files are generated from the released tarballs, and nothing compiles against
them. The gates compile apps that pin each release by URL. When a pair does not
build, there are two options: a newer platform release, or the nightly of the
current release, which the platform's `compiler` line already names. For
example, patch `0002-restore-parked-gregorian-examples.patch` is in the
basic-webserver track only because `gregorian` fails under every nightly from
`db56022` to `130536d`. The platform did not change. The compiler did.

A release can have the same problem in one module, when the fix is upstream but
not in a release. The corpus then pins the release anyway, because only an app
that imports that module fails. `scripts/gate-overrides.json` lets
`check:platforms` check those apps against the release with the fix applied, and
`check:platforms` counts them. On every refresh, look for a release that makes
the entry unnecessary. Then repin, and remove the entry and its `gate-` patch.

The track that a nightly bump needs depends on what fails under the new nightly.
For this reason, Step 1 comes before any edit:

| Baseline under the new nightly | Meaning | Track |
|---|---|---|
| All green | The nightly changed nothing that this repo relies on | Neither. Change the `compiler` line in `corpus/language/UPSTREAM`, and say in the commit that the set was checked again |
| `check:roc` fails | The language changed | Language: Steps 2, 4, 5 |
| `check:platforms` or `check:roc-check` fails | This nightly does not build with a pinned release | Platform: Step 3, then the `reference/` page of the platform that fails. The gate names the file, so find which platform the file belongs to before you assume that both changed |
| Both fail | The usual result of a nightly that adds a syntax change | Both, in one commit |

## Step 0: choose the nightly

You cannot finish without a `roc` binary. Download a nightly from
[roc-lang/roc releases](https://github.com/roc-lang/roc/releases) and unpack it
in the repo root. `.gitignore` already excludes `roc_nightly-*/` and its
tarball.

```bash
ROC=$(echo "$PWD"/roc_nightly-*-<date>-<commit>/roc)   # a glob does not expand in an assignment
export ROC
"$ROC" version
```

Name the new nightly in the glob, because the repo root also holds the nightlies
of the platform releases.

Export `ROC` once, here, so that every later command inherits it. The prefix
form `ROC=$PWD/roc_nightly-*/roc npm run check:roc` does not work. Bash does not
expand a glob in an assignment, and the scripts quote `"$ROC"`. Each script then
reports that it skipped, because it has no compiler. In this case `check` prints
`skipped`, not `ok`, so read the summary lines and not only the exit code.

The bundled content must match the language of that binary. Thus select a
nightly built at or near the commit that you pin. At the end, write the nightly
that you selected on the `compiler` line of `corpus/language/UPSTREAM`.

## Step 1: baseline before you change anything

Run every gate against an unchanged tree with the new binary:

```bash
bun run check
```

This one command divides every later failure into two kinds: "the compiler
changed the language" and "my edit was wrong". If you skip it, you cannot tell
which failures your changes caused and which failures the nightly already had.
`check` runs every gate and does not stop at the first failure, which is the
correct behavior for a baseline.

Write down the gates that fail. That list is the scope of the refresh, and the
table above maps it to a track.

## Step 2: pin a language commit and diff

Never refresh against `main` while it changes. Select one commit, clone it, and
diff each copied tree against the commit that `corpus/language/UPSTREAM`
records.

```bash
SCRATCH=$(mktemp -d)
git clone --depth 1 https://github.com/roc-lang/roc "$SCRATCH/roc"
git -C "$SCRATCH/roc" rev-parse HEAD      # this is the new pin

# Before the copy: every langref section that changed since the pin, with the
# topics that carry it. The script reads the pin from corpus/language/UPSTREAM.
roc scripts/langref-diff.roc -- "$SCRATCH/roc" > "$SCRATCH/langref-diff.md"

cp "$SCRATCH/roc/test/echo/all_syntax_test.roc" corpus/language/examples/all_roc_syntax.roc
cp "$SCRATCH/roc/src/build/roc/Builtin.roc"     corpus/language/Builtin.roc
cp "$SCRATCH/roc"/docs/langref/*.md             corpus/language/langref/
git diff --stat
```

Read the `git diff` on `all_roc_syntax.roc` line by line, and read
`$SCRATCH/langref-diff.md` whole. Together they are the complete list of
language changes that you must propagate, and they cost much less to read than
to find again.

The server does not serve `corpus/language/langref/`. The topics carry every
non-trivial idea of it, and `corpus/language/langref-map.txt` names the topics
that carry each section. So a langref change reaches an agent only through a
topic. For each section in the report:

| Report says | Do |
|---|---|
| Changed | Read the prose diff, and update the topics that the report names. A new rule goes in as an `expect`, a definition, a comment, or a `# @rejects` / `# @warns` block |
| Added | Write its ideas into a topic, or a new topic, and add its line to the map. A section with no rule for code gets `skip: <reason>` |
| Removed | Remove what only that section said from the topics, and remove its line |
| Renamed | Rename its key in the map |

`npm test` and `check:roc` fail until the map has exactly one line for each
section of the new pages.

## Step 3: settle the platform release

Look for a newer release, whatever the baseline result was. A repin costs much
less while the compiler is unpacked and the gates have just run than in a second
pass next month.

```bash
gh release list --repo roc-lang/basic-webserver --limit 5
gh release list --repo roc-lang/basic-cli --limit 5
gh release list --repo roc-lang/http --limit 5
```

Run the query once for each upstream. There are two possible outcomes:

- No newer release exists. Index nothing again, and leave its `compiler` line
  on the nightly of its release. Record in the commit that the platform was
  checked again. A pin that was measured and did not change is a result to
  state, because in a diff it looks the same as a pin that nobody checked.
- A newer release exists. Work through that platform's `reference/` page from
  start to end, and set its `compiler` line to the nightly of the new release:
  1. Move the `release` URL in its `plugin.json`.
  2. Run `npm run build:index`.
  3. Copy `examples/` and `docs/` again, where the platform has them.
  4. Regenerate its patches against the new tag. Do not rebase the old patches.
  5. Repin every site in its table.

`roc-lang/http` is one package under two platforms. Change
`corpus/packages/http/` and `corpus/packages/http/UPSTREAM` only when both
platforms pin the same new release. If only one platform uses a new release,
wait, because the package is indexed once. An app that pins the other release
still gets its signatures, because the server reads them from the compiler's
cache.

`kili-ilo/roc-random` follows the roc-ray pin in
`plugins/roc-ray/platform/main.roc`, with the same rule. `check:platforms`
compiles its `verify/` app. A package is checked with the nightly of the
platform that its programs pin, so its own `compiler` line only records that
nightly.

If a program on the bundled nightly fails and no newer release fixes it, do not
ship a corpus that does not compile. Keep the last nightly that worked, or use
`scripts/gate-overrides.json` for a fix that upstream has not released.

## Step 4: repair the parser before you trust the index

`parseBuiltin` is a heuristic based on tab indentation, and it reads a file that
upstream restructures often. Every past refresh broke it, and always in the same
way: record-body fields went into the index as methods. Run the detection recipe
in `reference/parser-traps.md` before anything else. A corrupt index makes the
hints, the overview counts and every lookup wrong.

Rule: every fix gets a test that fails against the parser from before the fix.
Confirm the failure before you commit. A test that passes both ways checks
nothing.

## Step 5: reconcile the derived content

Work through `reference/derived-content.md`. In summary:

1. Search every topic file for claims that the diff reversed. Operators,
   dispatch and conditionals are the most frequent cases.
2. Resolve every builtin that a topic file names against the new index.
   Upstream deletes and renames builtins freely (the 2026-08 refresh removed 34
   builtins, `List.join_with` among them).
3. Add topics only for new areas of the language, and only for areas that an
   agent would otherwise get wrong.
4. Update `src/builtin_hints.ts` for renames. The suite fails on a hint key that
   does not name a real builtin.
5. Step 4 can show that a count changed because of growth, and not because of
   phantom methods (record fields that the parser read as methods). Then update
   the counts that the tests assert (`src/builtin_parser.test.ts`,
   `src/scopes.test.ts`, `src/resources.test.ts`). Also update the record in
   `corpus/language/UPSTREAM`. No page quotes these counts.

## Step 6: reconcile the server metadata

| Site | What goes out of date |
|---|---|
| `BUILTIN_TOPICS` in `src/topics.ts` | Descriptions and keyword lists for renamed or reversed syntax |
| `src/server.ts` tool descriptions | Claims about the language, as opposed to claims about the tool |
| `README.md` topic table | One row per topic file, and the builtin module list |
| `README.md` refresh section | The pinned commit and its link |
| `package.json` version | Increase it. The server reads its version from this field |
| `corpus/language/UPSTREAM` | The `compiler` line, always. When the language changed, also the commit, the date, the counts and any new path mapping |
| `corpus/platforms/<name>/UPSTREAM` | Only for the platform that changed: the tag, commit, hashes, module counts, and the `compiler` line of the new release |
| `corpus/packages/http/UPSTREAM` | Tag and hash, only when both platforms changed to the same new `roc-lang/http` release |
| `corpus/*/*/plugin.json` `release` | The tarball URL. It must match the repo, tag and tarball in `UPSTREAM`. `src/upstream.test.ts` asserts that they match |
| `corpus/*/*/index.json`, `plugins/*/index.json` | Run `npm run build:index` after any `release` changes. `check:index` fails until you run it. A plugin outside this repo runs `roc-syntax-mcp plugin index <dir>` |

`Builtin.roc` has no pre-built index, by design, for three reasons:

- It is not a release, so it has no hash to key a snapshot by.
- Its source must stay in the repo for the parser tests and for the Step 2 diff.
- A snapshot would save about 28 ms at startup (30 ms parse, 2 ms load). It
  would be about the same size as the file (804 KB against 848 KB).

Thus the full refresh of `Builtin.roc` is a new copy of the file.

Put argument semantics in parameter descriptions, not in tool descriptions. A
parameter description costs tokens only when a client calls the tool. A tool
description costs tokens on every `tools/list`.

## Step 7: gates

All of these must pass. They are the same gates as the baseline, so run them in
the same way and compare:

```bash
bun run check
node .claude/skills/refresh-roc-upstream/scripts/tool-cost.mjs   # not part of `check`
```

`check` reports a compiler-backed gate as skipped, not passed, when no `roc` is
on `PATH`. Thus the only passing result is a summary where every line is `ok`.
To find a single failure, run the gates one at a time, cheapest first:

```bash
npm run build              # tsc clean
npm test                   # all suites
npm run check:index        # every index.json equals its release
npm run check:roc          # every bundled .roc type-checks
npm run check:platforms    # every platform corpus and its scaffold
npm run check:roc-check    # roc_check end to end
npm run check:detection    # detection against the claude CLI
```

`npm run eval:agentic -- --arm=<label>` is not a gate. It uses real model tokens
and takes minutes. It answers questions that the gates cannot answer: whether
the model still calls `get_roc_syntax()` first, whether it narrows its queries, and
whether the Roc that it writes compiles. Run it when a refresh changes a tool
description, a footer, or the shape of a tool's output. Add the arm to
`docs/evals/agentic.md`.

`roc check` type-checks but does not run `expect`. Use `roc test` on each topic
file whose `expect` states a claim about values, not only about types:

```bash
{ cat corpus/language/topics/<name>.roc; printf '\nmain! = |_args| Ok({})\n'; } > /tmp/t.roc
$ROC test --no-color /tmp/t.roc
```

`reference/derived-content.md` lists what each test suite asserts and how to
read a failure. `src/resources.test.ts` asserts the 2800-token ceiling that the
tool-cost meter also measures. The meter adds a breakdown for each tool. Justify
any growth in that breakdown against the numbers recorded above.

After that, do spot checks by hand, through the running server and not the
source:

- `search_symbols` on a few names that the diff changed.
- `list_roc_index` for the full topic count.
- `get_roc_syntax` with a question in words, such as "sort list", that should
  point to topics, worked programs and symbols.

## Step 8: commit

Make two commits, or one squashed commit with two sections. The copied half and
the derived half are separate jobs, and a reader wants to know which job changed
a file. You can split copied from derived if that is clearer. Keep
`corpus/language/UPSTREAM` in the commit that changes the bundled nightly.

State the pinned commit in the subject. Quote the measurements, because they are
the reason to trust the refresh: item count, module count and tool-list token
cost.

Name every pin in the body, also the pins that did not change, in the form
`nightly <commit>, language <commit>, basic-webserver <tag> (unchanged,
rechecked), basic-cli <tag> (unchanged, rechecked)`. A pin that was checked
again and a pin that nobody checked look the same in a diff. The next refresh
must know which corpus was last measured against which compiler.

## Invariants

Keep these true in every refresh. Each one has a test. If you break one, fix the
content, not the test.

- No indexed builtin has an empty `modulePath`, and no two share a `fullName`.
- Every key in `src/builtin_hints.ts` names a builtin that exists.
- Every builtin and module named in `corpus/language/overview/` exists, and the
  builtins page quotes no counts.
- Every tool named in `corpus/language/overview/` is registered.
- `roc-syntax://builtin` serves an index, never the whole file.
- Both overview pages together stay under 3,400 tokens, at 3.5 characters per
  token. `language` stays under 1,800 and `builtins` under 1,600.
- Every tool carries `readOnlyHint`, so clients can skip the approval prompt.
- Doc comments in bundled `.roc` are `##`, never `# #`.
- `tools/list` stays under 2,800 tokens at 3.5 characters per token.
- Only `@modelcontextprotocol/server` and `zod` are runtime dependencies.
- `corpus/language/UPSTREAM` and every `corpus/platforms/<name>/UPSTREAM` name
  a nightly on a `compiler` line. Each `corpus/platforms/<name>/UPSTREAM` tag is
  the version that
  `src/scopes.ts` serves. Each platform's scaffold pins the tarball that its
  provenance file records.
- An address space holds at most one platform, because an app pins one platform.
  Thus the names that two platforms share never compete. For a name outside the
  space, the server returns no item and does not report the name as unknown. It
  reports the name as out of scope, with the `scope` value that reaches it. If
  no platform is pinned or requested, the space holds no platform. The server
  does not guess one and does not offer both.
- No tool declares an `outputSchema` or returns `structuredContent`. Claude Code
  gives the model that JSON and drops the text. The text holds every footer, the
  detection note and the markdown formatting. `docs/evals/agentic.md` has the
  measurement.
- Every scope value that a tool offers is one that the tool can act on.
  `roc_check` takes only a platform, because only a platform has an app to
  scaffold.
- Nothing third-party appears in `corpus/platforms/*/scaffold.roc`. If a package
  stops building, every check shows errors that the caller cannot fix.
