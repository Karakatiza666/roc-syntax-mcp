# Inventory g1: modules, packages, platforms, comments-and-docs, README

Pages read whole: `corpus/language/langref/{modules,packages,platforms,comments-and-docs,README}.md`.
Coverage checked against `corpus/language/topics/*.roc`, `corpus/language/overview/*.md`, and (for the shebang) `corpus/platforms/basic-cli/topics/scripting.roc`.
Claims marked "verified" were run with `roc_nightly-linux_x86_64-2026-10-06-c34079d/roc` in scratch files that are not kept.

"HDR" in the form column: the idea is about a module header or about more than one file. A topic file is a single headerless app module, so the idea can only be shown as a comment unless a separate example file (or example package directory) is added.

## Ideas

| section (page#slug) | idea, max 20 words | covered | form | target topic | est. tokens to add |
| --- | --- | --- | --- | --- | --- |
| modules#type-modules | Capitalized file `Url.roc` must define top-level nominal `Url :=` or `Url ::`; that one type is exposed | overview/language.md:116-117 | comment (HDR) | imports | 0 |
| modules#type-modules | A type alias `Url : ...` does not count; importing gives error "type module requires nominal type" (verified) | none | comment (HDR) | NEW:modules | 35 |
| modules#hiding-implementation-details | Importers see only the module's type and its associated items; other top-level types, functions, constants stay private (verified) | none | comment (HDR) | NEW:modules | 50 |
| modules#hiding-implementation-details | Expose extra types/functions by nesting them in the type's `.{ }` block, reached as `Url.ParseErr`, `Url.from_str` | overview/language.md:111 (import only) | expect | NEW:modules | 80 |
| modules#hiding-implementation-details | Nesting goes arbitrarily deep (`Url.ParseErr.Foo.blah`); `import ... as` flattens it | imports.roc:36-39 (partial) | expect | NEW:modules | 50 |
| modules#alias-modules | Alias modules (`ParseErr : Url.ParseErr` in its own file) are designed but not implemented yet | imports.roc:65-66 | comment (HDR) | imports | 0 |
| modules#alias-modules | Convention: keep type-specific errors nested and qualified (`Url.ParseErr`, `CString.NulError`), not generic top-level names | none | code | error_design | 40 |
| modules#void-modules | A bag of functions is a void module: `Util :: [].{ ... }`, called as `Util.f(x)` (verified in an app) | platforms.roc:138-139 (platform convention only) | expect | NEW:modules | 60 |
| modules#void-modules | Use `[]` not `{}` as backing: it cannot be instantiated even inside the module, so it is a pure namespace | none | comment | NEW:modules | 30 |
| modules#void-modules | Constants with no natural owner type go on a void module's type | none | comment | NEW:modules | 15 |
| modules#rust | No private methods and no `pub`: every `.{ }` item is public; private helpers go at top level | none | code | NEW:modules | 40 |
| modules#elm | `import Url` brings the type itself; `Url.foo` and `Url -> Bool` both name the type; no `exposing (Url)` | imports.roc:8 (partial) | comment | imports | 30 |
| modules#roc | Import cycles between modules are rejected; mutually referencing code must share one file. Reason: per-module caching | none | comment (HDR) | NEW:modules | 50 |
| modules#roc | Packages also cannot depend on each other cyclically | none | comment (HDR) | NEW:packages | 15 |
| modules#import-statements | `import` only at top level, imports only types, only from type modules | imports.roc:3-5 | comment | imports | 0 |
| modules#exposing | `exposing [to_str, Request]` brings associated functions and nested types in unqualified | imports.roc:12-16 | comment | imports | 0 |
| modules#modules-in-subdirectories | `/` selects a source file, `.` a nested type; `./`, `../`, leading `/` bases; `as` never changes the file | imports.roc:22-34, overview/language.md:111 | comment | imports | 0 |
| modules#modules-in-subdirectories | A package exposes a subdirectory module by listing its import alias: `package [Widget] {}` plus `import Src/Widget as Widget` | none | comment (HDR) | imports | 40 |
| modules#modules-in-subdirectories | Directory traversal is private to the package; consumers use the public name | imports.roc:44-45 | comment | imports | 0 |
| modules#importing-mutually-recursive-types | Mutually recursive types live together in a void module `FooBar`; `import FooBar.Foo` for unqualified use | imports.roc:54-64 | comment (HDR) | imports | 0 |
| modules#module-headers | Type modules have no header (filename decides); package, platform and app modules have headers | overview/language.md:116-118 | comment (HDR) | imports | 0 |
| modules#package-modules, packages#packages | `package [Parser, Encoder] { json: "..." }`, root usually `main.roc`, lists exposed type modules and deps | overview/language.md:117-118 (form only) | comment (HDR) | NEW:packages | 40 |
| packages#packages | Modules not listed in `package [...]` are importable inside the package only | none | comment (HDR) | NEW:packages | 25 |
| modules#package-modules | A package can name `pf: platform "..."`, use its whole API incl. hosted effects, but never satisfies `requires` | app_header.roc:72-75 | comment (HDR) | app_header | 0 |
| modules#package-modules | All platform declarations must be identical: no compatible-version upgrade; local paths must resolve to the same root file | app_header.roc:73-74 (partial: URL only) | comment (HDR) | app_header | 30 |
| modules#platform-modules | Header sections `requires exposes packages provides hosted targets` and what each does | platforms.roc:21-48 | comment (HDR) | platforms | 0 |
| modules#requires | `requires { main : ... }` (one record) and `requires {} { main! : ... }` both compile (verified); topics show only the second | platforms.roc:22 (one form) | comment (HDR) | platforms | 30 |
| modules#requires | `[Model : model] for main : {...}` lets the app supply a type that stays opaque to the platform | platforms.roc:62-82 | comment (HDR) | platforms | 0 |
| modules#targets | `output` is `Exe` (default), `Shared`, `Archive`; platform, not app, picks it; first compatible target is default; input order matters | platforms.roc:45-60 | comment (HDR) | platforms | 0 |
| modules#targets | Linked wasm32 targets must list `exports: [...]` (`exports: []` for none), else build error "missing wasm exports" (verified) | none (platforms.roc:31 omits it) | comment (HDR) | platforms | 35 |
| modules#hosted-type-modules | Hosted function = annotation with no body in the type's `.{ }`, bound by `hosted { "sym": Mod.fn! }` | platforms.roc:43-44, 114-118 | comment (HDR) | platforms | 0 |
| modules#hosted-type-modules | Hosted functions must be effectful (`=>`), since compile-time evaluation cannot run host code | none | comment (HDR) | platforms | 25 |
| modules#hosted-type-modules | Every hosted declaration must appear in the header's `hosted` section | platforms.roc:317-318, 387 (partial) | comment (HDR) | platforms | 15 |
| modules#hosted-type-modules | Type variables in a hosted signature may appear only inside `Box(...)`, which is always a pointer | none | comment (HDR) | platforms | 35 |
| modules#application-modules | `app [main!] { pf: platform "...", json: "..." }`: exposed entrypoints plus deps record with exactly one `platform` | app_header.roc:64-67 | comment (HDR) | app_header | 0 |
| modules#pinning-a-roc-version | Any app/package/platform header may pin the compiler with a reserved `roc: "nightly-..."` entry | none | comment (HDR) | compiler | 35 |
| modules#pinning-a-roc-version | Pin value is a `roc version` string: nightly tag or release like `0.1.0`; `roc` cannot be a shorthand | none | comment (HDR) | compiler | 25 |
| modules#pinning-a-roc-version | A mismatched pin is a warning (exit 2), not an error (verified) | none | comment (HDR) | compiler | 15 |
| modules#pinning-a-roc-version | `roc fmt` refreshes a nightly pin to a newer running nightly; release pins are left alone; `--check` flags stale pins | compiler.roc:81-82 (no release rule) | comment | compiler | 15 |
| modules#nominal-type-identity-across-packages | Nominal identity = declared name plus byte-identical declaring module content, recursively through its imports | none | comment (HDR) | NEW:packages | 40 |
| modules#nominal-type-identity-across-packages | Unchanged module across versions, mirrors, vendored copies gives the same type; any change gives a new distinct type | none | comment (HDR) | NEW:packages | 40 |
| modules#nominal-type-identity-across-packages | Exception: `hosted` functions and `provides` entrypoints are identified by header symbol strings, not content | none | comment (HDR) | platforms | 25 |
| modules#headerless-application-modules | Headerless file gets the Echo platform with unqualified `echo!`; `main!` gets `List(Str)` | app_header.roc:1-36, overview/language.md:99-106, 118-119 | comment | app_header | 0 |
| modules#headerless-application-modules | `app [main!] { pkg: "..." }` with no platform still gets Echo; `app [main!] {}` equals no header | app_header.roc:7-10, 38-50 | comment (HDR) | app_header | 0 |
| modules#headerless-application-modules | Echo is intentionally minimal and not for production (no favoritism, no versioning) | app_header.roc:35-36 | prose-only | app_header | 0 |
| packages#depending-on-packages | Each dependency is `shorthand: "location"`; location is an HTTPS URL or a filesystem path | app_header.roc:66-67 (URL only) | comment (HDR) | NEW:packages | 20 |
| packages#url-packages | URL package is a `.tar.zst` over HTTPS; plain HTTP only for `localhost`; downloads are cached | none | comment | NEW:packages | 30 |
| packages#url-packages | Last URL segment is the content hash; Roc verifies it and refuses a mismatch, so a URL is immutable | compiler.roc:106-107 (naming only) | comment | NEW:packages | 30 |
| packages#url-packages | `roc bundle main.roc A.roc ...` writes a hash-named bundle to upload to any static HTTPS host | compiler.roc:106-107 | comment | compiler | 0 |
| packages#package-versions | Version `MAJOR.MINOR.PATCH` may appear anywhere in the URL before the hash, only once | none | comment | NEW:packages | 20 |
| packages#package-versions | Resolution: different majors both kept; same major takes the highest; for `0.x` the minor acts as major | none | comment | NEW:packages | 45 |
| packages#package-versions | App's own deps are exact; a transitive need for a higher version is an error showing the chain | none | comment | NEW:packages | 35 |
| packages#package-versions | URLs with no version never unify; each is a separate package | none | comment | NEW:packages | 15 |
| packages#package-versions | `roc bump` reports the needed semver bump from the public API diff | compiler.roc:108-110 | comment | compiler | 0 |
| packages#path-packages | Path dependency points at a package's `main.roc`, relative to the declaring module; never downloaded, cached, versioned | none | comment (HDR) | NEW:packages | 25 |
| packages#path-packages | `roc test` runs `expect`s in path packages but not in URL packages | testing.roc:3-4 (partial, "files it imports") | comment | testing | 20 |
| packages#shorthands | Shorthand is a lowercase name without `$` or `!`; `roc` is reserved | none | comment (HDR) | NEW:packages | 20 |
| packages#shorthands | Dependent picks the shorthand; it is scoped to the declaring header, so two packages may name one dep differently | none | comment (HDR) | NEW:packages | 30 |
| packages#inspecting-dependencies-with-roc-deps | `roc deps` prints the graph without compiling; edges show the full URL/path, never the shorthand | compiler.roc:88, 97 | comment | compiler | 0 |
| packages#inspecting-dependencies-with-roc-deps | Tree markers: `[shared]`, `[resolved to URL]`, `[replaced by ...]` | none | comment | compiler | 35 |
| packages#replacing-dependencies-with---replace-dep | `--replace-dep OLD NEW` on run/build/check/test/docs/deps, repeatable, one invocation, never edits files or cache | compiler.roc:89-93 (no `deps`, no "never edits") | comment | compiler | 10 |
| packages#replacing-dependencies-with---replace-dep | Match is exact incl. version and hash, everywhere incl. inside other packages; each release needs its own flag | compiler.roc:90 (partial) | comment | compiler | 25 |
| packages#replacing-dependencies-with---replace-dep | A flag that matches nothing is an error; a shorthand in place of a URL/path is an error | none | comment | compiler | 20 |
| packages#replacing-dependencies-with---replace-dep | The replacement's own header decides its deps, and the same flags apply to them | none | comment | compiler | 15 |
| platforms#platforms | Every app has exactly one platform; the platform, not the standard library, provides all I/O | overview/language.md:4, app_header.roc:68-69, platforms.roc:3-5 | comment | platforms | 0 |
| platforms#domain-specific-functionality | A platform can wrap one existing codebase so Roc is embedded in it (Vendr, roc-esbuild) | none | prose-only | platforms | 25 |
| platforms#ecosystem-benefits | I/O mismatches (blocking stdin on a server, file I/O in a browser) fail at build time | none | prose-only | platforms | 35 |
| platforms#security-benefits | Platform has exclusive I/O control, so it can enforce domain security (prompts, sandboxing) with no escape hatch | none | prose-only | platforms | 30 |
| platforms#security-benefits | Roc has no FFI of its own; calling other languages needs a platform-provided primitive | none | comment | platforms | 20 |
| platforms#performance-benefits | Platform may schedule concurrent I/O with domain knowledge; not yet practical (work in progress) | none | prose-only | platforms | 30 |
| platforms#host | Platform = Roc API (modules apps see) + host (non-Roc implementation); `provides` maps link symbols | platforms.roc:8-13, 41-42 | comment | platforms | 0 |
| platforms#memory-management | Host supplies allocation functions; enables per-request arenas where free is a no-op | platforms.roc:313-316 | comment | platforms | 0 |
| platforms#program-start | Host starts first and owns `main()`; the app is like a C library the host calls any number of times, or never | platforms.roc:9, 311-312 (partial) | comment | platforms | 25 |
| platforms#program-start | `roc build` compiles the app to an object and links it with the platform's prebuilt host binary | platforms.roc:10-11, 45-47 | comment | platforms | 0 |
| comments-and-docs#comments | `#` runs to end of line; there is no block or multi-line comment syntax | overview/language.md:17 (partial) | comment | NEW:comments | 15 |
| comments-and-docs#single-line-comments | The compiler gives comments no meaning; editing them changes only stack-trace locations | none | comment | NEW:comments | 15 |
| comments-and-docs#shebang-comments | `#!/usr/bin/env roc` on line 1 is an ordinary comment, so a script still compiles (verified) | basic-cli/topics/scripting.roc:10 | comment | NEW:comments | 0 |
| comments-and-docs#doc-comments | Doc comment = consecutive `## ` lines directly before a definition; otherwise it is an ordinary comment | overview/language.md:17 (partial) | code | NEW:comments | 40 |
| comments-and-docs#doc-comments | Doc comment text is Markdown | none | comment | NEW:comments | 10 |
| comments-and-docs#code-blocks-in-doc-comments | Code blocks in doc comments are never checked or run; add a real top-level `expect` too | idioms.roc:148-154 (partial) | expect | NEW:comments | 35 |
| comments-and-docs#autolinks | `[Str]`, `[Str.concat]`, `[Greeting.from_str]` autolink to docs (module, package, builtins); bare names only (compiles, verified) | none | code | NEW:comments | 45 |
| comments-and-docs#generating-docs-with-roc-docs | `roc docs main.roc` writes `generated-docs/` (`--output=`), `--serve` on localhost:8080; one page per exposed module | compiler.roc:104-105 | comment | compiler | 0 |
| comments-and-docs#bidirectional-controls | Comments and doc comments must not contain literal Unicode bidi controls (CVE-2021-42574); write `U+202E` instead | none | comment | NEW:comments | 30 |

## (a) Disagreements

| # | langref / reference says | topics / overview says | evidence |
| --- | --- | --- | --- |
| 1 | Platform header is `platform "name"` (langref/modules.md:475, 576; platforms.roc:21) | overview/language.md:117-118: "`platform [...]` head[s] the other module kinds" | Verified: `platform [Foo]` gives "expected platform name". The overview is wrong. |
| 2 | Linked wasm32 targets must list `exports` (langref/modules.md:538, 544-545) | platforms.roc:31 shows `wasm32: { inputs: ["host.wasm", app], output: Shared }` with no `exports` | Verified: `roc check` passes, `roc build --target=wasm32` fails "missing wasm exports". The topic example is wrong. |
| 3 | Doc comment lines start with `## ` "at the very beginning of the line" and must be followed by an assignment (langref/comments-and-docs.md:38-41) | builder_pattern.roc:28-31 indents `##` inside a `.{ }` block and puts it before an annotation; Builtin.roc does this 9784 times (42 at column 0). Langref's own example at comments-and-docs.md:79-82 also precedes an annotation | Langref rule is too narrow in practice. Not verified with `roc docs` (my scratch package generated an empty index). Also testing.roc:10 puts `##` before an `expect`, which by the rule is a plain comment. |
| 4 | `roc test` runs `expect`s of path packages only, not of URL packages (langref/packages.md:90-91) | testing.roc:3-4: "runs every top-level `expect` in that file and the files it imports" | Not a contradiction for local imports, but the topic implies dependencies too. Not verified. |
| 5 | `--replace-dep` works on run, build, check, test, docs and deps (langref/packages.md:142-143) | compiler.roc:92-93 lists check, test, run, build and docs | Omission only (`deps` missing). |
| 6 | Langref one-liners `main! = |_args| echo!("Hello, World!")` (modules.md:685) and `main! = |_| { Stdout.line!("Hello!") }` (modules.md:602-604) | app_header.roc:24-27 says the Echo one-liner does not type-check and adds `Ok({})` | Topic already flags the Echo case. modules.md:602-604 has the same bug, not flagged. |
| 7 | Langref is self-inconsistent on `Stdout.line!`: `line! : Str => {}` (modules.md:568) vs `Stdout.line!("...")?` (platforms.md:15) | app_header.roc:60 uses neither `?` nor `_ =` | Depends on the template-zig release; not verified (no corpus for that platform). |
| 8 | Void module advice says back it with `[]` (modules.md:96-102), but the FooBar example uses `FooBar :: {}.{` (modules.md:348) | imports.roc:58 copies `FooBar :: {}.{` | Langref internal inconsistency carried into the topic. |
| 9 | `requires { main : ... }` single record (modules.md:476, 488) | platforms.roc:22 and app_header.roc:32 use `requires {} { main! : ... }` | Both compile (verified). Not a conflict, but no topic says both forms are valid. |

## (b) Skipped as trivial

| page#section | skipped | what |
| --- | --- | --- |
| modules (intro) | 2 | modules exist for namespacing and hiding; four module kinds summary |
| modules#elm, #rust | 4 | Elm/Rust module comparisons as history (Rust `ffi` examples, Elm `exposing` habits) |
| modules#design-notes-on-imports | 2 | "mutually recursive types are rare, so extra effort is accepted"; long build-time argument (kept as one reason in the cycle row) |
| modules#importing-types-from-packages | 1 | restates `pf.` / `json.` prefixes |
| modules#importing-constants | 1 | `Color.all` reached through the type (covered by exposing row) |
| modules#exposes, #packages, #provides | 3 | one-line restatements of each header section |
| modules#package-shorthands | 1 | restates shorthand use in imports |
| modules#headerless-application-modules | 2 | wasm args are "arbitrary arguments from the outside world"; Echo teaches beginner concepts |
| packages#platforms | 1 | restates "one platform per app" |
| platforms#applications | 1 | Hello World walkthrough |
| platforms#domain-specific-functionality | 3 | game engine / web server / GUI / Vim / robot examples |
| platforms#memory-management | 1 | memory diagnostics benefit from a talk |
| platforms#program-start | 1 | small/large platform vs app size combos |
| platforms#summary | 1 | recap of the page |
| platforms (end) | 1 | list of example platforms |
| comments-and-docs#single-line-comments | 1 | end-of-line comment example |
| comments-and-docs#autolinks | 1 | ordinary Markdown links still work |
| comments-and-docs#generating-docs-with-roc-docs | 2 | static site can be hosted anywhere; search box |
| README | 3 | WIP banner, pointer to the tutorial, outline of ~150 links (outline lists `continue`; statements.md:300 and overview/language.md:126 agree it is not implemented, verified) |

## Totals

Computed from the Ideas table with awk.

| measure | count |
| --- | --- |
| ideas (rows) | 83 |
| already covered (0 tokens to add) | 26 |
| partially covered (tokens > 0, covered column not "none") | 18 |
| not covered | 39 |
| rows to add | 57 |
| to add, form expect | 4 rows, 225 tokens |
| to add, form code | 4 rows, 165 tokens |
| to add, form comment | 45 rows, 1205 tokens |
| to add, form prose-only | 4 rows, 120 tokens |
| of the rows to add, HDR (header or multi-file, comment only unless an example file is added) | 23 |
| estimated tokens to add | ~1715 |
| skipped as trivial | 29 |

Growth by target topic (tokens to add):

| topic | tokens | rows |
| --- | --- | --- |
| NEW:packages | 430 | 15 |
| NEW:modules | 410 | 9 |
| platforms | 330 | 12 |
| compiler | 195 | 9 |
| NEW:comments | 190 | 7 |
| imports | 70 | 2 |
| error_design | 40 | 1 |
| app_header | 30 | 1 |
| testing | 20 | 1 |

Existing topics that grow most: `platforms` (+330, all comments: header and hosted rules plus the wasm `exports` fix) and `compiler` (+195: pins, `roc deps` markers, `--replace-dep` rules). Most new content is package and module structure that one app file cannot show, so 23 of 57 rows are comment-only unless the plan adds a multi-file example package that the check script also builds. Only 8 rows (4 expect, 4 code) fit as compiling code: nested types, deep nesting, void module, no private methods, nested-error convention, doc comments, autolinks, doc code blocks.
