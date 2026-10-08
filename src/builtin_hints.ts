// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

/**
 * One-line hints for builtins whose name and signature alone mislead.
 *
 * This server writes these hints, not upstream. They appear only in the
 * signature list from `get_builtin_module`. `search_symbols` and
 * `detail: "full"` return upstream's docstrings unchanged, so a hint never
 * competes with the real docs.
 *
 * Add a hint only when a competent reader would guess wrong from the name and
 * type, and the hint saves a follow-up call. Each hint is distilled from the
 * item's own docstring in `corpus/language/Builtin.roc`, or from
 * `corpus/language/langref/` when the item has no docstring. Keep each hint at
 * 66 characters or fewer.
 *
 * Distilled from UPL-1.0 material, which permits it without condition. The
 * upstream notice is in THIRD-PARTY-NOTICES.md.
 */

import type { BuiltinItem } from "./builtin_parser.ts";

/** Shared by every `List.sort*` entry, because the ordering uses tags, not `<`. */
const SORT_ORDER = "orders by [Before, Same, After], not by < or >";

/** Keyed by full name, for a hint that applies to exactly one builtin. */
const EXACT: Record<string, string> = {
  // List: names that differ from the conventional ones, and order/bounds traps.
  "List.fold": "called reduce or foldl elsewhere",
  "List.fold_rev": "walks last to first, and step takes (item, state)",
  "List.fold_until": "return Break(state) from step to stop early",
  "List.keep_if": "filter: keeps items the predicate returns True for",
  "List.drop_if": "the inverse of keep_if",
  "List.keep_oks": "maps and keeps only the Ok values, dropping Errs",
  "List.join": "concatenates one level only, unlike a deep flatten",
  "List.join_map": "called concat_map elsewhere",
  "List.map_try": "stops at the first Err and returns it",
  "List.drop_swap": "O(1): moves the last item into the gap, breaking order",
  "List.get_wrap": "index is taken modulo the length, so it never overruns",
  "List.split_if": "adjacent or edge delimiters produce empty sublists",
  "List.intersperse": "inserts the separator between items, not around them",
  "List.iter_rev": "walks backwards in place. rev allocates a copy",
  "List.sort": SORT_ORDER,
  "List.sort_by": SORT_ORDER,
  "List.sort_with": SORT_ORDER,
  "List.sort_reversed": SORT_ORDER,
  "List.sort_by_reversed": SORT_ORDER,
  "List.sort_with_reversed": SORT_ORDER,

  // Str: the ASCII-only family, and byte-versus-character counts.
  "Str.with_ascii_lowercased": "ASCII only, so other characters are unchanged",
  "Str.with_ascii_uppercased": "ASCII only, so other characters are unchanged",
  "Str.caseless_ascii_equals": "ignores case for ASCII only",
  "Str.drop_prefix_caseless_ascii": "ignores case for ASCII only",
  "Str.count_utf8_bytes": "bytes, not characters or graphemes",
  "Str.len": "not a length: it only errs, to ask which unit you meant",
  "Str.to_utf8": "UTF-8 code units, not characters",
  "Str.drop_first_bytes": "a cut inside a code point gives Err(BadUtf8)",
  "Str.drop_last_bytes": "a cut inside a code point gives Err(BadUtf8)",
  "Str.split_on": "an empty separator returns the whole string, unsplit",
  "Str.from_utf8_lossy": "each invalid byte run becomes one U+FFFD",
  "Str.from_utf16_bom_lossy": "still a Try: a missing byte order mark is an error",
  "Str.from_utf32_bom_lossy": "still a Try: a missing byte order mark is an error",
  "Str.from_quote": "compiler hook for string literals",
  "Str.from_interpolation": "compiler hook for \"${...}\" interpolation",
  "Str.to_str": "no-op",

  // Dict and Set: the combining operations, and iteration order.
  "Dict.update": "one pass. Ok inserts or updates, Err(Missing) removes",
  "Dict.keep_shared": "intersection, keeping pairs where key AND value match",
  "Dict.remove_all": "drops keys found in the second dict",
  "Dict.join_map": "called concat_map elsewhere. Merges the returned dicts",
  "Dict.iter": "insertion order until a remove reorders the rest",
  "Set.difference": "items of the first set that are absent from the second",
  // A set has no values to get, so its `subscript` is membership, not lookup.
  "Set.subscript": "alias for contains, reserved for a future `[...]` operator",

  // Try: which combinator collapses, and which keeps the Try.
  "Try.ok_or": "returns the default and discards the error",
  "Try.err_or": "the mirror of ok_or, defaulting the Err side",
  "Try.on_err": "recover by returning a new Try. map_err only rewrites",
  "Try.catch": "collapses both sides to one plain value",
  "Try.collapse": "for Try(a, a): returns whichever side holds",
  "Try.map_both": "stays a Try. catch returns a plain value instead",

  // Iterators: laziness, and the sum/product asymmetry.
  "Iter.sum": "the type's default is used only for an empty iterator",
  "Iter.product": "Err on empty, unlike sum, since default is not 1",
  "Iter.custom": "undocumented upstream: builds an Iter from state plus next",
  "Iter.size_hint": "the length when known up front, for pre-sizing",
  "Iter.collect": "the target type must provide from_iter",
  "Stream.map": "lazy: the transform runs only as the stream is driven",
  "Stream.collect!": "drives the effectful stream to completion",

  // Box.
  "Box.box": "copies the value to the heap, so it is not free",
  "Box.unbox": "copies back off the heap, so it is not free",

  // Dec is a fixed-point I128, not a float.
  "Num.Dec.to_attos": "Dec is an I128 scaled by 10^18. This is that integer",
  "Num.Dec.from_attos": "builds a Dec from its raw I128 scaled by 10^18",
  "Num.Dec.from_dec_digits": "compiler hook for literals. Result is non-negative",
};

