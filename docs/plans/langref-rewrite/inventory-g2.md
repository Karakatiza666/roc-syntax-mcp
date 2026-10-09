# Langref coverage inventory, group g2

Pages: static-dispatch.md, types.md, tag-unions.md, records.md, tuples.md, naming.md (all under corpus/language/langref/).
Topic paths are relative to corpus/language/topics/, overview paths to corpus/language/overview/.
"verified" means checked with the bundled compiler roc_nightly-linux_x86_64-2026-10-06-c34079d in scratch files that are not kept.

## Ideas

| # | section (page#slug) | idea, max 20 words | covered | form | target topic | est. tokens |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | static-dispatch#static-dispatch | No dynamic dispatch by design; static dispatch compiles to a direct call, zero runtime overhead | static_dispatch.roc:7-9 | comment | static_dispatch | 0 |
| 2 | static-dispatch#methods | Methods live in the `.{ }` block after a nominal declaration; call as `T.f()` or `v.f()` | static_dispatch.roc:32-43 | code | static_dispatch | 0 |
| 3 | static-dispatch#well-known-methods | Full well-known method table: operators, inspect, hash, literals, iter/next, codecs, map | derived_methods.roc:41-68; language.md:87-95 | comment | derived_methods | 0 |
| 4 | static-dispatch#well-known-methods | Table does not limit method names; packages require their own methods via `where` | derived_methods.roc:43-44; static_dispatch.roc:71-72 | comment | static_dispatch | 0 |
| 5 | static-dispatch#compiler-derived-methods | Six derivable methods; structural types get them free, nominal opts in with `method : _` | derived_methods.roc:3-15; language.md:89-92 | code | derived_methods | 0 |
| 6 | static-dispatch#compiler-derived-methods | `_` annotation works only for the six names; other bodyless declarations are errors except hosted | derived_methods.roc:17-20 | comment | derived_methods | 0 |
| 7 | static-dispatch#compiler-derived-methods | A body is a custom implementation; a type can mix derived and hand-written methods | derived_methods.roc:22-32 | code | derived_methods | 0 |
| 8 | static-dispatch#compiler-derived-methods | Derived `map`/`map!` only for tag unions with one selected direct payload | derived_methods.roc:34-39; tag_unions.roc:57-66 | expect | tag_unions | 0 |
| 9 | static-dispatch#to_inspect | `to_inspect` customizes `Str.inspect`; without it the structural rendering is used | derived_methods.roc:70-79 | code | derived_methods | 0 |
| 10 | static-dispatch#to_inspect | `Str.inspect` uses `to_inspect` only if its type is exactly `T -> Str`, params unconstrained; else silently ignored | none | expect | derived_methods | 90 |
| 11 | static-dispatch#to_inspect | Inside `to_inspect`, call `Str.inspect` on payloads; it works for any type | none | expect | derived_methods | 20 |
| 12 | static-dispatch#equality-and-hashing | `!=` calls `is_eq` and negates the result | derived_methods.roc:47; operators.roc:46; language.md:77 | comment | operators | 0 |
| 13 | static-dispatch#equality-and-hashing | Custom `is_eq` needs a consistent `to_hash`; Dict/Set keys need both | hashing.roc:23-26; idioms.roc:122-124; builtins.md:28 | comment | hashing | 0 |
| 14 | static-dispatch#operators | Arithmetic dispatches on left operand, returns its type; right operand type may differ | derived_methods.roc:124-132; operators.roc:54-56 | code | operators | 0 |
| 15 | static-dispatch#operators | Comparison and range operators need both operands of the same type | operators.roc:55-56; ranges.roc:18-23 | comment | operators | 0 |
| 16 | static-dispatch#operators | Operator to method mapping (`+` plus ... `..=` range_inclusive_to) | operators.roc:42-52; language.md:71-85 | comment | operators | 0 |
| 17 | static-dispatch#operators | Unary operator methods (`negate`, `not`) take and return the same type | none | comment | operators | 20 |
| 18 | static-dispatch#operators | Custom range syntax via `range_exclusive_to` and `Range.custom`; `range_iter`, `_from` for `iter_rev` | ranges.roc:57-78 | code | ranges | 0 |
| 19 | static-dispatch#literal-conversion | `from_numeral` runs when a number literal's target is a nominal type defining it | derived_methods.roc:81-97; numbers.roc:53-68 | code | derived_methods | 0 |
| 20 | static-dispatch#literal-conversion | `Numeral` carries exact digits so a type can reject out-of-range literals with `InvalidNumeral` | derived_methods.roc:82-84 | comment | numbers | 0 |
| 21 | static-dispatch#literal-conversion | `from_quote` returning `Err(BadQuotedBytes)` makes the literal a compile-time error | derived_methods.roc:99-114 | code | derived_methods | 0 |
| 22 | static-dispatch#literal-conversion | `from_interpolation : Str, Iter((item, Str)) -> T`; first segment, then value with following segment | derived_methods.roc:116-122; strings.roc:54-58 | comment | derived_methods | 0 |
| 23 | static-dispatch#iteration | `for` calls `iter`; item type must match the pattern; loop then calls `next` (One/Skip/Done) | iterators.roc:3-14, 84-89 | code | iterators | 0 |
| 24 | static-dispatch#parsing-and-encoding | Hand-written `parser_for`/`encoder_for` constrain the encoding with `where`; nominal hides backing | json.roc:152-182 | code | json | 0 |
| 25 | static-dispatch#parsing-and-encoding | Structural records, unions, lists, sets, dicts get derived codecs when the format supports the shape | json.roc:93-94 | comment | json | 0 |
| 26 | static-dispatch#number-literal-defaulting | Defaulting order Dec, I64, U64, ...; `LITERAL DEFAULTED` warning when a default narrows a type | numbers.roc:37-46; language.md:23 | comment | numbers | 0 |
| 27 | static-dispatch#where-clauses | `where [a.m : sig]` lets a body call `m` on a type variable; checked at each call site | types.roc:27-30; static_dispatch.roc:71-74 | code | types | 0 |
| 28 | static-dispatch#where-clauses | Annotated function missing a needed `where` entry is an error; unannotated functions infer the clause | none | comment | types | 35 |
| 29 | static-dispatch#where-clauses | One `where` can list several comma-separated constraints over different type variables | none | code | types | 60 |
| 30 | static-dispatch#where-clauses | Structural records have no `to_str` method, so `.to_str()` on a record fails to type-check | none | comment | types | 25 |
| 31 | static-dispatch#calling-methods-on-type-variables | `Thing : thing` in a body names a type variable so `Thing.default()` calls methods without a value | json.roc:165, 177 (code only, not explained) | expect | types | 90 |
| 32 | static-dispatch#aliases | Where alias `a.Showable : where [...]`, used as `where [a.Showable]` | types.roc:32-41; json.roc:140-143 | expect | types | 0 |
| 33 | static-dispatch#aliases | Any type with the methods satisfies an alias; no "implements" declaration exists | none (implied by types.roc:41) | comment | types | 20 |
| 34 | static-dispatch#aliases | A where alias can combine other aliases and single constraints | none | code | types | 40 |
| 35 | static-dispatch#aliases | Where aliases take parameters (`a.Encodable(fmt)`) that their constraints can mention | types.roc:34; json.roc:118-129 | code | json | 0 |
| 36 | static-dispatch#aliases | A where alias is not a type: `describe : Showable -> Str` errors (verified "where alias used as a type") | none | comment | types | 25 |
| 37 | types#roc-s-type-system | Rank-1 only: a function argument is used at one type within a call | none | comment | types | 40 |
| 38 | types#roc-s-type-system | No higher-kinded polymorphism: cannot abstract over `List` as in `m(a) -> m(b)` | none | comment | types | 30 |
| 39 | types#roc-s-type-system | No subtyping; record/union width flexibility comes from extension variables | none | comment | types | 30 |
| 40 | types#generalization | Only functions, annotated let-values and value aliases generalize; other values are monomorphic (let case verified) | none | expect | types | 90 |
| 41 | types#generalization | Top-level value with free type variables is an error (verified "polymorphic value") | none | comment | types | 25 |
| 42 | types#generalization | `shorthand = Foo.my_func` stays generalized because copying a reference does no work | none (functions.roc:46-47 shows the form only) | comment | functions | 25 |
| 43 | types#generalization | Reason: monomorphic values stop a value, `dbg` or `expect` from recomputing per type | none | prose-only | types | 30 |
| 44 | types#generalization / naming#var-keyword | A `var` is never generalized, even when annotated; its type is fixed by first use | none | comment | loops | 30 |
| 45 | types#where-clauses | A `where` clause can go on a value annotation, not only on functions | none | comment | types | 20 |
| 46 | types#structural-types | Anonymous `..` is a fresh variable each use; named `..r` relates the rest across positions | tag_unions.roc:26-36; language.md:46-47 | comment | types | 0 |
| 47 | types#nominal-types | `UserId := U64` is distinct from `U64`; same-shaped nominals are distinct | nominal.roc:1-4; idioms.roc:99-101 | comment | nominal | 0 |
| 48 | types#constructing-nominal-types | Record and tag literals lift into a nominal when the expected type supplies it | derived_methods.roc:88-90; nominal.roc:29-32 | code | nominal | 0 |
| 49 | types#constructing-nominal-types | Explicit construction `T.(v)`, `T.(a, b)`, `T.{...}`, `T.Tag(p)`; `T.(v)` form absent from topics | partial: `T.{}` in ranges.roc:67, idioms.roc:120 | expect | nominal | 60 |
| 50 | types#constructing-nominal-types | Number and string literals never lift into a nominal without `from_numeral`/`from_quote` (verified mismatch) | none | expect | nominal | 50 |
| 51 | types#constructing-nominal-types | A value of concrete type must be wrapped explicitly: `|n| Distance.(n)`, not `|n| n` | none | code | nominal | 40 |
| 52 | types#destructuring-nominal-types | `Type.{ x }` destructures a nominal record in a parameter or match branch | types.roc:59-64; pattern_matching.roc:33-38 | code | pattern_matching | 0 |
| 53 | types#opaque-nominal-types | `::` hides the backing outside the defining module; inside it acts like `:=` | opaque.roc:1-6; language.md:39 | comment | opaque | 0 |
| 54 | types#nested-nominal-types | Nominal types nest in a `.{ }` block and are reached as `Outer.Inner.member` | imports.roc:54-64; language.md:111 | code | imports | 0 |
| 55 | types#type-aliases | `:` alias is transparent and interchangeable with its definition | nominal.roc:9; idioms.roc:95; language.md:37 | comment | nominal | 0 |
| 56 | types#recursive / tag-unions#limitations | Aliases and structural unions cannot be recursive; recursion must go through a nominal type | none | code | types | 60 |
| 57 | types#mutually-recursive | Mutually recursive types must all be nominal; export them as associated types of one type | imports.roc:54-66 | comment | imports | 0 |
| 58 | tag-unions#tags | Multi-payload `Foo(4, 2)` compiles exactly like `Foo((4, 2))` | none | comment | tag_unions | 30 |
| 59 | tag-unions#tags | One union cannot hold the same tag name with incompatible payload types | none | comment | tag_unions | 25 |
| 60 | tag-unions#structural-tag-unions | Structural unions need no declaration, match by shape, and grow with use | idioms.roc:19-24, 88-91 | comment | idioms | 0 |
| 61 | tag-unions#extending-structural-tag-unions | Branches of an `if`/`match` union their tags into the result type | error_design.roc:67-69; idioms.roc:42-44 | comment | error_design | 0 |
| 62 | tag-unions#structural-tag-union-type-parameters | `[Red, Green, ..others] -> [..., Blue, ..others]` passes unknown tags through; result narrows to produced tags | none | expect | tag_unions | 90 |
| 63 | tag-unions#structural-tag-union-type-parameters | Parameterized alias over an extension variable, `Letters(others) : [A, B, ..others]` | tag_unions.roc:35-44 | code | tag_unions | 0 |
| 64 | tag-unions#structural-tag-union-type-parameters | Open input union plus `_` branch accepts at least the listed tags | tag_unions.roc:26-33 | code | tag_unions | 0 |
| 65 | tag-unions#structural-tag-union-type-parameters | `..` means the same as `.._` | none | comment | tag_unions | 15 |
| 66 | tag-unions#closed-tag-unions | Closed `..[]` syntax is not implemented (verified parse error); use a nominal type to close | partial: idioms.roc:63-64 | comment | tag_unions | 30 |
| 67 | tag-unions#closed-tag-unions | Only closed unions cross the host boundary, since the host needs fixed discriminants | platforms.roc:166-178; error_design.roc:151-153; idioms.roc:63-64 | comment | platforms | 0 |
| 68 | tag-unions#nominal-tag-unions | Nominal unions are fixed: not extensible and take no `..others` | none | comment | tag_unions | 20 |
| 69 | tag-unions#qualified-tags | `Color.Red` is always a Color; bare `c = Red` stays structural unless the context expects Color | partial: tag_unions.roc:53-55; nominal.roc:29-32 | expect | tag_unions | 50 |
| 70 | tag-unions#qualified-tags | Qualified and unqualified tags mix in one match on a known nominal type | pattern_matching.roc:18 | code | pattern_matching | 0 |
| 71 | tag-unions#qualified-tags | Methods call on a qualified tag (`Color.Red.to_hex()`); a nested type named `Red` takes precedence | none | expect | tag_unions | 50 |
| 72 | tag-unions#opaque-tag-unions | Other modules cannot build or match an opaque union's tags, so its tags can change freely | opaque.roc:1-6 (general) | comment | opaque | 0 |
| 73 | tag-unions#structural-nominal-compatibility | Structural `Ok`/`Err` lift into nominal `Try` only for tags it has with compatible payloads | partial: nominal.roc:31; tag_unions.roc:4 | comment | tag_unions | 25 |
| 74 | tag-unions#structural-nominal-compatibility | Structural-nominal lifting does not bypass opaque access boundaries | none | comment | opaque | 15 |
| 75 | tag-unions#void | `[]` has no values; `Try(U64, [])` never errs, so `Ok` alone is exhaustive and `Ok(n) = f(x)` is allowed (verified) | none (pattern_matching.roc:44-45 states only the opposite case) | expect | pattern_matching | 70 |
| 76 | tag-unions#limitations-1 | Nominal unions can be recursive and can always cross the host boundary | idioms.roc:63-64 (FFI part) | comment | tag_unions | 0 |
| 77 | records#record-literals | A trailing comma makes `roc fmt` put fields on separate lines | none | comment | records | 20 |
| 78 | records#record-literals | Field pun `{ name, age }` | builder_pattern.roc:234-239; records.roc:9-15 | code | records | 0 |
| 79 | records#record-literals | Single-field pun needs a comma: `{ name }` is a block, `{ name, }` a record | derived_methods.roc:88-90; numbers.roc:59-61 (not in records topic) | code | records | 0 |
| 80 | records#accessing-fields | Field access is a fixed offset, no runtime name lookup | records.roc:39-41; record_fields.roc:56-57 | comment | records | 0 |
| 81 | records#record-types | Field order is not part of a record's type | none | comment | records | 15 |
| 82 | records#updating-records | Update replaces existing fields at the same type only; cannot add a field (verified mismatch) | none | code | records | 50 |
| 83 | records#updating-records | Update leaves the original unchanged | builder_pattern.roc:298-304; records.roc:17 | comment | records | 0 |
| 84 | records#compared-to-dictionaries | Fields fixed at compile time; use `Dict` for runtime keys | records.roc:42-43 | comment | records | 0 |
| 85 | records#compared-to-dictionaries | A record does not by itself imply stack or heap allocation | records.roc:40-41 | comment | records | 0 |
| 86 | records#open-record-types | `{ name : Str, .. }` accepts records with extra fields; `..rest` names the remainder | none (only the `..rest` pattern, records.roc:23-29) | expect | records | 60 |
| 87 | records#open-record-types | Open records are compile-time polymorphism; every concrete record has a fixed shape | none | comment | records | 20 |
| 88 | records#optional-fields | `label ?: Str`, read with `.?label` giving `Try(Str, [MissingField])`; `??` gives a fallback | record_fields.roc:6-41; language.md:49-50 | expect | record_fields | 0 |
| 89 | records#optional-fields | Optional fields are allowed on structural record aliases (unlike defaults) | json.roc:196 (implicit) | comment | record_fields | 15 |
| 90 | records#optional-fields | `person.?address.city` chains through required fields; the whole access is a `Try` | none | expect | record_fields | 50 |
| 91 | records#nominal-records | Associated constants in the methods block (`origin : Point`), used as `Point.origin` | none | code | nominal | 30 |
| 92 | records#nominal-records | Opaque record: other modules cannot read fields, build with a literal, or destructure | opaque.roc:1-6 | comment | opaque | 0 |
| 93 | records#defaulted-fields | `field : T ?? default`, nominal only, omitted field reads as default | record_fields.roc:3-36; types.roc:51-57 | expect | record_fields | 0 |
| 94 | records#defaulted-fields | `T.{}` builds a nominal record with every defaulted field omitted | none | expect | record_fields | 30 |
| 95 | records#defaulted-fields | Default expressions may be blocks or pure calls, evaluated per construction that omits them | none | code | record_fields | 40 |
| 96 | records#defaulted-fields | Defaults cannot run effects, constrain type parameters, or depend on each other cyclically | none | comment | record_fields | 35 |
| 97 | records#defaulted-fields | Defaulted is always present; optional preserves presence and reads as `Try` | record_fields.roc:3-9 | comment | record_fields | 0 |
| 98 | records#runtime-layout | Record is one inline C-struct-like aggregate; names and annotation not stored at runtime | records.roc:39-41 | comment | records | 0 |
| 99 | records#runtime-layout | Memory order: decreasing alignment class, then alphabetical; not source order; nominal records same by default | none (contradicted by platforms.roc:193-200) | comment | platforms | 40 |
| 100 | records#runtime-layout | `_ : {}` in a nominal record selects declared-order layout and takes no bytes | none | code | platforms | 50 |
| 101 | records#runtime-layout | Unnamed or `_reserved` field of nonempty type is padding, alignment 1; only in nominal records | none | code | platforms | 50 |
| 102 | records#runtime-layout | Size/alignment of Str, List, Box differ on 32 vs 64 bit (12/4 vs 24/8) | none | comment | platforms | 50 |
| 103 | records#runtime-layout | Use generated glue as the layout source of truth | compiler.roc:129-131 | comment | compiler | 0 |
| 104 | records#empty-record | Namespace module: back it with `[]` so no value can exist | platforms.roc:115-153 (contradicted by imports.roc:58) | code | imports | 0 |
| 105 | records#empty-record | `{}` is a closed empty record with one value; `{ .. }` accepts any record | none | comment | records | 20 |
| 106 | tuples#tuples | "Tuples are stack-allocated and not reference-counted" | none (contradicts records.roc:40-41) | prose-only | none (do not add) | 0 |
| 107 | tuples#tuple-literals | A tuple has at least two elements; `(42)` is just grouping | none | comment | tuples | 20 |
| 108 | tuples#accessing-tuple-elements | `.0`/`.1` zero-based access | tuples.roc:15-21; language.md:28 | code | tuples | 0 |
| 109 | tuples#accessing-tuple-elements | Access chains: `nested.0.1`, `get_point().0` | none | expect | tuples | 30 |
| 110 | tuples#accessing-tuple-elements | Index must be an integer literal, checked at compile time; no computed index | none | comment | tuples | 20 |
| 111 | tuples#destructuring-tuples | Destructure in assignment and match | tuples.roc:7-30 | code | tuples | 0 |
| 112 | tuples#tuples-vs-records | Tuples have no optional fields and no update syntax | none | comment | tuples | 15 |
| 113 | tuples#tuples-vs-records | Prefer records past two or three elements or unclear positions | none | comment | idioms | 30 |
| 114 | naming#lowercase-names | Identifiers are ASCII only: letters, digits, underscores | none | comment | NEW:naming | 15 |
| 115 | naming#lowercase-names | `$` is part of the name (`$count` differs from `count`) and is only for `var` | partial: language.md:15; loops.roc:3-5 | comment | loops | 15 |
| 116 | naming#lowercase-names / naming#unused-names | Referencing a `_name` gives a warning that the underscore misleads | none | comment | NEW:naming | 20 |
| 117 | naming#lowercase-names | Type variables, record fields, package shorthands may not contain `$` or `!` | none | comment | NEW:naming | 20 |
| 118 | naming#unused-names | Unused locals, arguments and pattern bindings warn; top-level names never do | none (language.md:16 gives `_name` only) | comment | NEW:naming | 25 |
| 119 | naming#shadowing | Shadowing and same-scope redefinition are warnings, not errors (verified "duplicate definition" warning) | none | code | NEW:naming | 40 |
| 120 | naming#constants | Top-level constants are evaluated at compile time when possible | partial: json.roc:113-114; dbg_crash.roc:4 | comment | functions | 20 |
| 121 | naming#var-keyword | `var` is not allowed at module top level | none | comment | loops | 15 |
| 122 | naming#var-keyword | A nested lambda can read but not reassign a `var` | loops.roc:111-113; language.md:127-128 | comment | loops | 0 |
| 123 | naming#var-keyword | A lambda sees the `var` value from when it was defined, not later values (verified) | none | expect | loops | 60 |
| 124 | naming#dollar-prefix | Warnings for `var` without `$` and for `$name` without `var` | none | comment | loops | 20 |
| 125 | naming#type-variables | `_elem` or `_` in an annotation marks a type unrelated to any other | partial: types.roc:47-49 (`_` = infer) | comment | types | 25 |
| 126 | naming#parameterized-type-aliases | Alias type parameters must be named; `Pair(_)` is an error (verified) | partial: idioms.roc:67-68 (bare `..` rejected) | comment | types | 20 |
| 127 | naming#module-names | Type module file name equals its type; other modules unrestricted | language.md:116-117 | comment | imports | 0 |
| 128 | naming#module-names | Package shorthand is a lowercase name chosen by the importer (`import json.Parser`) | imports.roc:36-42 | comment | imports | 0 |
| 129 | naming#as | `as` in patterns: `Ok(n) as result` binds the payload and the whole value | none (list form only, list_patterns.roc:11) | expect | pattern_matching | 40 |

