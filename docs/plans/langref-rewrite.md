# Plan: rewrite the langref into topics

## Status

| Phase | State |
|---|---|
| 1. Fix the errors that the inventory found in our pages | Done. `topics/loops.roc`, `topics/platforms.roc`, `overview/language.md` |
| 2. Gate: `roc test` on every topic, and checked `@rejects` / `@warns` claims | Done. `scripts/check-topics.roc`, called by `scripts/check-roc.sh` |
| 3. The section map, its test, and `scripts/langref-diff.roc` | Done. `corpus/language/langref-map.txt`, `src/langref.test.ts`, `--check-map` in `check:roc` |
| 4. Rewrite the langref ideas into topics | Done. 40 language topics, 30.7k to 48.0k tokens. 8 new topics. 86 checked claims and 130 top-level `expect`s |
| 5. Remove `get_roc_langref`, the langref hits of `search`, `list_roc_index(kind: "langref")`, the langref resource and the overlay | Done. `tools/list` is 2346 tokens for 8 tools |
| 6. Gates, text pass, eval arm | Done. All 7 gates pass. 391 tests pass. The `langref-topics` arm: 12/12 runs compile, `get_roc_syntax()` first in 12/12, $0.295 a run against $0.276 for `roc-module`, 7 topic reads against 4 |

## Decisions already made

| Decision | Source |
|---|---|
| Every non-trivial idea of `corpus/language/langref/` goes into a topic, as a comment, a definition or an `expect` | Maintainer |
| An `expect` can exist to show syntax. It must still pass `roc test` | Maintainer. The gate runs `roc test` |
| Churn on a langref refresh is acceptable. A script shows the prose diff between two pinned commits, grouped by the topics that carry each section | Maintainer |
| The langref stays in the repo as source. The server stops serving it | The diff script and the section map need the text at the pinned commit |

## Findings that shape the plan

Measured on 2026-10-09 with nightly `c34079d`. The langref is pinned at the same commit.

### Use

| Measure | Value |
|---|---|
| `get_roc_langref` calls in all local transcripts | 5. `roc_overview` and `get_roc_syntax` had 250 |
| `get_roc_langref` calls in 57 eval runs | 0 |
| Subjects of the 5 calls | Purity inference, where clauses, platform module headers, compile-time evaluation, platform scope. No topic covers them |
| Cost of `get_roc_langref` in `tools/list` | 203 of 2517 tokens |

### Size of the rewrite

Four agents read every page whole and listed its non-trivial ideas. The lists are in `langref-rewrite/inventory-g1.md` to `inventory-g4.md`.

| Pages | Ideas | Covered | To add | Estimate (tokens) |
|---|---|---|---|---|
| g1: modules, packages, platforms, comments-and-docs, README | 83 | 26, and 18 partly | 57 | 1715 |
| g2: static-dispatch, types, tag-unions, records, tuples, naming | 129 | 60 | 68 | 2400 |
| g3: numbers, strings, dictionaries-and-sets, iterators, loops, operators, parsers, if-else | 117 | 66 | 51 | 1460 |
| g4: functions, expressions, compile-time, statements, pattern-matching | 93 | 32 | 61 | 2250 |
| Total | 422 | 184 | 237 | 7825 |

| Form of the ideas to add | Count |
|---|---|
| Comment | 152 |
| `expect` | 48 |
| Definition | 27 |
| No code to attach to | 10 |

A pilot rewrote `functions.md` into `functions` and `effects`. It added 897 tokens, against an estimate of 560. So the real total is about 1.6 times the estimate, about 12.5k tokens, against 73k tokens of prose. The language topics grow from about 33k to about 46k tokens.

In the pilot, 1 of 3 claims that only a comment made was wrong. The comment said that a top-level effect is a "type mismatch". The compiler reports "effectful top level value". Phase 2 makes such claims checkable.

### Conflicts, checked with the compiler