/** Keyed by method name, applied in every `Num.*` module. */
const NUMERIC: Record<string, string> = {
  to: "inclusive range iterator. until excludes the end",
  until: "exclusive range iterator. to includes the end",
  mod_by: "result is never negative. rem_by follows the dividend",
  rem_by: "follows the dividend's sign. mod_by never goes negative",
  div_trunc_by: "rounds toward zero. div_floor_by rounds toward -infinity",
  div_floor_by: "rounds toward -infinity. div_trunc_by rounds toward zero",
  from_numeral: "compiler hook for literals. Parse user text with from_str",
  from_int_digits: "base-10 digits, most significant first",
  shl_wrap: "the shift count is taken modulo the bit width",
  shr_wrap: "the shift count is taken modulo the bit width",
  shr_zf_wrap: "zero-fill. The count is taken modulo the bit width",
  is_multiple_of: "a zero divisor is True only when the value is zero too",
  order_relative_to: "three-way ordering, returns [Before, Same, After]",
  default: "the type's zero, used by sum on an empty collection",
  range_exclusive_to: "the `..<` operator desugars to this",
  range_inclusive_to: "the `..=` operator desugars to this",
  range_exclusive_from: "undocumented upstream: range-operator support method",
  range_inclusive_from: "undocumented upstream: range-operator support method",
  range_iter: "undocumented upstream: range-operator support method",
  range_len_if_known: "undocumented upstream: range-operator support method",
};

/** Keyed by method name, applied in every module that has it. */
const UNIVERSAL: Record<string, string> = {
  parser_for: "compiler-derived. `_` means the compiler supplies the type",
  encoder_for: "compiler-derived. `_` means the compiler supplies the type",
  subscript: "alias for get, reserved for a future `[...]` operator",
  release_excess_capacity: "shrinks capacity to length, and unwraps seamless slices",
};

/** The hint for one builtin, most specific rule first, or undefined. */
export function hintFor(item: BuiltinItem): string | undefined {
  return (
    EXACT[item.fullName] ??
    (item.modulePath.startsWith("Num.") ? NUMERIC[item.name] : undefined) ??
    UNIVERSAL[item.name]
  );
}

/** Every hint key, so a test can prove none has gone stale. */
export function hintKeys(): { exact: string[]; numeric: string[]; universal: string[] } {
  return {
    exact: Object.keys(EXACT),
    numeric: Object.keys(NUMERIC),
    universal: Object.keys(UNIVERSAL),
  };
}

/** All hint texts, for length and formatting checks. */
export function allHints(): string[] {
  return [...Object.values(EXACT), ...Object.values(NUMERIC), ...Object.values(UNIVERSAL)];
}