## (a) Disagreements

| # | langref claim | our claim | notes |
| --- | --- | --- | --- |
| D1 | records.md:314: structural record memory order is by alignment class, then alphabetical, not source order; nominal records use the same rule by default | platforms.roc:193-200: the compiler reads host-returned record fields "in the order that the Roc source declares them"; reordering causes segfaults | Real conflict on ABI. Not verified. compiler.roc:129-131 says to trust generated glue, which both sides accept. |
| D2 | tuples.md:5 "Tuples are stack-allocated and not reference-counted"; tuples.md:90 "neither one involves a heap allocation" | records.roc:40-41 "The compiler decides whether a record is on the stack or the heap"; records.md:128 agrees with the topic | Langref contradicts itself; our topic follows records.md. Do not port the tuples claim. |
| D3 | records.md:353 and types.md:211: back a namespace module with `[]` (uninhabited) | imports.roc:58 uses `FooBar :: {}.{ ... }`; platforms.roc:115-153 uses `[]` | Topics disagree with each other. imports.roc should use `[]`. |
| D4 | naming.md:174-193: shadowing and same-scope redefinition (`answer = 1` then `answer = 2`) are warnings, and the program runs (verified) | language.md:15 "`$name` ... the only rebindable binding"; loops.roc:5 "Constants ... can never be reassigned" | Soft. True for reassignment, but an agent may read it as "redefinition is a compile error". |
| D5 | types.md:76-78 shows `items : List(a) where [...]` / `items = []` as if top level | types.md:34 says top-level values with free vars are errors; compiler gives "polymorphic value" at top level (verified) | Langref-internal. Port it only as a let-definition. |
| D6 | tag-unions.md:215: `Try(ok, err) := [Ok(ok), Err(err)]` is nominal; structural tags lift into it | tag_unions.roc:4 "the canonical name for `[Ok(a), Err(b)]`"; language.md:46 "`Try(ok, err)` is `[Ok(ok), Err(err)]`" | Soft. A value annotated `[Ok(U64), Err(Str)]` passes where `Try(U64, Str)` is expected (verified), so practical impact is small. |
| D7 | naming.md:307-315: `_` / `_elem` in an annotation means "any type, not tied to another" | types.roc:47-49: `_` in a signature means "infer this part" | Framing only. Both are true; a topic can say both in one comment (row 125). |