| Claim | Langref | Our pages | Result |
|---|---|---|---|
| A second `foo = ...` in one scope | A warning | `topics/loops.roc:5` and `overview/language.md:15` imply an error | Langref is right: warning "duplicate definition" |
| `foo = foo + x` | Not mentioned | Not mentioned | Error "invalid assignment to itself" |
| Platform header | `platform "name"` | `overview/language.md:117` writes `platform [...]` | Ours is wrong: "expected platform name" |
| wasm32 target without `exports` | Rejected | `topics/platforms.roc:31` shows it | Ours is wrong: "missing wasm exports" |
| Literal pattern in `for` | Crashes at runtime | `topics/loops.roc:75` says compile error | Ours is right: "non exhaustive destructure" |
| Tag pattern in `for` (`for Ok(x) in xs`) | Type mismatch | Not mentioned | The compiler panics: "instantiation widened a closed tag union" |
| `types.md:76` top-level `items : List(a) where [...]` | Shown as valid | Not used | Error "polymorphic value" |
| `..[]` closed union | Shown, and marked as not parsing | `topics/idioms.roc:63` gives the nominal alternative | Does not parse |

Checked later, in phase 4 and after it:

| Claim | Langref | Our pages | Result |
|---|---|---|---|
| Field order of a record at the host boundary | `records.md:314`: by alignment, then by name | `topics/platforms.roc:193`: source order | The langref is right. `platform_abi` states it |
| Tuples always on the stack | `tuples.md:5` | `topics/records.roc:40`: the compiler chooses | The langref is right. Records and tuples are inline, with no allocation of their own |
| `roc test` runs the `expect`s of URL packages | `packages.md:90`: path packages only | `topics/testing.roc:3` | The langref is right |

## Design

### Checked claims in comments

A topic can state that some code is an error or a warning. The gate compiles that code and checks the title of the diagnostic.

```roc
# @rejects effectful top level value
# message = greet!("Sam")
```

| Rule | Meaning |
|---|---|
| `# @rejects <title>` | The block must give an error with this title |
| `# @warns <title>` | The block must give this warning and no error |
| The block | The comment lines after the marker, up to the first line that is not a comment or is a bare `#`. The gate removes `# ` from the start of each line |
| The prelude | The rest of the topic file, so a block can use the names the topic defines |

The marker stays in the served text. It tells the reader the exact title that the compiler prints.

### The section map

`corpus/language/langref-map.txt` has one line per langref page (its intro) and one per section (`page#slug`): the key, spaces, then the comma-separated topics that carry the ideas, or `skip: <reason>`.

A test fails when:
- a section of the pinned langref has no key;
- a key names a section that does not exist;
- a list names a topic that does not exist.

So an upstream refresh that adds a section fails the suite until someone maps it.

### `roc scripts/langref-diff.roc -- <roc checkout> [commit]`

The script is a Roc app on basic-cli.

1. Read the pinned commit from `corpus/language/UPSTREAM`.
2. Fetch each commit that the checkout lacks, so a `git clone --depth 1` is enough.
3. Split both versions of each page into sections, as `src/langref.ts` does, and match the sections by key, then by body.
4. Print each added, removed, changed or renamed section with its prose diff and the topics that the map names.

`--check-map` checks the map against `corpus/language/langref/`. `src/langref.test.ts` checks the same map against `src/langref.ts`, so the two parsers must agree.

On 2026-10-09, the report from `c34079d` to upstream `3ee70f0` had 104 changed, 89 added, 9 removed and 1 renamed section. Upstream added the pages `boxes`, `errors` and `lists` in those three days. A refresh starts from that report.

## Topic ownership in phase 4

Each agent owns a set of topic files, so no two agents edit one file. An idea whose target belongs to another set goes to its owner.

| Set | Topics |
|---|---|
| Types | `types`, `tag_unions`, `nominal`, `opaque`, `records`, `record_fields`, `tuples`, `static_dispatch`, `derived_methods`, `idioms`, NEW `naming` |
| Values | `numbers`, `ranges`, `strings`, `hashing`, `iterators`, `loops`, `operators`, `json`, `conditionals`, `try_operator`, NEW `dict_set` |
| Functions | `functions`, `effects`, `dbg_crash`, `testing`, `pattern_matching`, `list_patterns`, NEW `compile_time`, NEW `memory` |
| Modules | `imports`, `app_header`, `platforms`, `compiler`, `error_design`, `builder_pattern`, NEW `modules`, NEW `packages`, NEW `comments` |

The pilot's `recursion` content goes into `functions`. The inventory's `bindings` rows go into `naming`.

