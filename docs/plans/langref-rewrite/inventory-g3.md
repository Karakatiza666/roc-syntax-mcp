# Langref inventory, group 3

Pages: numbers, strings, dictionaries-and-sets, iterators, loops, operators, parsers, if-else.
Paths: langref = `corpus/language/langref/`, topics = `corpus/language/topics/`, overview = `corpus/language/overview/`.
"partial" in the covered column means the topic touches the idea but leaves out the rule. Those rows count as "to add".
Covered rows have no form, target or token estimate.

## numbers.md

| section (page#slug) | idea, max 20 words | covered | form | target topic | est. tokens |
| --- | --- | --- | --- | --- | --- |
| numbers#number-literals | Underscores may sit between any digits, also hex letters and fraction digits. Each needs a digit on both sides | none | expect | numbers | 30 |
| numbers#number-literals | Base prefixes `0x` `0o` `0b` must be lowercase | partial: numbers.roc:26-28 (shows, no rule) | comment | numbers | 12 |
| numbers#number-literals | Scientific `e` suffix is base-10 only, e.g. `1.5e-2`, never with a base prefix | none | expect | numbers | 30 |
| numbers#number-literals | No decimal point after a base prefix: hex letters would clash with suffixes like `.F64` | none | comment | numbers | 20 |
| numbers#number-literals | `-1` is one literal, `-x` calls `negate`. Custom types see the sign via `from_numeral` | none | comment | numbers | 25 |
| numbers#type-suffixes | Suffix works with any custom number type in scope: `21.Celsius` calls its `from_numeral` | none (numbers.roc:12 builtin only) | code | numbers | 15 |
| numbers#defaulting-to-dec | Unpinned literal defaults to `Dec` | numbers.roc:3, numbers.roc:37-46, language.md:23 | | | |
| numbers#builtin-number-types | Sizes are fixed on every target. Numbers allocate only when converted to `Str` | none | comment | numbers | 20 |
| numbers#fractions | `Dec`: 16 bytes, 18 fraction digits, range about +/-1.7e20 | partial: builtins.md:32 (10^18, no range) | comment | numbers | 20 |
| numbers#fractions | `0.1.Dec + 0.2 == 0.3` is True, `0.1.F64 + 0.2 == 0.3` is False | partial: numbers.roc:4 (comment, Dec half) | expect | numbers | 30 |
| numbers#fractions | `Dec` divide by zero crashes. Float divide by zero gives +/-infinity, some ops give NaN | partial: builtins.md:15, builtins.md:32 | comment | numbers | 20 |
| numbers#fractions | Use `Dec` for money (exact), floats for graphics and simulation (speed, range) | none | comment | numbers | 20 |
| numbers#ranges | `..<` excludes, `..=` includes the end. Both build a reusable `Range` | ranges.roc:1-4 | | | |
| numbers#ranges | Both bounds same type. `Range(U8)`, `Range(Dec)`. Unpinned bounds default like literals | ranges.roc:18-23 | | | |
| numbers#ranges | Step starts at 1. `step_by` replaces the step, a second call does not multiply | ranges.roc:25-29 | | | |
| numbers#ranges | `size_hint` gives `Known(n)` when the count fits `U64`, else `Unknown` | ranges.roc:31-34 | | | |
| numbers#ranges | `iter_rev` yields the same lower-anchored members backwards: 11, 9, 7, 5 | ranges.roc:36-41 (code, no expect) | | | |
| numbers#ranges | Float ranges have no `iter_rev`. Forward float iteration ends when adding the step stops growing | ranges.roc:43-47 | | | |
| numbers#ranges | Range is empty if lower is not below/at upper, or step is not positive | ranges.roc:49-51 | | | |
| numbers#ranges | Range ops dispatch to `range_*_to`. `range_*_from` enables `iter_rev`. `Range.custom` plus `range_iter` | ranges.roc:57-78 | | | |
| numbers#custom-number-types | `from_numeral` runs at compile time. Its `Err(InvalidNumeral(msg))` becomes a compile error at the literal | partial: numbers.roc:53-68 (no compile-error note), derived_methods.roc:99-101 (from_quote only) | comment | numbers | 20 |
| numbers#inferred-custom-number-types | Plain literal passed where a custom type is expected calls its `from_numeral` | numbers.roc:67-68 | | | |
| numbers#custom-number-types-and-operators | `+` and `/` on a custom number type call its `plus` and `div_by` | operators.roc:42-58, derived_methods.roc:124-132 | | | |
| numbers#custom-number-types-and-operators | Top-level constant `two_thirds : Ratio = 2 / 3` is computed at compile time and embedded | none (dbg_crash.roc:4 hints at folding) | code | numbers | 60 |
| numbers#custom-number-types-and-operators | A `crash` in an operator method during compile-time evaluation is a compile error. At runtime it crashes | none | comment | numbers | 25 |
| numbers#creating-a-from_numeral-implementation | `Numeral` methods: `is_negative`, `digits_before_pt`, `digits_after_pt`, `digits_after_pt_count` | none | comment | numbers | 45 |
| numbers#creating-a-from_numeral-implementation | Digits are base-256 `List(U8)`, most significant first. Zero is `[]` | none | comment | numbers | 40 |
| numbers#creating-a-from_numeral-implementation | `digits_after_pt_count` tells `.517` from `.5170`, and `1` (0) from `1.0` (1) | none | comment | numbers | 30 |
| numbers#creating-a-from_numeral-implementation | Compiler strips underscores, applies base prefix and exponent before `from_numeral` sees the digits | none | comment | numbers | 25 |
| numbers#creating-a-from_numeral-implementation | Digits have no length limit, so a big-integer type can accept huge literals | none | comment | numbers | 15 |
| numbers#creating-a-from_numeral-implementation | Simplest `from_numeral` delegates to `I64.from_numeral` and converts | numbers.roc:58 | | | |

## strings.md

| section (page#slug) | idea, max 20 words | covered | form | target topic | est. tokens |
| --- | --- | --- | --- | --- | --- |
| strings#code-points | One grapheme can be many code points. `Str` has no grapheme functions, they live in roc-lang/unicode | none | comment | strings | 25 |
| strings#single-quote-syntax | `'x'` is a number literal of its code point, so unpinned it is a `Dec` | strings.roc:25-29 | | | |
| strings#single-quote-syntax | Single quotes need exactly one code point. `''` is invalid | strings.roc:26-27 | | | |
| strings#string-literal-conversion-and-interpolation | `from_quote` and `from_interpolation`. Each interpolated value pairs with the segment after it | strings.roc:54-59, derived_methods.roc:116-122 | | | |
| strings#string-equality-and-normalization | `"caf\u(e9)" == "café"`: the escape inserts that exact code point | partial: strings.roc:22-23 (escape syntax only) | expect | strings | 20 |
| strings#string-equality-and-normalization | Precomposed and combining forms render the same but `==` is False | strings.roc:62-64 (comment, could be expect) | | | |
| strings#string-normalization | `Str` never normalizes. Normalize (NFC or NFD) once when text enters the program | strings.roc:62-64 | | | |
| strings#why-not-normalize-automatically | Auto normalization on every `==` costs too much CPU, so Roc leaves it to you | none | prose-only | strings | 15 |
| strings#utf-8 | Every `Str` is valid UTF-8. `to_utf8` cannot fail, `from_utf8` gives `Err(BadUtf8({ index, problem }))` | none (platforms.roc:270 use only) | expect | strings | 45 |
| strings#utf-8 | `from_utf8_lossy` replaces each invalid sequence with U+FFFD | partial: platforms.roc:272 (use only) | comment | strings | 15 |
| strings#utf-8 | `Str.len` returns a `LearnAboutStringsInRoc` tag. Use `count_utf8_bytes` | builtins.md:65, strings.roc:33 (see disagreement 2) | | | |
| strings#when-to-use-each-of-these | Parsers work on UTF-8 bytes. Avoid code points unless writing a Unicode library. Avoid grapheme splitting | partial: strings.roc:27-28 | comment | strings | 30 |
| strings#low-level | Surrogate halves are invalid syntax, even in single quotes | strings.roc:61-62 | | | |
| strings#bidirectional-controls | Literal bidi control characters are rejected in source, even balanced, even in strings. Write `"\u(202E)"` | none | code | strings | 35 |
| strings#bidirectional-controls | Rejected set U+061C, U+200E-F, U+202A-E, U+2066-9. `roc fmt` refuses the file | none | comment | strings | 35 |

## dictionaries-and-sets.md

| section (page#slug) | idea, max 20 words | covered | form | target topic | est. tokens |
| --- | --- | --- | --- | --- | --- |
| dictionaries-and-sets#dictionaries | No dict literal syntax. Build with `Dict.empty`, `Dict.single`, `Dict.from_list` of `(k, v)` tuples | none | code | NEW:dict_set | 30 |
| dictionaries-and-sets#dictionaries | `insert`/`remove` return a new dict. Unshared dicts update in place, so it stays fast | none | comment | NEW:dict_set | 20 |
| dictionaries-and-sets#dictionaries | `insert` on an existing key replaces its value | none | expect | NEW:dict_set | 30 |
| dictionaries-and-sets#looking-up-values | `get` returns `Try(v, [KeyNotFound])`, pair with `??`. `contains` tests presence | partial: operators.roc:98 (subscript only) | expect | NEW:dict_set | 30 |
| dictionaries-and-sets#looking-up-values | `update` callback gets `Ok(v)` or `Err(Missing)`. Return `Ok` to store, `Err(Missing)` to remove | none | code | NEW:dict_set | 70 |
| dictionaries-and-sets#iteration-order | Iteration is in insertion order and yields `(key, value)` tuples: `for (k, v) in dict` | partial: builtins.md:29 (order), loops.roc:8 (dicts iterable) | expect | NEW:dict_set | 35 |
| dictionaries-and-sets#iteration-order | Replacing a value keeps its position. `remove` moves the last-inserted key into the hole | partial: builtins.md:29 ("until a remove") | expect | NEW:dict_set | 45 |
| dictionaries-and-sets#sets | `Set(a)` is `Dict(a, {})`. `{}` takes no memory. Same order rules as `Dict` | none | comment | NEW:dict_set | 15 |
| dictionaries-and-sets#sets | Sets have `union`, `intersection`, `difference` | builtins.md:29 | | | |
| dictionaries-and-sets#keys-and-hashing | Keys need `is_eq` and `to_hash`. Structural types have both when their parts do | hashing.roc:23-28, builtins.md:29 | | | |
| dictionaries-and-sets#keys-and-hashing | Nominal keys opt in with `is_eq : _` and `to_hash : _` or hand-write them | hashing.roc:29-32 | | | |
| dictionaries-and-sets#keys-and-hashing | Functions have no equality, so they cannot be keys or set elements | none | comment | hashing | 15 |
| dictionaries-and-sets#keys-and-hashing | Dicts built at runtime use a random hash seed per run, against hash flooding | none | comment | hashing | 25 |

## iterators.md

| section (page#slug) | idea, max 20 words | covered | form | target topic | est. tokens |
| --- | --- | --- | --- | --- | --- |
| iterators#iterators | Collections and ranges have `iter`. `Dict.iter` yields `(k, v)` | iterators.roc:16-17, ranges.roc:6 | | | |
| iterators#transforming-iterators | `map`, `keep_if`, `drop_if`, `with_index`, `take_first`, `drop_first` each return a new `Iter` | iterators.roc:46-54 | | | |
| iterators#transforming-iterators | Reduce with `fold`, `sum`, `min`, `max` | iterators.roc:63-70 | | | |
| iterators#collecting | `collect` target comes from inference. Any type with `from_iter`: `List`, `Set`, `Dict` | builtins.md:34, iterators.roc:54 | | | |
| iterators#collecting | `List.from_iter(it)` names the target explicitly | iterators.roc:43-44 | | | |
| iterators#laziness | Lazy: `map` runs only for items pulled. No intermediate collection per step | partial: builtins.md:34 ("Lazy" only) | expect | iterators | 45 |
| iterators#laziness | Infinite iterators are fine if the consumer stops, e.g. `take_first` | none | expect | iterators | 40 |
| iterators#custom-iterators | `Iter.custom(seed, size_hint, step)`. Collections use the hint to pre-allocate | iterators.roc:75-82, iterators.roc:100-103 | | | |
| iterators#how-iteration-works | `next` returns `One({ item, rest })`, `Skip({ rest })`, or `Done` | iterators.roc:8-14 | | | |
| iterators#how-iteration-works | Iterators are values. `next` does not change the iterator, continue with `rest` | none | comment | iterators | 20 |
| iterators#effectful-iteration | `Iter` callbacks are pure. Use `Stream` for effects | iterators.roc:91-98 | | | |
| iterators#effectful-iteration | `Stream.custom` builds a stream whose step is effectful (`=>`) | none | comment | iterators | 25 |
| iterators#effectful-iteration | Stream adapters pull nothing. Consumers `for!`, `fold!`, `for_each!`, `collect!` need an effectful function | partial: iterators.roc:91-121 (collect!, for! only) | comment | iterators | 25 |
| iterators#effectful-iteration | A plain `for` over an `Iter` may call effectful functions in its body | effects.roc:24-30 | | | |

## loops.md

| section (page#slug) | idea, max 20 words | covered | form | target topic | est. tokens |
| --- | --- | --- | --- | --- | --- |
| loops#for-loops | Body holds only statements. The loop evaluates to `{}` | loops.roc:7-9, language.md:64 | | | |
| loops#iterating-over-types-that-have-iter | `for` calls `iter`, then `next` on the result | loops.roc:7-8, iterators.roc:3-8 | | | |
| loops#looping-backwards | `iter_rev` reads in place. Dict/Set have it. Other sources: `List.from_iter` first | loops.roc:34-37 | | | |
| loops#pattern-matching-in-for | Item position is a pattern: tuples destructure, `_` discards | loops.roc:48-68 | | | |
| loops#pattern-matching-in-for | `for` pattern must be exhaustive. Name the item and `match` inside | loops.roc:70-77, language.md:129 (see disagreement 1) | | | |
| loops#looping-over-streams-with-for | `for!` calls `stream`, so it takes a `Stream` or an `Iter`. Effectful functions only | iterators.roc:112-121 | | | |
| loops#looping-over-streams-with-for | In `for!` the pattern must be exhaustive and `break`/`return` work as in `for` | none | comment | loops | 15 |
| loops#looping-over-streams-with-for | A plain `for` over a `Stream` fails: missing method | iterators.roc:114-115 | | | |
| loops#break-statement | `break` exits only the innermost loop | loops.roc:108-109, language.md:68 | | | |
| loops#infinite-loops | No `loop` keyword. Use `while True` and exit with `break` or `return` mid-body | none | code | loops | 50 |
| loops#infinite-loops | A non-ending loop during compile-time evaluation hangs the compiler | none | comment | loops | 15 |

## operators.md

| section (page#slug) | idea, max 20 words | covered | form | target topic | est. tokens |
| --- | --- | --- | --- | --- | --- |
| operators#desugaring | Operator to method table, chosen at compile time from operand types | operators.roc:42-56, language.md:73-85 | | | |
| operators#and | `and`/`or` take `Bool` only and short-circuit | operators.roc:36-37, conditionals.roc:49-51 | | | |
| operators#and | `and`/`or` do not desugar to methods, so a type cannot overload them | partial: operators.roc:36 (if form only) | comment | operators | 15 |
| operators#arithmetic-operators | Dispatch on left operand, result has its type, right operand may differ | operators.roc:54-55, derived_methods.roc:124-132 | | | |
| operators#comparison-operators | Comparisons need the same type on both sides and return `Bool` | operators.roc:55-56 | | | |
| operators#range-operators | Ranges bind loosest: `1..<n + 1` is `1..<(n + 1)`. No chaining | operators.roc:73-75 | | | |
| operators#-default-value-on-err | `??` desugars to `match` with `Err(_) => default` | operators.roc:85-88, try_operator.roc:75-82 | | | |
| operators#--negate | `-x` is `negate`, `!x` is `not` | operators.roc:51-52 | | | |
| operators#-unwrap-if-ok-early-return-if-err | `?` desugars to `match` with `Err(e) => return Err(e)` | try_operator.roc:30-34 | | | |
| operators#-unwrap-if-ok-early-return-if-err | The function's error type is the union of every `?` site's errors | error_design.roc:61-69 | | | |
| operators#-unwrap-if-ok-early-return-if-err | `?` in top-level `expect` fails the test. In inline `expect` it is a compile error | testing.roc:31-39 | | | |
| operators#-subscript-operator | `x[i]` is not implemented. Call `.subscript(i)`. `Set.subscript` gives `Bool` | operators.roc:94-100 | | | |
| operators#-subscript-operator | Any type opts into future `[...]` syntax by defining `subscript` | none | comment | operators | 12 |

## parsers.md

| section (page#slug) | idea, max 20 words | covered | form | target topic | est. tokens |
| --- | --- | --- | --- | --- | --- |
| parsers#parsers | Format knows primitives, type knows its shape. Any format works with any type | json.roc:3-6, builtins.md:50 | | | |
| parsers#parsing-json | `Json.parse` picks its parser from the inferred target type | json.roc:8-35 | | | |
| parsers#parsing-json | Encoded record fields come out in alphabetical order, not source order (`{"age":..,"name":..}`) | none (json.roc:70 is consistent, no rule) | expect | json | 30 |
| parsers#parsing-json | `parser_camel` maps `user_id` to `"userId"`. `parse_trailing_commas` accepts trailing commas | json.roc:37-52 | | | |
| parsers#which-types-can-be-parsed | Derived codecs for Str, numbers, Bool, records, tuples, tag unions, List, Dict, Set | json.roc:29-30 (no tuples, see note 5) | | | |
| parsers#which-types-can-be-parsed | In JSON a record is an object and a payload-less tag is a string (`"Active"`) | none | expect | json | 30 |
| parsers#optional-fields | Missing field allowed only for `?:` or `Try(T, [Missing])`, else `MissingRequiredField` | json.roc:129-138 | | | |
| parsers#nominal-types | Nominal types get no codec by default, to protect invariants. Derived one uses the backing representation | partial: json.roc:81-86 (opt-in only) | comment | json | 25 |
| parsers#nominal-types | Hand-written `parser_for`/`encoder_for` give a custom representation | json.roc:88-118 | | | |
| parsers#parsers-at-compile-time | A top-level parser constant is built once, at compile time | json.roc:49-52 | | | |
| parsers#writing-generic-parsing-functions | Generic wrappers use `where [a.Json.Parseable(..)]` / `a.Json.Encodable([])` | json.roc:54-65 | | | |
| parsers#other-formats | Formats implement only shapes they support. Unsupported shape is a compile-time error | json.roc:8-10, json.roc:88-91 | | | |
| parsers#other-formats | `Encoding.HttpHeader.parser_for()` parses headers into a record, absent ones as `Try(_, [Missing])` | partial: json.roc:126-127 (named only) | code | json | 40 |
| parsers#other-formats | Formats can ship in packages with no change to the types | json.roc:89-91 | | | |

## if-else.md

| section (page#slug) | idea, max 20 words | covered | form | target topic | est. tokens |
| --- | --- | --- | --- | --- | --- |
| if-else#if-and-else | `if` is a `match` on `Bool` | conditionals.roc:1-2 | | | |
| if-else#if-and-else | No truthiness, only `Bool` | conditionals.roc:4 | | | |
| if-else#else-if | `else if` is just `else` followed by an `if` | conditionals.roc:29-35 | | | |
| if-else#if-without-else | `else` may be left out only when the body is `{}` | conditionals.roc:38-47, language.md:55 | | | |
| if-else#and--or | `a or b` is `if a True else b`, `a and b` is `if a b else False` | conditionals.roc:49-51 | | | |
| if-else#and--or | No `&&`/`\|\|` because `\|\|` is a zero-argument lambda | conditionals.roc:53-54, language.md:79 | | | |

## (a) Disagreements between langref and topics/overview

| # | langref | topics / overview | note |
| --- | --- | --- | --- |
| 1 | langref/loops.md:91: no special exhaustiveness error for `for` yet. A non-exhaustive tag pattern shows as a type mismatch. A number literal pattern is not caught and crashes at runtime | topics/loops.roc:75-77: compiler reports "non exhaustive destructure". `for 1 in ...` is caught at compile time | Direct conflict. Not checked: there is no `roc` on PATH for `roc_check`. Run a check before a merge |
| 2 | langref/strings.md:185-186: `Str.len` returns a `LearnAboutStringsInRoc` tag (Builtin.roc:2256 agrees) | overview/builtins.md:65: "`Str.len` only gives a type error" | Overview is not exact: the call compiles. The type error comes only when the result is used as a number |
| 3 | langref/numbers.md:45-63: an unpinned literal becomes `Dec` | topics/numbers.roc:37-46: ordered fallback (Dec, I64, U64, ...) plus a `LITERAL DEFAULTED` warning | No conflict. The langref is simpler. The topic is the more detailed source |
| 4 | langref/dictionaries-and-sets.md:76-79: exact order rule after `remove` | overview/builtins.md:29: "insertion-ordered until a `remove`" | Agrees but gives less detail. The rule goes into NEW:dict_set |
| 5 | langref/parsers.md:47: tuples derive codecs | topics/json.roc:29-30: list has no tuples | Topic leaves tuples out. Fix in the same pass (about 2 tokens) |

## (b) Ideas skipped as trivial

| page | count | what |
| --- | --- | --- |
| numbers | 7 | digit/letter-digit basics, sample literal list, integer range table, signed vs unsigned, size trade-off advice, `List.get` inference example, REPL reason for the Dec default |
| strings | 8 | intro, Unicode glossary, "character" terminology, ZWJ walk-through and code-point list, memory of joined emoji, `""` vs ints, UTF-8 byte widths, "use `Str` helpers most of the time" |
| dictionaries-and-sets | 4 | Dict/Set definitions, `Dict(Str, U64)` type example, `Set.from_list` dedupe/`len`/`contains`, record-as-key example |
| iterators | 4 | intro, `Iter(item)` meaning, `evens_times_ten` example, link to the static-dispatch iteration page |
| loops | 6 | intro, list `for` example, `1..<5` note (same as ranges), `while` condition is Bool, nested `break` example, "loops are for reassignment or effects" |
| operators | 4 | `and`/`or` truth tables, `??` usage samples, `?` vs `??` advice (already in try_operator.roc:66-73), unary result type equals operand type |
| parsers | 3 | intro, sample inputs and outputs, `Point` opt-in example (same as json.roc:83-86) |
| if-else | 3 | intro, brace-free `else if` example, `if` without `else` sample |

Optional upgrades (not counted above): some covered ideas exist only as comments and could become `expect`s that also test the claim. Examples: ranges.roc:41 and :50-51, strings.roc:62-63, strings.roc:26. That is about 8 expects, about 150 tokens.

## Totals

| page | ideas | covered | to add | expect | code | comment | prose-only | est. tokens |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| numbers | 31 | 12 | 19 | 3 | 2 | 14 | 0 | 502 |
| strings | 15 | 7 | 8 | 2 | 1 | 4 | 1 | 220 |
| dictionaries-and-sets | 13 | 3 | 10 | 4 | 2 | 4 | 0 | 315 |
| iterators | 14 | 9 | 5 | 2 | 0 | 3 | 0 | 155 |
| loops | 11 | 8 | 3 | 0 | 1 | 2 | 0 | 80 |
| operators | 13 | 11 | 2 | 0 | 0 | 2 | 0 | 27 |
| parsers | 14 | 10 | 4 | 2 | 1 | 1 | 0 | 125 |
| if-else | 6 | 6 | 0 | 0 | 0 | 0 | 0 | 0 |
| total | 117 | 66 | 51 | 13 | 7 | 30 | 1 | 1424 |

Add about 40 tokens for the header of the NEW:dict_set topic and its entry in src/topics.ts. Total about 1.46k tokens.

Growth by topic:

| topic | items | est. tokens |
| --- | --- | --- |
| numbers | 19 | 502 |
| NEW:dict_set | 8 | 275 (+40 overhead) |
| strings | 8 | 220 |
| iterators | 5 | 155 |
| json | 4 | 125 |
| loops | 3 | 80 |
| hashing | 2 | 40 |
| operators | 2 | 27 |

The numbers topic grows the most. Most of that is the `Numeral` contract (base-256 digits, `digits_after_pt_count`, normalization). One `Numeral` comment block next to `Celsius` could hold about 150 of those tokens. `if-else` is fully covered. `operators` is nearly fully covered.