Not a disagreement, but note: tag-unions.md:93-120 teaches closed `..[]` syntax, which does not parse (verified). The langref flags this itself. idioms.roc:63-64 gives the working alternative (a nominal type).

## (b) Skipped as trivial

| page#section | count | what |
| --- | --- | --- |
| static-dispatch#static-dispatch | 2 | definitions of dispatch, static vs dynamic |
| static-dispatch#equality-and-hashing / #operators / #iteration | 4 | repeated usage examples (`p1 == p2`, `v1 + v2`, `for row in rows`, `next` hook prose) |
| types#types / #type-annotations | 3 | types are inferred; `name : Type` annotation form; repeated type var means same type |
| types#generalization | 1 | number literals default instead of generalizing (duplicate of row 26) |
| types#destructuring-nominal-types | 1 | `|{ x }| x` plain record destructuring |
| types#nested-nominal-types | 1 | "useful for grouping" |
| tag-unions#tags / #structural-tag-unions | 3 | what a tag and a payload are; sum type definition |
| tag-unions#closed-tag-unions | 1 | "rarely useful to application authors" |
| records#records / #record-literals | 3 | record literal syntax, nesting, arbitrary expressions in fields |
| records#compared-to-dictionaries | 3 | heterogeneous fields, lowercase names, Dict lookup returns Try |
| records#structural-records | 2 | `origin = { x: 0, y: 0 }`; functions accept record literals |
| records#empty-record | 1 | `{}` literal and type spelled the same |
| tuples#tuple-literals / #tuple-types | 3 | tuple literal and type syntax, nested tuples |
| tuples#tuples-vs-records | 2 | records self-document; common tuple uses list |
| naming#uppercase-names | 2 | must start uppercase; no underscores stylistically |
| naming#unused-names | 2 | `_` pattern as alternative; a `_name` documents intent |
| naming#constants / #variables-with-var | 2 | constants never change; `var` example loop |
| naming#type-variables / #type-aliases | 3 | descriptive type var names; alias definition; `Pair(Str)` substitution |
| naming#as | 2 | `as` in imports and list patterns (already in imports.roc:18-20, list_patterns.roc:11) |
| Total | 41 | |

