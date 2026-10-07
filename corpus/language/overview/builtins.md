# Roc builtins in one page

Every builtin module is in scope with no import, and all of them come from one
`Builtin.roc`. That file is hundreds of thousands of tokens, so never ask for
it whole. Use `get_builtin_module Str` (signatures only), `lookup_builtin
Str.concat` (one method with its docs), `lookup_builtin Try` (a type with its
variants), or `search_builtin_signatures` (search by type).

## Suffix conventions

Most of the API is one root name plus a suffix. Learn the suffixes first.

| Suffix | Meaning |
| --- | --- |
| `_try` | returns a `Try`. The bare form crashes instead (`plus` on overflow, `div_by` on a zero divisor) |
| `_wrap` | wraps on overflow. Shifts take the count modulo the bit width |
| `_saturated` | clamps at `highest` / `lowest` |
| `to_<T>` | infallible widening conversion. `to_<T>_try` when the value may not fit, `to_<T>_wrap` to truncate |
| `!` | the effectful twin of a pure method (`map_try!`, `for_each!`, `collect!`) |
| `keep_` / `drop_` | keep or discard by predicate. `keep_if` is filter, `keep_oks` is filter-map |
| `_rev` | walks backwards in place, where `rev` allocates a reversed copy |

## Modules

| Module | Contents |
| --- | --- |
| `Str` | UTF-8 text. `from_utf16_*` and `from_utf32_*` decode the wide encodings, with `_le`, `_be` and `_bom` variants. Counts and cuts are in bytes (`count_utf8_bytes`, `iter_utf8`, `drop_first_bytes`). Case folding and caseless compares are ASCII-only. `inspect` renders any value for debugging. |
| `List` | Growable array. `fold`/`fold_until`/`fold_rev`, `map_try`, `keep_oks`, `find_first`, `split_*`, `chunks_of`. `sort`/`sort_by`/`sort_with`, each with a `_reversed` twin, order by `[Before, Same, After]`. |
| `Dict` `Set` | Hash map and set. Keys need `to_hash` and `is_eq`. Iteration is insertion-ordered until a `remove`. `keep_shared`, `union`/`intersection`/`difference`. |
| `Try` | `map_ok`, `map_err`, `map_both`, `map2`, `on_err` (recover into a new `Try`), `catch` (collapse to a plain value), `ok_or`, `collapse`. Each mapper has a `!` twin. |
| `Num.U8` … `U128`, `I8` … `I128` | The same API for each width: the four arithmetic families, `pow`, `div_ceil_by`/`div_floor_by`/`div_trunc_by`, `mod_by`/`rem_by`, `bitwise_*`, `count_*_bits`, `from_str`/`from_str_prefix`/`to_str`, `to`/`until` range iterators, `is_even`, `order_relative_to`, `plus`/`minus`/`times_overflows`, `highest`/`lowest`. |
| `Num.F32` `F64` `Dec` | Only the bare arithmetic (no `_wrap`, `_saturated`, `_try`, or bitwise), plus `sqrt`, trig, `pi`/`e`/`tau`, and `round_to_*`/`floor_to_*`/`ceiling_to_*`. `Dec` is the default numeric type and a fixed-point I128 scaled by 10^18 (`to_attos`), so it has no `nan` or `infinity`. The floats do. |
| `Num.U8x16` … `I64x2` | SIMD vectors. `splat`, `eq_lanes`/`gt_lanes`, `to_bitmask`, `any_lanes_set`, saturating lane arithmetic, `to_*_bits` reinterpretation. |
| `Iter` `Stream` | Lazy pull iterators, pure and effectful. `for` desugars to `iter`/`next`. `map`, `keep_if`, `fold`, `take_first`, `step_by`, `size_hint`, `custom`. `collect` needs `from_iter` on the target type. `Stream.collect!` drives an effectful one. |
| `Hasher` | The `write_bool`/`write_u64`/`write_str`/`write_bytes` builder that `to_hash` feeds. Not a digest. |
| `Crypto.SHA256` `Crypto.BLAKE3` | `hash(List(U8))` and `hash_chunks(Iter(List(U8)))`, both giving a `Digest` with `to_hex`/`from_hex`/`to_bytes`/`from_bytes`. |
| `Encoding.Json` | `parse`, `to_str`, `to_str_try`, plus the `Default`/`CamelCase`/`TrailingCommas` dialects in `JsonEncoding`. |
| `Bool` `Box` | `Bool` is the tag union `Bool.True`/`Bool.False` plus `not`. `Box.box`/`unbox` move a value to and from the heap. Both copy. |

## First-class protocols

The compiler resolves these methods by name at each call site and can derive
them. Structural types get them free. A nominal (`:=`) or opaque (`::`) type
opts in per method with `method : _` and no body.

| Method | Powers |
| --- | --- |
| `to_hash : T, Hasher -> Hasher` | `Dict` and `Set` keys. Feeds a hasher, does not return a number. Keep it consistent with `is_eq` or lookups miss. |
| `is_eq : T, T -> Bool` | `==` and `!=` |
| `parser_for` / `encoder_for` | Format-agnostic codecs, derived like any other method. JSON has no special case, and another format gets the type for free. Wrapping one repeats its constraint, qualified: `where [a.Encoding.Json.Encodable(err)]`. |
| `to_inspect : T -> Str` | how `Str.inspect` renders the value |
| `iter` / `next` | `for item in value` |
| `from_numeral` / `from_quote` / `from_interpolation` | number and string literals of your own type |
| `map` / `map!` | derived payload mapping on an eligible tag union |

## Traps

- `==` on `F32`/`F64` is the compiler-derived `is_eq`. IEEE 754 equality, where
  `NaN` does not equal itself, is the separate `is_float_eq`.
- `Iter.product` errs on an empty iterator, but `Iter.sum` returns the type's
  `default`, because that default is 0, not 1.
- `subscript` is `get` under a reserved `[...]` operator, not a new operation.
- `List.drop_swap` is the O(1) removal and does not preserve order.
- `List.join` flattens exactly one level.
- `Str.len` only gives a type error, which names `count_utf8_bytes`.
- `get_builtin_module` annotates the surprising methods inline.
