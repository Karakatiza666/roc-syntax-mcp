# Bug repros

Each file is a minimal program that shows one defect of the Roc compiler or of
its language reference (langref), found while the langref was rewritten into
the topics. See `docs/plans/langref-rewrite.md`. Every file starts with the
command to run, the expected result and the actual result. All of them were run
with `nightly-2026-10-06-c34079d`, the nightly that this repo bundles. Langref
line numbers refer to `corpus/language/langref/` at the same commit.

```bash
ROC=$(echo "$PWD"/roc_nightly-*/roc)
"$ROC" check --no-color bugs/<file>.roc
```

## The compiler crashes

| File | Result |
|---|---|
| `for-tag-pattern-panic.roc` | `for Ok(x) in xs`, where `xs` also holds `Err`, panics: "instantiation widened a closed tag union" |
| `local-generic-list-crash.roc` | `empty : List(x)` in a block, used at two element types, gives "compile time crash" ("invalid numeric literal") |
| `langref-for-literal-pattern.roc` | A literal pattern in `for` gives "non exhaustive destructure", and also a wrong "compile time crash" ("hit a runtime error") |

## The compiler differs from the langref

| File | Langref | Compiler |
|---|---|---|
| `not-operator-custom-type.roc` | `operators.md:118`: `!x` dispatches to `x.not()` | "type mismatch". `!` takes only a `Bool` |
| `open-union-pass-through.roc` | `tag-unions.md:49`: the `add_blue` example | "type mismatch" |
| `underscore-open-tail.roc` | `tag-unions.md:89`: `..` is the same as `.._` | `.._` does not parse |
| `nominal-union-extension.roc` | `tag-unions.md:138`: a nominal tag union has no `..others` | Compiles |
| `top-level-free-type-variable.roc` | `types.md:33`: a top-level value with a free type variable is an error | Compiles and runs |
| `private-type-reachable/` | `modules.md:31`: a second top-level type in `Url.roc` is visible only inside it | `Url.Hidden` compiles and runs in another module |
| `top-level-capacity.roc` | `compile-time.md:68`: a top-level `List.with_capacity(123)` keeps its capacity | Capacity 0 at runtime, 123 under `roc test` |
| `number-underscores.roc` | `numbers.md:13`: an underscore needs a digit on both sides | `1__0`, `1_` and `0x_5` compile |

## Langref examples that do not compile

| File | Langref | Compiler |
|---|---|---|
| `langref-value-where.roc` | `types.md:77` | "polymorphic value" |
| `langref-echo-hello.roc` | `modules.md:685` | "type mismatch". Echo's `main!` must return a `Try` |
| `langref-reserved-provides/` | `modules.md:479`, `:526` | "invalid hosted section". The `roc__` prefix is reserved |