## Totals

| measure | value |
| --- | --- |
| ideas (rows) | 129 |
| already covered (0 tokens to add) | 60 |
| excluded on purpose (row 106, contradicted claim) | 1 |
| to add (none or partial coverage) | 68 |
| to add as comment | 41 |
| to add as expect | 16 |
| to add as code | 10 |
| to add as prose-only | 1 (row 43) |
| est. tokens to add | 2,400 |

Partial rows (49, 69, 73, 115, 120, 125, 126 and 31, 66) count under "to add".

Growth by target topic:

| topic | rows added | est. tokens |
| --- | --- | --- |
| types | 17 | 665 |
| tag_unions | 9 | 335 |
| platforms | 4 | 190 |
| records | 6 | 185 |
| nominal | 4 | 180 |
| record_fields | 5 | 170 |
| loops | 5 | 140 |
| NEW:naming | 5 | 120 |
| derived_methods | 2 | 110 |
| pattern_matching | 2 | 110 |
| tuples | 4 | 85 |
| functions | 2 | 45 |
| idioms | 1 | 30 |
| operators | 1 | 20 |
| opaque | 1 | 15 |

Most of the types growth is type-system rules (rank-1, no HKT, no subtyping, generalization, where-clause rules, where-alias rules). They have no topic home today; types.roc is 64 lines. The 30 comment rows of 15 to 40 tokens each are cheap. The 16 expect rows carry most of the cost and most of the value, because they fix syntax that topics do not show yet (`T.(v)`, `..others` pass-through, `Try(_, [])`, `.?a.b`, `Thing : thing`, var capture).
