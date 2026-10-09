# Inventory g4: functions, expressions, compile-time, statements, pattern-matching

Paths: `topics/` = corpus/language/topics/, `overview/` = corpus/language/overview/.
No `roc` compiler was on PATH, so no claim below was checked with `roc_check`.
"partial" in the covered column means the topic says less than the langref; the row counts as not covered and the token estimate is for the missing part.

| section (page#slug) | idea, max 20 words | covered | form | target topic | est. tokens to add |
| --- | --- | --- | --- | --- | --- |
| functions#functions | One function syntax, the lambda `\|a, b\| body`; no `fn`, `\x ->` or `f x = ...` forms | topics/functions.roc:3-6; overview/language.md:30 | code | functions | 0 |
| functions#functions | Rationale: functions are ordinary values, so they are declared like every other value | topics/functions.roc:46 | prose-only | functions | 0 |
| functions#pure-functions | Effectfulness is transitive: calling an effectful function makes the caller effectful | topics/effects.roc:23-24 | code | effects | 0 |
| functions#pure-functions | Top-level constants, like pure functions, cannot call effectful functions; `x = greet!("Sam")` is an error | partial: topics/effects.roc:16-17 (pure functions only) | comment | effects | 25 |
| functions#pure-functions | Purity is why every top-level value can be evaluated at compile time with an identical result | none | comment | NEW:compile_time | 35 |
| functions#pure-functions | Pure code may crash or loop; a compile-time crash is a compile error, a loop hangs the compiler | none | comment | NEW:compile_time | 40 |
| functions#pure-functions | Allocation is allowed in pure code; a failed allocation crashes | none | comment | NEW:memory | 20 |
| functions#pure-functions | `dbg`/`expect` are allowed in pure code; output may appear only at compile time, or never | topics/dbg_crash.roc:3-4 | comment | dbg_crash | 0 |
| functions#effectful-functions | A `->`-annotated function that calls an effectful one is rejected | topics/effects.roc:16-17 | code | effects | 0 |
| functions#effectful-functions | All effects come from platform functions; the platform calls the effectful entry point `main!` | overview/language.md:4; topics/effects.roc:7 | comment | effects | 0 |
| functions#--and--in-function-type-annotations | No effect polymorphism: no "pure or effectful" type, hence `map_ok`/`map_ok!` twins | partial: overview/builtins.md:19 (twins only, no reason) | comment | effects | 35 |
| functions#-suffix-in-function-names | Only effectful functions end in `!`; compiler warns if an effectful name lacks `!` | partial: overview/language.md:14 (convention, no warning) | comment | effects | 20 |
| functions#purity-inference | Purity is inferred; a purity annotation is optional | none (topics/effects.roc:19 is unannotated but says nothing) | comment | effects | 15 |
| functions#purity-inference | Wrong purity annotation is today a type mismatch error (planned to become a warning) | none | comment | effects | 30 |
| functions#purity-inference | `roc check`/`build` never run platform code, so no dependency can do I/O at build time | none | prose-only | NEW:compile_time | 35 |
| functions#recursive-functions | Non-tail self recursion uses a stack frame per call and can overflow | none | code | NEW:recursion | 50 |
| functions#self-tail-calls | `n * f(n - 1)` is not a tail call; an accumulator argument makes it one | none | expect | NEW:recursion | 80 |
| functions#tail-call-optimization | If every self-call is a tail call the function becomes a loop: no overflow, may loop forever | none | comment | NEW:recursion | 35 |
| functions#modulo-cons | A self-call placed directly in a tag of its own return type also becomes a loop | none | expect | NEW:recursion | 90 |
| functions#mutually-recursive-functions | Functions can call each other; the listed tail-call optimizations cover self-calls only | none | code | NEW:recursion | 50 |
| expressions#types-of-expressions | `\|\| body` is a zero-argument lambda | topics/conditionals.roc:53-54; topics/dbg_crash.roc:5 | code | functions | 0 |
| expressions#values | Values are immutable; only `$var` bindings rebind | overview/language.md:15 | comment | loops | 0 |
| expressions#value-identity | No reference equality, pointers or address access; equality is by value only | none | comment | NEW:memory | 30 |
| expressions#value-identity | A platform can see addresses; relying on them is the platform author's choice | none | prose-only | platforms | 30 |
| expressions#reference-counting | Str, List, Box, recursive unions: heap, atomic refcount; numbers, records, tuples, other unions: stack | partial: overview/language.md:4 (refcount only); see disagreement A2 | comment | NEW:memory | 45 |
| expressions#reference-cycles | Roc cannot express reference cycles, so it needs no cycle collector or weak references | none | prose-only | NEW:memory | 25 |
| expressions#opportunistic-mutation | Builtin update of a unique value (refcount 1) is in place; a shared value is shallow-cloned first | none | comment | NEW:memory | 45 |
| expressions#block-expressions | A block is statements plus a final expression, with its own scope | topics/functions.roc:3-5,13; topics/conditionals.roc:21 | code | functions | 0 |
| expressions#block-expressions | `{ x }` is always a block, never a one-field record; write `{ x, }` | topics/derived_methods.roc:89-90; topics/numbers.roc:60-61 | expect | records | 0 |
| expressions#evaluation | Evaluation is strict, never lazy | overview/language.md:3 | prose-only | - | 0 |
| expressions#side-effects-during-evaluation | Only `dbg` and `expect` have effects outside effectful functions; they are not program semantics | partial: topics/dbg_crash.roc:3 (dbg only) | comment | dbg_crash | 25 |
| expressions#side-effects-during-evaluation | Platform allocation hooks may do effects; the optimizer may remove them between compiler releases | none | prose-only | platforms | 30 |
| expressions#compile-time-evaluation | Results of effectful calls and platform-provided values are never known at compile time | none | comment | NEW:compile_time | 25 |
| expressions#compile-time-evaluation | `add_one = make_adder(1)` at top level is built at compile time, same as a literal lambda | none | expect | NEW:compile_time | 60 |
| compile-time#compile-time-evaluation | Evaluated values are stored in the binary as static constants | none | comment | NEW:compile_time | 20 |
| compile-time#top-level-declarations | Every top-level declaration is evaluated at compile time; `z = x + y` costs the same as `z = 3` | partial: topics/json.roc:49-50 (parsers only) | expect | NEW:compile_time | 50 |
| compile-time#top-level-equivalent-expressions | A subexpression using only top-level values and pure calls folds, even inside `main!` | none | code | NEW:compile_time | 50 |
| compile-time#top-level-equivalent-expressions | Only final values are kept; intermediate constants are dead-code eliminated | none | comment | NEW:compile_time | 20 |
| compile-time#effectful-functions-never-run-at-compile-time | In `echo!("z is ${z.to_str()}")` the string folds at build, `echo!` runs at runtime | none | comment | NEW:compile_time | 30 |
| compile-time#empty-builtin-collections-never-get-stored | Empty List/Str/Dict/Set are never stored; top-level `List.with_capacity(n)` re-runs at runtime | none | comment | NEW:compile_time | 45 |
| compile-time#code-with-errors | A program with type errors still runs; code with an error crashes only when reached | none | comment | compiler | 30 |
| compile-time#code-with-errors | Compile-time eval reaching an error (even via `==`, method, parser) reports it once; value crashes at runtime; unreached errors are harmless | none | comment | NEW:compile_time | 55 |
| compile-time#code-with-errors | A top-level `expect` that reaches code with an error is a compiler error in `roc test`, not pass/fail | none | comment | testing | 30 |
| compile-time#performance | Top-level evaluation can bloat the binary: a big list is stored even if its path never runs | none | comment | NEW:compile_time | 35 |
| compile-time#uses | A top-level parser from `parser_for`/`Json.parser_camel()` is assembled at compile time | topics/json.roc:49-50 | code | json | 0 |
| compile-time#uses | `import "x.json"` plus a top-level `Json.parse` parses at build; runtime neither reads nor parses | partial: topics/imports.roc:47-52 (embed only) | comment | NEW:compile_time | 45 |
| compile-time#uses | Precompute lookup tables and Dicts as top-level constants | none | code | NEW:compile_time | 50 |
| statements#assignment-patterns | A destructuring assignment must be exhaustive; `Ok(x) = list.first()` is rejected | topics/pattern_matching.roc:44-46; topics/loops.roc:70-77 | comment | pattern_matching | 0 |
| statements#assignment-order | Inside a block a name must be defined before use; top-level definitions may be in any order | none | code | NEW:bindings | 50 |
| statements#assignment-cycles | A top-level cycle is allowed only if every member is a function; a value cycle is a compile error | none | code | NEW:recursion | 60 |
| statements#reassignment | Only a `var $x` can be reassigned | topics/loops.roc:3-5; overview/language.md:15 | code | loops | 0 |
| statements#reassignment | `x = 0` then `x = 1` is shadowing with a warning, not reassignment and not an error | none; see disagreement A4 | comment | NEW:bindings | 30 |
| statements#import-exposing | With `exposing`, the qualified `Color.to_str` still works too | partial: topics/imports.roc:12-16 | comment | imports | 15 |
| statements#importing-non-roc-files | The type must be `Str` or `List(U8)`; a missing file or invalid UTF-8 for `Str` is a compile error | none (topics/imports.roc:47-49 shows `Str` only) | comment | imports | 40 |
| statements#importing-non-roc-files | The file is embedded at build and need not exist at runtime; path is relative to the importer | topics/imports.roc:47-48; overview/language.md:113 | comment | imports | 0 |
| statements#dbg | `dbg` prints `[dbg] value` to stderr through `Str.inspect`, so `to_inspect` applies | none | comment | dbg_crash | 30 |
| statements#dbg | A `dbg` reached during compile-time eval prints during `roc check`/`build`, not when the program runs | partial: topics/dbg_crash.roc:4 | comment | dbg_crash | 20 |
| statements#dbg | An optimized build warns for every `dbg` | topics/compiler.roc:57-58 | comment | compiler | 0 |
| statements#top-level-expect | A failure report shows the failing expression and values of referenced top-level names | none | comment | testing | 20 |
| statements#top-level-expect | `roc test` also runs `expect`s of imported modules and path packages, not URL packages | partial: topics/testing.roc:3-4 | comment | testing | 25 |
| statements#top-level-expect | `?` in a top-level `expect` fails the test on `Err` | topics/testing.roc:31-39 | expect | testing | 0 |
| statements#inline-expect | A failed inline `expect` reports and continues; optimized builds omit it | topics/testing.roc:17-19 | code | testing | 0 |
| statements#expect-control-flow | `return` and a `break` out of an outer loop are errors in top-level `expect`s too | partial: topics/testing.roc:31-35 (inline only); see A3 | comment | testing | 20 |
| statements#expect-control-flow | `?`/`return` inside a function defined in the `expect`, and `break` of an inner loop, are allowed | none | expect | testing | 60 |
| statements#expect-control-flow | A `var` declared inside the `expect` can be reassigned freely | partial: topics/testing.roc:35 (outer var only) | expect | testing | 40 |
| statements#return | `return` exits the enclosing function | topics/dbg_crash.roc:25; topics/functions.roc:19 | code | dbg_crash | 0 |
| statements#break | `break` exits the innermost loop | topics/loops.roc:108-109 | comment | loops | 0 |
| statements#continue | `continue` is not implemented | topics/dbg_crash.roc:48-50; overview/language.md:126 | comment | dbg_crash | 0 |
| statements#crash | What happens after `crash` is the platform's choice: recover or terminate | none | comment | dbg_crash | 20 |
| statements#block-statements | A block may end in a statement such as `return`, with no final expression | topics/functions.roc:22-24; topics/conditionals.roc:38-41 | code | functions | 0 |
| pattern-matching#branch-alternatives | `\|` gives several patterns one body | topics/pattern_matching.roc:10-11; overview/language.md:58 | code | pattern_matching | 0 |
| pattern-matching#branch-alternatives | Every alternative must bind the same names with compatible types | none | expect | pattern_matching | 50 |
| pattern-matching#if-guards-on-branches | A guard runs after its pattern matches; `False` falls through to the next branch | topics/pattern_matching.roc:24-31; overview/language.md:57 | code | pattern_matching | 0 |
| pattern-matching#if-guards-on-branches | A guarded branch never counts for exhaustiveness, even `_ if cond` | none | comment | pattern_matching | 25 |
| pattern-matching#bindings-and-wildcards | `_` binds nothing; `_name` binds but marks the name as unused on purpose | overview/language.md:16 | comment | pattern_matching | 0 |
| pattern-matching#literal-patterns | A numeric literal pattern can carry a type suffix: `1.5.F32 =>` | none | expect | pattern_matching | 45 |
| pattern-matching#literal-patterns | Single-quote codepoint patterns, with a suffix: `'A'.U8 =>` | none (topics/strings.roc:25-29 is expression only) | expect | pattern_matching | 40 |
| pattern-matching#literal-patterns | `True`/`False` are `Bool` tags and match as tags | topics/pattern_matching.roc:18-21; topics/nominal.roc:29-31 | code | pattern_matching | 0 |
| pattern-matching#literal-patterns | String captures `${id}`, `${_}`; two captures cannot be adjacent | topics/pattern_matching.roc:48-57 | expect | pattern_matching | 0 |
| pattern-matching#literal-patterns | A capture before literal text takes everything up to the first occurrence of that text | none | expect | pattern_matching | 35 |
| pattern-matching#record-patterns | `field: pattern` renames a field or sub-matches it (`active: True`) | partial: topics/strings.roc:111 (`after: _` only) | expect | records | 50 |
| pattern-matching#record-patterns | A record pattern without `..` must list every field; bare `..` ignores the rest | none (`..rest` at topics/records.roc:23-29) | expect | records | 50 |
| pattern-matching#list-patterns | `..` appears once, with fixed patterns either side; `.. as rest` binds it | topics/list_patterns.roc:9-11; overview/language.md:62 | code | list_patterns | 0 |
| pattern-matching#nested-patterns-and-as | A one-field record pattern is written `{ name, }` (trailing comma), like the expression | none (expression form only, topics/derived_methods.roc:89-90) | comment | records | 20 |
| pattern-matching#nested-patterns-and-as | `pattern as name` binds the whole value while destructuring it, for any pattern | partial: topics/list_patterns.roc:11 (list rest only) | expect | pattern_matching | 40 |
| pattern-matching#nominal-patterns | A nominal value destructures only through its type: `Distance.(m)`; the same syntax wraps | none | expect | nominal | 50 |
| pattern-matching#nominal-patterns | Nominal records use `Type.{ fields }`; `Type.({ ... })` is accepted but unconventional | topics/pattern_matching.roc:33-38; topics/types.roc:59-64 | code | pattern_matching | 0 |
| pattern-matching#exhaustiveness | The compiler lists missing patterns; prefer explicit cases to `_` | topics/pattern_matching.roc:40-42 | comment | pattern_matching | 0 |
| pattern-matching#exhaustiveness | The compiler reports redundant branches, such as `Ok(_)` after `_` | none | comment | pattern_matching | 20 |
| pattern-matching#destructuring | A destructure that can fail is a compile error, never a runtime failure | topics/pattern_matching.roc:44-46; topics/loops.roc:75-77 | comment | pattern_matching | 0 |
| pattern-matching#destructuring-assignments | A tag destructure is allowed when the type has only that tag | none | expect | pattern_matching | 40 |
| pattern-matching#destructuring-assignments | Function argument patterns must be exhaustive too | none (shown at topics/pattern_matching.roc:38, not stated) | comment | pattern_matching | 20 |
| pattern-matching#destructuring-assignments | A `for` pattern must be exhaustive | topics/loops.roc:70-77; overview/language.md:129 | comment | loops | 0 |

## (a) Disagreements between the langref and our content

| # | langref | ours | note |
| --- | --- | --- | --- |
| A1 | expressions.md:20-34 lists "all" expression kinds and says there are no others; `if`, `match`, `for` are not listed | topics/conditionals.roc:1, topics/pattern_matching.roc:2 (and pattern-matching.md:9 itself) call `if`/`match` expressions | Langref list is incomplete or uses a narrow meaning. Ours is the safer claim. |
| A2 | expressions.md:58-59: records, tuples and non-recursive tag unions are stack-allocated and not refcounted | topics/records.roc:40-41: "The compiler decides whether a record is on the stack or the heap" | Direct conflict. Find out which one is current before writing NEW:memory. |
| A3 | statements.md:235-238: `return` and an outer `break` are errors in top-level and inline `expect`s; `?` only in inline | topics/testing.roc:31-35 lists `return`, `break` and outer `var` reassignment under the inline case only | Ours is narrower, so it reads as "allowed at top level". |
| A4 | statements.md:83-88: `foo = 0; foo = 1` compiles with a shadowing warning | topics/loops.roc:5 "Constants (without `$`) can never be reassigned"; overview/language.md:15 "`$name` ... the only rebindable binding" | Not a strict conflict (shadowing is not reassignment), but an agent will read ours as "error". Check with roc_check. |

Langref defects (not disagreements): compile-time.md:280 is an unfinished draft line ("trick: both branches of an if ... prob hopefully haha"). functions.md:143 says incorrect purity annotations give a type mismatch error today, not the warning the section describes.

## (b) Ideas judged trivial or duplicate, skipped

| page | count | what |
| --- | --- | --- |
| functions | 4 | first-class functions intro, side-effect example list, definitions of self-recursion and tail call |
| expressions | 6 | parenthesization rule, expression-kind list (literals, lookups, calls), values evaluate to themselves, `List.set` narrative; compile-time crash and code-with-errors (duplicates of functions/compile-time rows) |
| compile-time | 3 | comptime/CTFE terminology, literals evaluate to themselves, "compile time is usually faster" |
| statements | 6 | statements have no value, names are lowercase, basic `import`, code after `crash` is unreachable, single-statement block, `expect` reaching an error (duplicate of compile-time row) |
| pattern-matching | 7 | first matching branch wins, scrutinee evaluated once, branch-scoped names, bodies share a type, a named binding is a catch-all, tuples need two elements, nested tag payloads |

## Totals

| measure | value |
| --- | --- |
| ideas (rows) | 93 |
| already covered | 32 |
| to add (none or partial) | 61 |
| to add as expect | 15 |
| to add as code | 6 |
| to add as comment | 36 |
| to add as prose-only | 4 |
| est. tokens to add | ~2,250 |

| target topic | rows to add | est. tokens |
| --- | --- | --- |
| NEW:compile_time | 15 | 595 |
| NEW:recursion | 6 | 365 |
| pattern_matching | 9 | 315 |
| testing | 6 | 195 |
| NEW:memory | 5 | 165 |
| effects | 5 | 125 |
| records | 3 | 120 |
| dbg_crash | 4 | 95 |
| NEW:bindings | 2 | 80 |
| platforms | 2 | 60 |
| imports | 2 | 55 |
| nominal | 1 | 50 |
| compiler | 1 | 30 |

Of the existing topics, pattern_matching, testing and effects grow most. Of the 61 ideas to add, 51 are compile-time evaluation, recursion and tail calls, memory model, or pattern-matching edge cases. The 4 prose-only ideas (no build-time I/O, address visibility for platforms, no reference cycles, platform allocation hooks) are short, and each fits as a comment in a topic. NEW:bindings is small (2 rows) and could go into `functions` or `loops` instead.
