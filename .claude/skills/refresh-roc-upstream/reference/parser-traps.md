# Builtin parser traps

`src/builtin_parser.ts` reads `corpus/language/Builtin.roc` line by line, and
keeps a stack of module scopes by tab depth. It has no grammar. Upstream
restructures that file freely, so every refresh so far broke the parser. The
failure was always the same: the parser read a record or tag-union body as a
list of method declarations.

The damage gives no error. A phantom method is a body field that the parser
read as a method. It goes into `byFullName` and `byName`, and hides a real
method with the same name. `search_symbols` then returns a record field where a
function belongs.

## Detection recipe

Run this against the refreshed file before you change anything else.

```bash
node --import tsx/esm -e '
import * as fs from "node:fs";
import { parseBuiltin } from "./src/builtin_parser.ts";
const i = parseBuiltin(fs.readFileSync("corpus/language/Builtin.roc", "utf-8"));
const seen = new Map();
for (const it of i.items) seen.set(it.fullName, (seen.get(it.fullName) ?? 0) + 1);
console.log("methods     ", i.items.filter((x) => x.kind === "value").length);
console.log("types       ", i.items.filter((x) => x.kind === "type").length);
console.log("modules     ", i.modulePaths.size);
console.log("no module   ", i.items.filter((x) => !x.modulePath).map((x) => `${x.kind}:${x.name}`));
console.log("duplicated  ", [...seen].filter(([, n]) => n > 1).map(([k]) => k));
'
```

Three signals, from most severe to least severe:

| Signal | Meaning |
|---|---|
| A `value` with an empty `modulePath` | A body leaked above the outermost module. This is always a bug. A `type` with an empty `modulePath` is correct, because it is declared directly inside `Builtin` |
| Any duplicated `fullName` | Two captures collided, and `byFullName` kept the second one without an error |
| A method or type count much higher than in the previous refresh | Phantoms, not growth. Compare against the numbers recorded in `corpus/language/UPSTREAM` |

The counts of the last refresh are in `corpus/language/UPSTREAM`. Some types
have no module, for example `Bool`, `Dict`, `Iter` and `Try`, and that is
expected. The duplicate count is always zero.

Then separate phantoms from real methods. The source line of a record field ends
with a comma. A method declaration is followed by a `name = ...` definition, or
it is a `name : _` derive opt-in with no body. This heuristic is good but not
exact. In the 2026-08 refresh, it flagged 38 items, and 4 of them were real
methods whose signature wrapped onto the next line. Check each flagged item
against its line in `Builtin.roc` before you delete anything.

## The three known causes

The 2026-08 refresh fixed all three. They are listed here because upstream
continues to add new shapes that hit the same three weaknesses. The fixes have
not regressed.

### A. A multi-line type header leaks its body

`Iter(item) :: {` ... `}.{` opens a header that spans several lines. While the
header is open, the top of the stack is still the enclosing module, so the
record fields inside the header go there as methods. This cause produced 14
phantoms, and four of them hid the real `Num.Numeral.*` methods.

Guard: while a header is open and its closing `.{` has not appeared, do not
capture signatures. Clear the pending header when a line at or below its indent
arrives without closing it. `parseBuiltin` tracks this state as `header`.

### B. The continuation loop does not advance the cursor

The loop that adds indented continuation lines to a signature left `i`
unchanged. Thus the main loop read each consumed line again as a separate item.
This cause produced 13 phantoms, all from function arguments shaped as records.

Guard: advance `i` past the consumed lines.

### C. An uppercase type alias with a record body is invisible

A declaration regex that requires a lowercase first letter does not match
`DictData(k, v) : {`. Thus the parser skips the alias line, but captures its
body fields as methods of the parent module. This cause produced 7 phantoms
under `Dict`, and it emitted three of them twice.

Guard: recognize `Uppercase : {` and `Uppercase(params) : {` as the start of an
alias, and skip to the closing brace.

## Two traps in the type-declaration capture

`parseBuiltin` emits type declarations as `kind: "type"` items, and does not
only push them as scopes. Two rules keep that capture correct. If you remove
either rule, the capture fails without an error.

### D. A local annotation inside a function body looks like a type

`Shape : a` is inside an `expect` block at `corpus/language/Builtin.roc:237`,
and it appears five times. The declaration regex matches it in the same way as a
real type. Without a depth rule, the index gets 20 items, all with duplicate
full names, and `Encoding.Json.Shape` resolves to the one parsed last.