## Results of phase 4

Four agents rewrote the pages, each with its own set of topic files. Every claim that a comment makes about the compiler was tried in a scratch file first.

| Set | Pages | Topics, tokens before and after |
|---|---|---|
| Types | static-dispatch, types, tag-unions, records, tuples, naming | 7.3k to 12.6k. New: `naming` |
| Values | numbers, strings, dictionaries-and-sets, iterators, loops, operators, parsers, if-else | 9.2k to 13.6k. New: `dict_set` |
| Functions | functions, expressions, compile-time, statements, pattern-matching | 2.1k to 5.1k. New: `compile_time`, `memory` |
| Modules | modules, packages, platforms, comments-and-docs, README | 12.1k to 16.4k. New: `modules`, `packages`, `comments`. `platforms` split into `platforms` and `platform_abi` |

The total is 48.0k tokens against the 46k that the plan estimated. `src/topics.test.ts` holds every language topic under 3500 tokens, and `platforms` (3738) under 4000.

### Conflicts that the rewrite settled

| Claim | Langref | Our pages before | Compiler |
|---|---|---|---|
| `!x` calls `x.not()` | Yes (`operators.md:25`) | `overview/language.md:80` said yes | No. `!` takes only a `Bool`: "type mismatch" |
| `provides { "roc__entrypoint": ... }` | Shown (`modules.md:479`) | `topics/platforms.roc:25` used it | "invalid hosted section". The `roc__` prefix is reserved |
| Record field order at the host boundary | By alignment, then by name | `topics/platforms.roc` said source order | The langref is right (checked with glue). `_ : {}` in a nominal record keeps the declared order |
| `return` or `break` in a top-level `expect` | Errors | `topics/testing.roc` listed them for inline `expect`s only | "return in expect", "break in expect" |
| `roc test` and dependencies | Runs the `expect`s of path packages only | `topics/testing.roc:3` said "the files it imports" | The langref is right |
| `add_blue : [Red, Green, ..others] -> [Red, Green, Blue, ..others]` | Shown (`tag-unions.md:49`) | Not used | "type mismatch". The input must also list `Blue` |
| `..` is the same as `.._` | Yes (`tag-unions.md:89`) | Not used | `.._` does not parse |
| A top-level value with a free type variable | An error (`types.md:34`) | Not used | `top : List(a) = []` compiles. Only a kept `where` constraint gives "polymorphic value" |
| Underscores in number literals | A digit on both sides | Not used | `1__0`, `1_` and `0x_5` compile. Only `_1` fails |
| `var` and generalization | Never generalized | `naming` said one type from the first use | A `var` that holds `\|x\| x` works at two types. Each assigned value must have the same type |
| `List.with_capacity(123)` at top level | Keeps its capacity | Not used | A built binary has capacity 0. `roc test` reports 64 |
| `requires { ... }` | Not shown | Only `requires {} { ... }` | Both forms compile |
| `--replace-dep` | Also on `deps` | `topics/compiler.roc` left `deps` out | The langref is right |

### Claims the topics keep in the langref's modality

Nobody could check these with the compiler: the reference count is atomic, a failed allocation crashes, `List.set` copies a shared list, number sizes are the same on every target, a host can see the address of a value, the optimizer can remove effects in a host allocator, the runtime hash seed is random per run, and concurrency is planned.

The maintainer accepts these claims as comments in the topics.

### Where records and tuples live

The compiler source settles the stack question of `expressions.md:58` and `tuples.md:5`. In `src/layout/layout.zig` at `c34079d`, records and tuples share the `struct_` layout, an inline aggregate with fields stable-sorted by alignment. A struct has no allocation and no reference count of its own. `Store.layoutContainsRefcounted` in `src/layout/store.zig` counts a struct as refcounted only for the `Str`, `List` and `Box` values in it. A recursive tag union refers to itself through a box: "recursive back-edges are materialized as box layouts". `memory`, `records` and `tuples` state this. The langref is right.

### Compiler defects found

`bugs/` holds a minimal repro for each one, with the command, the expected result and the actual result. `bugs/README.md` lists them: 3 crashes, 8 places where the compiler differs from the langref, and 3 langref examples that do not compile.
