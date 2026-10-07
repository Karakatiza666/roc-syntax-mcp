# Plan: move the roc-parser corpus to 2.0.0

## Status

| Phase | State |
|---|---|
| 0. Baseline | Done. 7 gates `ok`, 85 files in `check:platforms`, tool cost 2768 |
| 1. Gate override for the Yaml.roc defect | Done. `scripts/check-platform-examples.sh`, `scripts/gate-overrides.json`, `src/gate_overrides.test.ts` |
| 2. A fresh corpus directory and index | Done. 270 items: 217 public, 52 private, 1 host |
| 3. Topics | Done. Six topics, 5.8 to 7.2 KB each |
| 4. Overview page and verify app | Done. 2583 chars, about 738 tokens |
| 5. Upstream examples | Done. 5 examples, one repin patch |
| 6. The `scripting` topic | Done |
| 7. Tests, docs and the server surface | Done |
| 8. Gates and the server, asked as a caller would | Done. See "Results" |
| 9. Commit | Done |

## Decisions already made

| Decision | Source |
|---|---|
| The corpus pins the 2.0.0 release URL, and reads as though 2.0.0 works | Maintainer. 2.0.1 replaces it later |
| A file that does not compile against 2.0.0 is checked against the build with the fix. The fixed build is never pinned in the corpus | Maintainer |
| Start a fresh directory. Nothing from the 1.1.0 corpus is kept as a base | Maintainer |
| The corpus condenses the 2.0 manual into topics, and links to the `.adoc` pages for the full text. The manual is not bundled | Maintainer. A package corpus cannot bundle `docs` anyway (`src/scopes.ts:559`, `PLATFORM_ONLY`) |

## Findings that shape the plan

Measured on 2026-10-08 with nightly `c34079d`, the newest nightly.

### The defect, and how far it reaches