Guard: emit a type only when its declaration is exactly one level deeper than
its enclosing module, `indent === stack[top].indent + 1`. A top-level
declaration in a platform module file has an empty stack, so there the rule is
`indent === 0`.

### E. A namespace declaration is not a type

`Str :: [ProvidedByCompiler]`, `Num :: {}` and `Num.U8 :: [].{` declare
modules, not data. If the parser indexes them, `byFullName` gets an empty body
under a name that is also a module path. Then `search_symbols("Str")` answers
`Str :: [ProvidedByCompiler]` and does not fall through to the module.

Guard: skip a body of `[]`, `{}` or `[ProvidedByCompiler]`. Also remove a
trailing `.{}`, which is an empty method block and not part of the type.

## The host-boundary name rule

`isHostBoundary` marks glue methods as `tier: "host"`. Thus they stay out of
app-facing search, but a caller can still address them by name. The patterns
are anchored by design:

| Pattern | Matches | Does not match |
|---|---|---|
| `^(to\|from)_host(_\|$)` | `to_host`, `to_host_config`, `from_host_request` | |
| `_(to\|from)_host$` | `response_to_host`, `timestamp_from_host` | |
| `_for_host!?$` | `respond_for_host!`, `advance_for_host!` | |

A substring rule on `host` would also hide `Server.Authority.host` and
`Url.host`. These read the HTTP Host header, and an app author who routes by
hostname needs them. `src/builtin_parser.test.ts` asserts that both are public.

Measured against basic-webserver 0.16.0, there are 41 host-tier methods. 24 of
them are in modules that the platform exposes (20 in `Server`, 4 in `Sse`), and
0 are in `Builtin.roc`.

## Two rules that are not about phantoms

Both rules add items and do not remove items. Both were added because a corpus
was missing its primary API, and nothing reported an error.

### A module member with no annotation is still a member

The capture that reads `name : sig` finds most of what a platform exports, but
not all of it. basic-cli's `Sqlite.query_many!`, each of its row decoders,
`Tcp.connect!`, `File.open_reader!`, and all 35 of basic-webserver's `Html`
element helpers are declared as a bare `name = |args|`. A second capture finds
them. It uses the lambda head as the signature and sets `unannotated: true`.

That flag has two effects:

- `declLine` prints `name = |a, b|` and not `name : |a, b|`, which would look
  like a type.
- A type query of `search_symbols` skips these items, because it cannot match a
  lambda head by structure.

Guards, in order of what they protect against:

| Guard | Without it |
|---|---|
| Indent is exactly one level inside the module block | Every `cols`, `helper!`, `actual` and `expected` in a function body or an `expect` block becomes a module member |
| The name has no annotated item already | Every annotated method is indexed twice, once from `name : sig` and once from `name = ...` |

`Builtin.roc` annotates everything, so this rule must add nothing there.
`src/builtin_parser.test.ts` asserts the empty set, because the `instructions`
string states the builtin count as a fact.

### Indentation is not always tabs

basic-cli's `InternalSqlite.roc` uses four spaces. A parser that counted only
tabs read every line of it as top-level, and indexed nothing from the file.
`spaceUnit` selects the unit for each file. If a file has any tab indentation,
the parser counts tabs. The parser measures only a file with no tab indentation
in spaces. The parser does not guess about a mix, by design. If a future file
mixes the two, the parser indexes its tab structure and drops its space
structure. The result is an undercount that you can see, not a scrambled tree.

## Testing a fix

`src/builtin_parser.test.ts` asserts properties by derivation where it can, for
example "every item has a module path" and "no duplicate full names". It asserts
by name where a property cannot be derived. Follow that split. A derived
assertion continues to work across refreshes. A fixed list of phantom names
breaks when upstream renames one of them.

Where you must name items, name both sides:

- Phantoms that must be absent, one for each cause.
- Real methods that must remain, including at least one whose signature wraps
  across lines. Assert that this signature is intact, not only present.
- Builtins that upstream deleted, which must not resolve.
- Builtins that upstream added, which must resolve.

Confirm that each new assertion fails against the parser from before the fix.
`git stash` the fix, run the suite, see it fail, and restore the fix. A test
that passes both ways checks nothing.
