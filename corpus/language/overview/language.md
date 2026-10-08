# Roc in one page

Pure functional, ML family, eager, fully inferred. No `null`, no exceptions, no
GC (reference counted). Effects come only from the platform that an app runs on.
This is the Zig-based compiler (2026 nightlies), not pre-2025 Roc: `Try`
replaced `Result`, and `value.method()` static dispatch is the normal style.

## Naming and layout

| Form | Meaning |
| --- | --- |
| `snake_case` | values, fields, type variables |
| `UpperCamelCase` | types, tags, modules |
| `name!` | effectful. Its type uses `=>` |
| `$name` | a `var`, the only rebindable binding |
| `_name` | deliberately unused |
| `#` / `##` | comment / doc comment |
| tabs | what `roc fmt` indents with |

## Values

```roc
x = 5                     # unconstrained number literals are Dec
n = 5.U64                 # literal suffix picks the type; 0x5 0o5 0b0101 also work
s = "hi ${name}\n"        # interpolation; a line starting with \\ begins a multi-line string
lst = [1, 2, 3]
rec = { x: 1, y: 2 }      # structural record; { ..rec, y: 3 } to update
tup = ("Roc", 1)          # tup.0, tup.1
t = Ok(5)                 # tag; payloads are positional, and there may be several
f = |a, b| a + b          # function literal; a multi-statement body needs { }
```

## Types

| Form | Meaning |
| --- | --- |
| `Name : Type` | type alias, interchangeable with what it names |
| `Name := [A, B(Str)]` | nominal type, distinct from its backing type |
| `Name :: { k : Str }` | opaque nominal type, backing hidden outside its module |
| `Name(a) : [A, ..a]` | parameterized alias. Lowercase `a` is a type variable |
| `Name := X.{ ... }` | append a method block to a nominal or opaque type |
| `a -> b` / `a => b` | pure / effectful function |
| `_` | let the compiler infer this type |
| `where [a.to_str : a -> Str]` | accept any `a` that provides that method |

`Try(ok, err)` is `[Ok(ok), Err(err)]`. `[Red, Green, ..]` is an open union that
accepts further tags. `..others` binds the rest as a type variable. Return-type
unions are open already. Record fields
can default (`port : U16 ?? 8080`, read as `.port`) or be optional
(`timeout ?: U64`, read as `.?timeout`, giving a `Try`).

## Control flow

```roc
if n == 1 "one" else "other"      # else is required unless the body evaluates to {}
match value {                     # exhaustive
	Ok(x) if x > 0 => "pos"       # guard
	Ok(_) | Err(_) => "other"     # alternatives
}
match lst {
	[] => 0
	[first, .. as rest] => first + rest.len()
}
for item in collection { ... }    # anything with an `iter` method; the loop is {}
while $i < n { ... }
```

`break` leaves the innermost loop. `return` exits the function. `crash "msg"`
aborts. `expect cond` is a test assertion, at top level or inside a body.

## Operators

| Operator | Desugars to | Note |
| --- | --- | --- |
| `+ - *` | `plus minus times` | crash on overflow. `_wrap`/`_saturated`/`_try` variants do not |
| `/` `//` `%` | `div_by` `div_trunc_by` `rem_by` | `%` follows the dividend's sign. `mod_by` never goes negative |
| `== !=` | `is_eq` | `!=` is `is_eq` then `not` |
| `< <= > >=` | `is_lt is_lte is_gt is_gte` | |
| `and` `or` | short-circuiting | no `&&` or `\|\|`, since `\|` opens a lambda |
| `!x` `-x` | `not` `negate` | `!` is prefix-not and suffix-effectful |
| `x?` | unwrap `Ok`, early-return the `Err` | `x ? Tag` or `x ? \|e\| ...` maps the err first |
| `x ?? d` | `d` when `x` is an `Err` | |
| `a..<b` `a..=b` | `range_exclusive_to` `range_inclusive_to` | exclusive, inclusive |
| `x.f(y)` | `f(x, y)`, `f` resolved from `x`'s type | static dispatch, checked at compile time |
| `x \|> f(y)` | `f(x, y)` | for functions not defined on the type |

## Methods the compiler knows

Six are derivable: `is_eq`, `to_hash`, `parser_for`, `encoder_for`, `map`,
`map!`. Structural types get them automatically. A nominal or opaque type opts
in per method when it declares `method : _` with no body. Writing a body instead
defines it by hand, so a type can mix the two. Other well-known names the
compiler calls: the operator methods above, `to_inspect` (`Str.inspect`),
`iter`/`next` (`for`), `from_numeral`/`from_quote`/`from_interpolation`
(literals of your own type).

## Modules

```roc
# The smallest complete program. No header, so it gets the built-in Echo
# platform and runs with `roc main.roc`.
main! = |_args| {
	echo!("Hello, World!\n")  # echo! appends no newline of its own
	Ok({})                     # Echo requires a Try
}
```

```roc
app [main!] { pf: platform "https://...", json: "https://..." }
import pf.Stdout                  # lowercase alias from the header, then the module
import Url.ParseErr as PE         # `.` selects a type nested in a module, `/` a subdirectory
import Http exposing [Request]    # use `Request` unqualified
import "data.json" as data : Str  # embed a file's contents at compile time
```

A capitalized file (`Url.roc`) is a type module. It must define `Url :=` or
`Url ::` at the top level, and that one type is what it exposes. `package [...]
{ ... }` and `platform [...]` head the other module kinds. A headerless file
runs directly under `roc file.roc`, where `echo!` is available without import.

## Where LLMs go wrong

- `Try`/`Ok`/`Err`, never `Result`. `True`/`False` (or `Bool.True`), never lowercase `true`.
- `List.fold` (not `walk` or `reduce`), `keep_if` (not `filter`), `keep_oks`,
  `join_map` (not `concat_map`). Check with `search_symbols`.
- There is no `continue` yet, only `break`.
- A `var` is reassignable only inside the function that declared it, so a lambda
  cannot mutate it. Use a `for` loop.
- `for` patterns must be exhaustive: bind the whole item and `match` inside.
- Errors go in the `Try` err position as an anonymous tag union, or `_`.
  Declaring an error type is the exception.
- For a worked example, call `search_roc_syntax` with a construct name, with
  `idioms` to choose a construct, or with `scripting` for a complete standalone
  `.roc` utility. For a whole program that compiles, call `get_roc_syntax`.
- Type-check with the `roc_check` tool before claiming any of this compiles.
- Old `roc` CLI flags are wrong. See the `compiler` topic or `roc <cmd> --help`.
