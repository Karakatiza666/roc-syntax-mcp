// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { parseBuiltin } from "./builtin_parser.ts";
import { searchBySig } from "./sig_search.ts";

const ROOT = path.join(import.meta.dirname, "..");
const items = parseBuiltin(fs.readFileSync(path.join(ROOT, "corpus", "language", "Builtin.roc"), "utf-8")).items;

// Assert on the scoring rule, not on where an item lands in a truncated top-N.
const ALL = Number.MAX_SAFE_INTEGER;

function find(results: ReturnType<typeof searchBySig>, fullName: string) {
  return results.find((r) => r.item.fullName === fullName);
}

// score 100: exact full-signature match
test("exact full-signature match (score 100)", () => {
  const results = searchBySig(items, "List(a), (a -> b) -> List(b)", ALL);
  const m = find(results, "List.map");
  assert.ok(m, "List.map not found");
  assert.strictEqual(m.score, 100);
  assert.strictEqual(m.matchKind, "exact");
});

// score 90: return-type match via leading -> prefix
test("return-type-only search with -> prefix (score 90)", () => {
  const results = searchBySig(items, "-> Bool", ALL);
  const m = find(results, "Str.is_empty");
  assert.ok(m, "Str.is_empty not found");
  assert.strictEqual(m.score, 90);
  assert.strictEqual(m.matchKind, "return_type");
});

// score 90: return-type match via leading => prefix (effectful)
test("return-type-only search with => prefix (score 90)", () => {
  const results = searchBySig(items, "=> {}", ALL);
  const m = find(results, "List.for_each!");
  assert.ok(m, "List.for_each! not found");
  assert.strictEqual(m.score, 90);
  assert.strictEqual(m.matchKind, "return_type");
});

// score 80: return-type match from a plain (no prefix) query
// Str.count_utf8_bytes : Str -> U64, with only "U64" in the return position
test("return-type match from plain query (score 80)", () => {
  const results = searchBySig(items, "U64", ALL);
  const m = find(results, "Str.count_utf8_bytes");
  assert.ok(m, "Str.count_utf8_bytes not found");
  assert.strictEqual(m.score, 80);
  assert.strictEqual(m.matchKind, "return_type");
});

// score 70: exact args match with trailing ->
// List.get : List(item), U64 -> Try(item, [...])
// List.drop_at : List(a), U64 -> List(a)
test("exact args with trailing -> (score 70)", () => {
  const results = searchBySig(items, "List(a), U64 ->", ALL);
  const get = find(results, "List.get");
  const dropAt = find(results, "List.drop_at");
  assert.ok(get, "List.get not found");
  assert.strictEqual(get.score, 70);
  assert.strictEqual(get.matchKind, "exact_args");
  assert.ok(dropAt, "List.drop_at not found");
  assert.strictEqual(dropAt.score, 70);
});

// score 70: exact args match with trailing => (effectful)
// List.for_each! : List(item), (item => {}) => {}
test("exact args with trailing => (score 70)", () => {
  const results = searchBySig(items, "List(a), (a => {}) =>", ALL);
  const m = find(results, "List.for_each!");
  assert.ok(m, "List.for_each! not found");
  assert.strictEqual(m.score, 70);
  assert.strictEqual(m.matchKind, "exact_args");
});

// score 60: exact args match (plain query, return type differs from args)
// keep_if / drop_if / count_if / any / all all take List(a), (a -> Bool)
// but return different types, so the return-type check (80) does not match
test("exact args match (score 60)", () => {
  const results = searchBySig(items, "List(a), (a -> Bool)", ALL);
  for (const name of ["List.keep_if", "List.drop_if", "List.any", "List.all"]) {
    const m = find(results, name);
    assert.ok(m, `${name} not found`);
    assert.strictEqual(m.score, 60, `${name} score`);
    assert.strictEqual(m.matchKind, "args");
  }
});

// score 50 (args_prefix) vs 70 (exact_args) in the same result set
// Query "List(a) ->". Functions with exactly List(a) as args → 70.
// Functions with List(a) + more args → 50.
test("args prefix with trailing -> (score 50), ranked below exact_args (70)", () => {
  const results = searchBySig(items, "List(a) ->", 100);
  const rev = find(results, "List.rev");       // args: List(item) exactly → 70
  const append = find(results, "List.append"); // args: List(a), a  → prefix → 50
  assert.ok(rev, "List.rev not found");
  assert.strictEqual(rev.score, 70);
  assert.ok(append, "List.append not found");
  assert.strictEqual(append.score, 50);
  assert.strictEqual(append.matchKind, "args_prefix");
  assert.ok(results.indexOf(rev) < results.indexOf(append), "exact_args should rank above args_prefix");
});