| Fact | Evidence |
|---|---|
| `Yaml.roc:1` writes `import Parser exposing [Parser]`. This nightly rejects it as a redundant expose, an error | `roc check package/main.roc` at tag 2.0.0 |
| The compiler loads only the modules an app imports. So only an app that imports `parser.Yaml` fails | Of the 26 upstream apps, the 5 that import Yaml fail against the release. The other 21 pass |
| With the one-line fix, the whole package passes: check, 391 tests, docs, and the 26 apps against basic-cli 0.24.0 | Upstream's `scripts/all_tests.py`, after the fix |
| Upstream has the identical fix on branch `automation/roc-nightly` (PR #87, commit `d56ad0c`). The PR is not merged. Its fuzz jobs for HTTP segfault (exit 139) | `gh pr view 87` |
| The fixed package bundles to `HYfA3qcXJNCjCA8ai5bmwmraSp7XSLGCgGBQaNfB2z77.tar.zst`. A local `roc bundle` and upstream CI give the same hash | The CI artifact `release-bundles` of run 37384162379 |
| If upstream releases `d56ad0c` unchanged as 2.0.1, its tarball has that hash | Follows from the row above. Check it when 2.0.1 is published |
| An app header can pin a package by the absolute path of a local `main.roc`. The package's own `unicode` dependency still resolves | Tested with the extracted fixed bundle |

### What the gate and the tests require

| Constraint | Where | Effect on this plan |
|---|---|---|
| `check-platform-examples.sh` compiles every file in `examples` and `checks` exactly as written. It cannot substitute a URL | `scripts/check-platform-examples.sh:51-72` | Phase 1 adds the substitution |
| The package page must stay under 1000 tokens (chars / 3.5) | `src/scopes.test.ts:589` | The overview is a short index of the package, not a manual. The detail goes into topics |
| Every `Mod.fn` name on the page must be in the package index. Only `Entropy.seed_u32!` and `Json.parse` are exempt | `src/scopes.test.ts:592-597` | Do not name `Str.*` or other builtins on the page |
| Every line of a `roc` block on the page must be in a compiled app under `checks` | `src/scopes.test.ts:600-608` | `verify/overview-snippets.roc` holds them |
| A bundled package topic name is listed in the `search_roc_syntax` description in `tools/list` | `src/server.ts:447-456, 1274` | Every new topic name costs tokens |
| `tools/list` must stay under 2800 tokens. It costs 2768 | `src/resources.test.ts:339-344`, `tool-cost.mjs` | 32 tokens remain. See "Topic names and the budget" |
| A package corpus may declare `overview`, `topics`, `checks` and `examples`. It may not declare `docs`, `scaffold` or `handler` | `src/scopes.ts:559, 676-685` | The 5 upstream examples can ship as `examples` |
| `index.json` is built by `roc deps` from the release URL, then parsed | `scripts/build-index.ts`, `src/release.ts:204-305` | Indexing does not compile, so the Yaml defect does not affect it |

### The 2.0.0 index

Built in a scratch directory with the current indexer and loaded with `plugin inspect`:

| Measure | 1.1.0 | 2.0.0 |
|---|---|---|
| Modules | 8 | 9 (`Utf8` replaces `String`, `MarkdownEntities` is new) |
| Items | 125 | 270: 217 public, 52 private, 1 host |
| Dependencies | none | `unicode` 4.2.0, used only by Markdown |
| Duplicates, collisions | 0, 0 | 0, 0 |

No parser change is needed:

- The private types at the top level of `Markdown.roc` and `Xml.roc`, such as `Span` and `StartTag`, load as private.
- `MarkdownEntities` is not exposed, and it loads at host tier.

About 80 of the 217 public items are the decoding protocol: `CSV.Format.*`, `CSV.State`, `Yaml.Format.*` and `Yaml.Cursor`. The source makes them public, and static dispatch needs them. Their names look like user API: `CSV.Format.parse_str` exists, but 2.0 has no `CSV.parse_str`. The overview says this in one line, and the index follows the source.

### Stale statements in the upstream manual

The topics follow the source, not these pages. Each statement was checked against the compiler.

| Page | Says | Fact |
|---|---|---|
| `combinators.adoc` | Repetition needs the input type to support `==` | It needs `len` (`where [input.len : input -> U64]`) |
| `combinators.adoc` | `alt` joins all the messages with "or" | 2.0 keeps one failure: the furthest one, and on a tie the later one |
| `combinator-primer.adoc` | `parse_str` "returns one of three results" | Two: `Ok` and `Err(ParseError(...))` |
| `conformance.adoc:152` | HTTP methods are a closed union, and lowercase methods are rejected | `get` parses as `Extension("get")` |
| `modules.adoc` | Matching a non-ASCII character with `codeunit` is "not possible" | `Utf8.codeunit('é')` compiles, and matches only the byte `0xE9` |

## Topic names and the budget

Six topics share one prefix, so a model can tell the package from the name:

| Name | Chars with ", " | Tokens |
|---|---|---|
| `parser_combinators` | Already counted | 0 |
| `parser_csv` | 12 | 3.4 |
| `parser_yaml` | 13 | 3.7 |
| `parser_xml` | 12 | 3.4 |
| `parser_markdown` | 17 | 4.9 |
| `parser_http` | 13 | 3.7 |
| Total | 67 | about 19, so about 2787 of 2800 |

One topic per format keeps a read cheap. A question about CSV pays for CSV, not for Markdown. If the measured cost is over 2800, or leaves too little room, the fallback is one code change. Bundled package topics get the bounded enumeration that plugin topics already have (`fromPlugin`, `src/server.ts:429`). Then the package page names them, and keywords still find them. Do not merge topics only to save tokens.

## Phase 0: baseline

1. `export ROC=$PWD/roc_nightly-linux_x86_64-2026-10-06-c34079d/roc`
2. `npm run check`. Record the six result lines. Any failure here belongs to HEAD, not to this work.
3. `node .claude/skills/refresh-roc-upstream/scripts/tool-cost.mjs`. Record 2768.

## Phase 1: gate override for the Yaml.roc defect

The gate must check Yaml apps against 2.0.0 with the fix. The corpus must not change, and the gate must measure every other file against the real release.

### Data

`corpus/packages/roc-parser/patches/gate-0001-yaml-redundant-expose.patch` holds the upstream fix as a diff against the release tarball root (`Yaml.roc`, not `package/Yaml.roc`). The prefix `gate-` shows that the gate applies the patch, and that the patch never changes a served file.

`scripts/gate-overrides.json`:

```json
[
  {
    "release": "https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst",
    "patch": "corpus/packages/roc-parser/patches/gate-0001-yaml-redundant-expose.patch",
    "reason": "Yaml.roc:1 is a redundant expose on nightlies from 2026-10-04. Fixed upstream in d56ad0c (PR #87), not released",
    "until": "a roc-parser release that builds on the pinned nightly"
  }
]
```

### Mechanism in `scripts/check-platform-examples.sh`

| Step | Does |
|---|---|
| 1 | Compile each file as written, as the script already does |
| 2 | If it fails and the file pins a `release` from the overrides file, apply the override. Otherwise report the failure as the script already does |
| 3 | Get the release with `roc deps`, copy its cache directory into the gate's temporary directory, and apply the patch there |
| 4 | Write a copy of the file into the temporary directory, with the URL replaced by the absolute path of the patched `main.roc`. Compile the copy |
| 5 | Report `ok (override: <patch>)` or `FAIL`, under the original path. Diagnostic paths that point into the temporary directory are rewritten to the original file |
| 6 | The summary counts the files that needed an override, so the gate never passes one in silence |

Compile first, and apply the override only after a failure. Then the gate measures every non-Yaml file against the real 2.0.0. Also, the override stops applying when the corpus moves past 2.0.0: when 2.0.1 replaces the URL, no file pins the 2.0.0 release.

The overrides file is not in `package.json` `files`. So in an npm install, `plugin validate` measures a user's plugin against the real release, and the script must work when the file is absent.

### Tests

| Test | Proves | Validate by |
|---|---|---|
| Each override names a release that some corpus file pins, and a patch that exists | No stale override survives 2.0.1 | Point the release at an unused URL. The test must fail |
| The patch applies to the cached release | The data is right | Damage one context line. The test must fail (skip it when the release is not cached, as the compiler gates do) |
| With the override removed, `check:platforms` fails on the Yaml apps with "redundant expose" | The override is what makes them pass, and nothing else | Do this by hand once, and record it in the commit message |

## Phase 2: a fresh corpus directory and index

1. `git rm -r corpus/packages/roc-parser`, then create the directory again. Nothing is copied from 1.1.0.
2. `plugin.json`:

   | Field | Value |
   |---|---|
   | `release` | The 2.0.0 URL above |
   | `description` | "The roc-parser package: parser combinators, and parsers for CSV, YAML, XML, Markdown and HTTP/1.1 messages that decode into your own types." |
   | `purpose` | Keep "parsing text formats, on any platform". The test at `detect_server.test.ts:678` asserts it |
   | `overview` | `overview.md` |
   | `examples` | `examples` |
   | `checks` | `["topics", "verify"]` |
   | `topics` | The six below, each with a description written as a question and keywords that a question uses |

3. `UPSTREAM`:
   - The repository, tag `2.0.0`, tarball `7CLz...`, and `compiler nightly-2026-10-06-c34079d`.
   - The dependency on `unicode` 4.2.0.
   - The gate override and its exit condition.
   - The upstream commit of the manual that the links point at (`0c67c54`).
   - The examples and their repin patch.
   - The file roles.
4. `ROC=... npm run build:index -- corpus/packages/roc-parser`. Expect 270 items in 9 modules. Then `npm run check:index`.
5. `plugin inspect corpus/packages/roc-parser`. Expect 217 public, 52 private and 1 host item, and no duplicates.

## Phase 3: topics

Method: `.claude/skills/author-roc-plugin/reference/finding-traps.md`. Each topic is a complete app that pins basic-cli 0.24.0 and the 2.0.0 URL.

- Write it from the upstream example programs, then probe what they leave out. A trap goes in only if the compiler or a run proved it.
- Each trap is a comment at the line where it applies. `expect`s carry the claims about values, and `roc test` runs them.
- The header doc comment ends with the links to the full pages:
  `https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/<page>.adoc`.
- Target size: 4 to 7 KB. That is the range of the topics this repo already ships.

The research notes and probe apps are in the session scratch directory. The "Must teach" column holds a copy of the verified facts, so the plan does not depend on that directory.

| Topic | Must teach | Sources | Imports Yaml |
|---|---|---|---|
| `parser_combinators` | `Parser.const(\|a\| \|b\| ...)` with `.keep` and `.skip`: the function must be curried. `one_of` is ordered, so put the longer keyword first. `maybe` gives `Try(a, [Missing])`, and a stale `Err(Nothing)` is a non-exhaustive match. `sep_by` rejects a trailing separator. A failed element ends `many`, not the parse. `.map(...)` with `Try(_, Str)` then `.flatten()` validates. `Parser.lazy` builds recursion, with no left recursion. `and_then`. `Parser.custom`. `parse_str` against `parse_str_partial` (`{ value, rest }`). One error tag, `ParseError({ message, offset })`. Parsers read bytes, not characters. `digits` returns `U64`. `chomp_while`, `chomp_until` and `span` are in `Parser`. `Utf8.ByteClass` and `span_class` for speed. A line-based custom format with line numbers. No 1.x comparison: the doc comment says what each linked manual page covers | `combinator-primer`, `combinators`, `custom-format`, `errors`, `performance` (tips), `glossary` | No |
| `parser_csv` | `CSV.parse` into a record, where the annotation names `MissingRequiredField(Str)`. `Try(_, [Missing])` is an absent column. `Try(_, [Null])` is an empty cell. `parse_normalized`. `parse_headerless` into tuples. `parse_records` and `split_header` for raw bytes. `parse_with` with `record` and `field`. `InvalidCsv({ record, field, line, column, message })`. No trimming. Strict row width. The number grammar is data, not Roc literals. The separator is always `,`. A BOM is kept. The 2.0 changes that alter data in silence | `csv`, `choosing-an-approach`, `getting-started` | No |
| `parser_yaml` | `Yaml.decode` into a record. `Yaml.decoder({ keys: KebabCase, unknown_keys: Reject })` as a top-level constant. The tree: `parse_str`, `get_path`, `as_str` and `?` with `[Missing, WrongType]`. `Text`, not `String`. `InvalidYaml`. The YAML 1.2 core schema: `yes` and `no` are text. A scalar in the tree differs from the decoded value (`1.10`). `Int` is `I64`. Keys are source text. The list of rejected features | `yaml` | Yes, so it uses the override |
| `parser_xml` | `Xml.parse_str`, `xml.root`, `children_named`, `attribute ?? default`, `text()`. Matching on `Element({ name, attributes, children })` and `Text`. Whitespace text nodes. Only the 5 predefined entities, so use `&#160;`. DOCTYPE is rejected. No namespaces. What is normalised. `Xml.parser` stops at trailing input | `xml` | No |
| `parser_markdown` | `Markdown.parse_str` returns a list, with no `Try`. A renderer over `Markdown` and `Markdown.Inline`, with `level.to_str()`. A tight list still wraps its text in `Paragraph`, so check `loose`. A soft break stays `"\n"`. Escape the text you emit, and raw HTML passes through. Reference links resolve only in `parse_str`. `frontmatter` then `Yaml.parse_str` | `markdown` | Yes, for the frontmatter. It uses the override |
| `parser_http` | `HTTP.parse_request(text.to_utf8())?`, which takes bytes. `HTTP.header(headers, "content-type") ?? ...`. `rest` and pipelining. `parse_requests`. `HTTP.request` inside a `Parser`. `InvalidHttp({ offset, message })`. Methods are case-sensitive, so a match needs `Extension(name)`. The framing rules. What is rejected against smuggling. No size limits | `http` | No |

`detect_server.test.ts:686` asserts that the `parser_combinators` text contains `Parser.lazy`. Keep it.

## Phase 4: overview page and verify app

A model reads the overview before it writes code. The page must stay under 3500 characters.

| Part | Content |
|---|---|
| Title | `# roc-parser 2.0.0` |
| Header | One `roc` block: the basic-cli 0.24.0 and parser 2.0.0 pins, and `import parser.Utf8` and `import parser.Parser` |
| Module map | A table: module, what it gives, the entry call, the topic |
| The 2.0 style | Methods on parsers and trees. Errors are open tags named after the format, so `?` composes them. Optional values are `Try(_, [Missing])`. Decoding takes its type from the annotation. `Utf8` replaces `String` |
| Traps | The six that cost the most: a curried `const`, `parse_str` is a full parse, `sep_by` and a trailing separator, `Markdown.parse_str` returns no `Try`, HTTP takes `List(U8)`, and `MissingRequiredField(Str)` in the annotation |
| Protocol line | `Format`, `State` and `Cursor` are the decoding protocol. Never call them |
| Manual | One link to `https://github.com/lukewilliamboswell/roc-parser/tree/2.0.0/docs` |

`verify/overview-snippets.roc` is one app that holds every line of every `roc` block on the page, and it does not import Yaml. `scopes.test.ts:600-608` then passes without the override.

## Phase 5: upstream examples

Bundle the 5 programs in `examples/` of the release examples archive: `csv-movies`, `letters`, `markdown`, `numbers` and `xml-svg`. A caller reads them as `roc-syntax://package/roc-parser/example/<name>`.

| Step | Detail |
|---|---|
| Source | `roc-parser-examples-2.0.0.zip`, which pins the 2.0.0 URL and basic-cli 0.23.0 |
| Repin | `patches/0001-repin-examples-to-basic-cli-0.24.0.patch`. Change only the platform line. basic-cli 0.23.0 fails on this nightly with the same redundant-expose error, 13 times |
| Gate | None of the 5 imports Yaml, so all compile against the real release with no override. Measured: all 5 pass |
| Licence | `REUSE.toml` gets an annotation for `corpus/packages/roc-parser/examples/**` (UPL-1.0, © 2023 Luke Boswell and subsequent authors). `THIRD-PARTY-NOTICES.md` gets a row |

The 21 programs in `docs/examples/` are not bundled. They are the sources of the topics.

## Phase 6: the `scripting` topic

`corpus/platforms/basic-cli/topics/scripting.roc` pins roc-parser and imports `CSV`, `Parser`, `String` and `Yaml`.

| Lines | 1.1.0 | 2.0.0 |
|---|---|---|
| 20 | The 1.1.0 URL | The 2.0.0 URL |
| 33 | `import parser.String` | `import parser.Utf8` |
| 84-93 | `CSV.record`/`field` against `CSV.CSVRecord`, then `CSV.parse_str` with `ParsingFailure`, `SyntaxError` and `ParsingIncomplete` | `CSV.parse` into a `Sale` record, with `[InvalidCsv(CSV.Error), MissingRequiredField(Str)]`. That is the 2.0 idiom, and it is shorter |
| 124-146 | `Yaml` tree tags `String`, `Mapping`, `Int` and `Null`. `YamlError(err)` | `Text` in place of `String`, and `InvalidYaml(err)`. Or `Yaml.decode` into a record, if that reads better in a script |
| 155-168 | `String.Utf8`, `String.digits`, `String.one_of`, `String.string`, `String.parse_str` | `Utf8.Bytes`, `Utf8.digits`, `Parser.one_of`, `Utf8.string`, `Utf8.parse_str` |

It imports Yaml, so the gate checks it with the override.

In `src/topics.ts:241-286`, the `scripting` entry: change the description to name the 2.0 calls, and remove the keywords that belong to a format topic after this change: `xml`, `parse xml`, `markdown`, `parse markdown` and `multi-format`. Keep `csv` and `yaml` only if a query for them should still reach a script. Phase 8 decides this by asking the server.

## Phase 7: tests, docs and the server surface

| File | Change |
|---|---|
| `src/scopes.test.ts:731-745` | `PACKAGE_DOCS` and `HOST_PACKAGES` get version 2.0.0 and hash `7CLz...` |
| `src/detect_server.test.ts:685, 687` | `roc-parser 2.0.0` |
| `src/resources.test.ts:521-536` | No edit. The topic count follows the files |
| `README.md:203-206, 262-265` | The topic table gets `roc-parser (6)` and the six names. The package table gets 2.0.0 and its description |
| `CONTRIBUTING.md:28, 82` | Mention examples and the gate override |
| `REUSE.toml`, `THIRD-PARTY-NOTICES.md` | The examples, see Phase 5 |
| `.claude/skills/refresh-roc-upstream/SKILL.md:41, 82-83` | Remove "held at 1.1.0". Say that 2.0.0 is served, and that `scripts/gate-overrides.json` is checked on every refresh and its entry removed when it is no longer used |
| `.claude/skills/refresh-roc-upstream/SKILL.md:47` | The new tool cost |
| `docs/design/packaging.md` or `docs/design/plugins.md` | One paragraph on gate overrides: what they are, why they never reach a served file, and why they do not ship |

## Phase 8: gates, and the server asked as a caller would

1. `npm run check`, all six lines `ok`. The summary of `check:platforms` names the files that needed the override, and only the Yaml apps are in it.
2. `roc test` on each topic, because `roc check` does not run `expect`.
3. `tool-cost.mjs` stays under 2800. Record the number.
4. `plugin validate corpus/packages/roc-parser`. The `name` failure is expected for a bundled corpus. Every other line must be `ok`.
5. Start a server from a workspace whose app header pins basic-cli and roc-parser 2.0.0, and from one that pins no package. Ask:

   | Ask | Expect |
   |---|---|
   | `search_roc_syntax("roc-parser")` | The page, then "Topics: ..." with six names and "Examples: ..." with five |
   | `search_roc_syntax("parse csv")`, `("yaml config")`, `("xml")`, `("markdown to html")`, `("http request")` | The matching `parser_*` topic, not `scripting` |
   | `search_roc_syntax("utf8")`, `("parser combinator")` | `parser_combinators` |
   | `lookup_builtin("Utf8.parse_str")`, `("CSV.parse")`, `("Yaml.decode")` | One answer each |
   | `lookup_builtin("String.parse_str")` | A miss. The 1.x name is gone |
   | `roc_overview` | The catalogue line for roc-parser is unchanged |

## Phase 9: commit

One commit, because the corpus, the gate override and the tests only pass together. The body states:

- The pins: nightly `c34079d`, roc-parser 2.0.0 with the gate override for `Yaml.roc`, basic-cli 0.24.0 (unchanged).
- The measurements: 270 items in 9 modules, 6 topics, 5 examples, the tool cost.
- The validation by reversion: without the override, the Yaml apps fail with "redundant expose".

## Results

Measured on 2026-10-08, nightly `c34079d`.

| Gate | Result |
|---|---|
| `npm run check` | 7 of 7 `ok` |
| `check:platforms` | 96 files pass. 3 pass through the override: `parser_yaml`, `parser_markdown` and `scripting` |
| The same, with `scripts/gate-overrides.json` moved away | Those 3 fail with "redundant expose" at `Yaml.roc:1:25`. The other 93 pass |
| `src/gate_overrides.test.ts` | Fails when the release is changed to one no file pins, and when a context line of the patch is damaged |
| `roc test` | Every topic, the verify app and `scripting` pass. A changed value in a copy fails each new `expect` that was checked |
| `plugin validate` | All `ok`, except `name`, which is expected for a bundled corpus |
| `tool-cost.mjs` | 2787 of 2800 |

What the server answers, from a workspace that pins the package and from one that does not (the same in both):

| Ask | Answer |
|---|---|
| `search_roc_syntax("roc-parser")` | The page, then six topics and five examples |
| "parse csv", "csv", "yaml config", "read yaml", "xml", "markdown to html", "frontmatter", "chunked", "parse raw http request bytes" | The matching `parser_*` topic |
| "utf8", "parser combinator", "write a parser for my own format", "tokenize" | `parser_combinators` |
| "http request", "make an http request", "http response" | `cli_http`, as before this change |
| `lookup_builtin` on `Utf8.parse_str`, `CSV.parse`, `Yaml.decode` | One answer each, from roc-parser 2.0.0 |
| `lookup_builtin("String.parse_str")` | A miss |

Changes made while measuring:

| Change | Why |
|---|---|
| Topic descriptions cut to about 190 characters | `get_roc_syntax` lists every topic with its description on a miss, and `src/resources.test.ts:571` limits that answer to 6000 characters |
| `parser_http` lost `HTTP.request`, `http request`, `http response` and the keywords that contain them | `matchTopic` returns a topic when one of its keywords contains the whole query (`src/topics.ts:562`), so "http request" left `cli_http` |
| `parser_combinators` got `format`, `own format`, `custom format` | "write a parser for my own format" answered `derived_methods` |
| `parser_yaml` got `read yaml`, `load yaml`, `yaml file` | "read yaml" answered `cli_files` on a tie |

A finding for the overview, from the verify app: `import parser.Parser exposing [Parser]` in an app is the same redundant-expose error as the one in `Yaml.roc`.

## Moving to 2.0.1 later

One search must find every place where the corpus says 2.0.0:

```bash
grep -rnE 'roc-parser/releases/download/2\.0\.0|roc-parser/(blob|tree)/2\.0\.0|roc-parser 2\\?\.0\\?\.0|Package \| 2\.0\.0|7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW' \
  --exclude-dir=node_modules --exclude-dir='roc_nightly-*' --exclude-dir=tmp --exclude-dir=dist .
```

`roc-parser 2\\?\.0` also finds `src/detect_server.test.ts`, which writes the version as a regex. Two hits describe history and are not pins: the paragraph in `docs/design/plugins.md` and the one in the refresh skill. Rewrite them by hand, and do not apply a substitution.

| Step | Detail |
|---|---|
| 1 | Replace the URL, the hash and the version in every hit. If 2.0.1 is `d56ad0c` unchanged, its hash is `HYfA3qcXJNCjCA8ai5bmwmraSp7XSLGCgGBQaNfB2z77` |
| 2 | Point the manual links at the new tag, and diff `docs/` between the tags for new content |
| 3 | Remove the override entry and the `gate-0001` patch. The test in Phase 1 fails until both are gone |
| 4 | `npm run build:index`, then `npm run check` |