// score 50: args prefix from a plain query
// "List(a), state" normalizes to "List(a), b"
// List.fold : List(item), state, (state, item -> state) -> state
// normArgs = "List(a), b, (b, a -> b)" starts with "List(a), b"
test("args prefix from plain query (score 50)", () => {
  const results = searchBySig(items, "List(a), state", ALL);
  const fold = find(results, "List.fold");
  assert.ok(fold, "List.fold not found");
  assert.strictEqual(fold.score, 50);
  assert.strictEqual(fold.matchKind, "args_prefix");
});

// score 20: substring match (plain query)
test("substring match (score 20)", () => {
  const results = searchBySig(items, "OutOfBounds", ALL);
  const m = find(results, "List.get");
  assert.ok(m, "List.get not found");
  assert.strictEqual(m.score, 20);
  assert.strictEqual(m.matchKind, "substring");
});

// score 10: substring match with returnOnly prefix
// "-> OutOfBounds": returnOnly=true, and normRet of List.get ≠ "OutOfBounds"
// but the full normSig contains it → substring fallback
test("substring match with -> prefix (score 10)", () => {
  const results = searchBySig(items, "-> OutOfBounds", ALL);
  const m = find(results, "List.get");
  assert.ok(m, "List.get not found");
  assert.strictEqual(m.score, 10);
  assert.strictEqual(m.matchKind, "substring");
});

test("a signature wrapped across lines matches on its real return type", () => {
  // `Num.Range.custom` takes a record that spans 9 lines. Only the closing line
  // has `-> Range(bound)`.
  const results = searchBySig(items, "-> Range(a)", ALL);
  const custom = results.find((r) => r.item.fullName === "Num.Range.custom");
  assert.ok(custom, "Num.Range.custom not found");
  assert.strictEqual(custom.score, 90);
  assert.strictEqual(custom.matchKind, "return_type");
});

test("equal scores rank documented builtins above undocumented ones", () => {
  // `-> Bool` matches 193 signatures exactly. File order puts undocumented
  // `Encoding.Json` lexer helpers first, and they fill the default 10 slots.
  const top = searchBySig(items, "-> Bool", 10);
  assert.strictEqual(top.length, 10);
  for (const hit of top) {
    assert.notStrictEqual(hit.item.docs.trim(), "", `${hit.item.fullName} has no docs`);
  }
  assert.ok(
    top.some((h) => h.item.fullName === "Bool.not"),
    "Bool.not should be in the top 10 for `-> Bool`"
  );
});

// A variable in the query stands for any type, not only for another variable.
// Every `_try` builtin returns a concrete `[OutOfRange, ..]`, and no renaming
// makes that union a variable. So `F32 -> Try(U64, err)` needs the wildcard.
test("a variable in the query matches a concrete type (score 95)", () => {
  const results = searchBySig(items, "F32 -> Try(U64, err)", ALL);
  const found = results.map((r) => r.item.fullName).sort();
  assert.deepEqual(found, [
    "Num.F32.ceiling_to_u64_try",
    "Num.F32.floor_to_u64_try",
    "Num.F32.round_to_u64_try",
    "Num.F32.to_u64_try",
  ]);
  assert.strictEqual(results[0].score, 95);
  assert.strictEqual(results[0].matchKind, "exact_unified");
});

// The same question with a literal union. Nearly every fallible builtin in the
// corpus returns an open union.
test("a closed union in the query matches the open union in the signature", () => {
  const results = searchBySig(items, "F32 -> Try(U64, [OutOfRange])", ALL);
  const m = find(results, "Num.F32.to_u64_try");
  assert.ok(m, "Num.F32.to_u64_try not found");
  assert.strictEqual(m.score, 100);
  assert.strictEqual(m.matchKind, "exact");
});

// One variable, one type. Without that rule, a wildcard matches each occurrence
// independently, and `Str, a -> a` matches every function that takes two Strs.
test("a repeated query variable binds to one type", () => {
  const results = searchBySig(items, "Str, a -> a", ALL);
  assert.ok(find(results, "Str.concat"), "Str.concat should match with a = Str");
  const contains = find(results, "Str.contains"); // Str, Str -> Bool
  assert.ok(!contains || contains.matchKind === "substring", "Str.contains must not unify");
});

// The widening runs one way. If the signature's own variables were wildcards
// too, `-> Try(U64, err)` would match every `-> Try(a, b)`. For example,
// `Bool.encode` returns a Try, but never a Try of a U64.
test("a variable in the signature is not widened to the query's concrete type", () => {
  const results = searchBySig(items, "-> Try(U64, err)", ALL);
  assert.ok(results.length > 20, "the query itself stopped matching");
  for (const hit of results) {
    assert.match(hit.item.signature.replace(/\s+/g, " "), /Try\(U64/, `${hit.item.fullName} widened`);
  }
});
