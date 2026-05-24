import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { parseBuiltin } from "./builtin_parser.js";
import { searchBySig } from "./sig_search.js";

const ROOT = path.join(import.meta.dirname, "..");
const items = parseBuiltin(fs.readFileSync(path.join(ROOT, "builtin", "Builtin.roc"), "utf-8")).items;

function find(results: ReturnType<typeof searchBySig>, fullName: string) {
  return results.find((r) => r.item.fullName === fullName);
}

// score 100: exact full-signature match
test("exact full-signature match (score 100)", () => {
  const results = searchBySig(items, "List(a), (a -> b) -> List(b)");
  const m = find(results, "List.map");
  assert.ok(m, "List.map not found");
  assert.strictEqual(m.score, 100);
  assert.strictEqual(m.matchKind, "exact");
});

// score 90: return-type match via leading -> prefix
test("return-type-only search with -> prefix (score 90)", () => {
  const results = searchBySig(items, "-> Bool");
  const m = find(results, "Str.is_empty");
  assert.ok(m, "Str.is_empty not found");
  assert.strictEqual(m.score, 90);
  assert.strictEqual(m.matchKind, "return_type");
});

// score 90: return-type match via leading => prefix (effectful)
test("return-type-only search with => prefix (score 90)", () => {
  const results = searchBySig(items, "=> {}");
  const m = find(results, "List.for_each!");
  assert.ok(m, "List.for_each! not found");
  assert.strictEqual(m.score, 90);
  assert.strictEqual(m.matchKind, "return_type");
});

// score 80: return-type match from a plain (no prefix) query
// Str.count_utf8_bytes : Str -> U64  — only "U64" in the return position
test("return-type match from plain query (score 80)", () => {
  const results = searchBySig(items, "U64");
  const m = find(results, "Str.count_utf8_bytes");
  assert.ok(m, "Str.count_utf8_bytes not found");
  assert.strictEqual(m.score, 80);
  assert.strictEqual(m.matchKind, "return_type");
});

// score 70: exact args match with trailing ->
// List.get : List(item), U64 -> Try(item, [...])
// List.drop_at : List(a), U64 -> List(a)
test("exact args with trailing -> (score 70)", () => {
  const results = searchBySig(items, "List(a), U64 ->");
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
  const results = searchBySig(items, "List(a), (a => {}) =>");
  const m = find(results, "List.for_each!");
  assert.ok(m, "List.for_each! not found");
  assert.strictEqual(m.score, 70);
  assert.strictEqual(m.matchKind, "exact_args");
});

// score 60: exact args match (plain query, return type differs from args)
// keep_if / drop_if / count_if / any / all all take List(a), (a -> Bool)
// but return different types — so return_type check (80) won't fire
test("exact args match (score 60)", () => {
  const results = searchBySig(items, "List(a), (a -> Bool)");
  for (const name of ["List.keep_if", "List.drop_if", "List.any", "List.all"]) {
    const m = find(results, name);
    assert.ok(m, `${name} not found`);
    assert.strictEqual(m.score, 60, `${name} score`);
    assert.strictEqual(m.matchKind, "args");
  }
});

// score 50 (args_prefix) vs 70 (exact_args) in the same result set
// Query "List(a) ->" — functions with exactly List(a) as args → 70;
// functions with List(a) + more args → 50
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
// normArgs = "List(a), b, (b, a -> b)" — starts with "List(a), b"
test("args prefix from plain query (score 50)", () => {
  const results = searchBySig(items, "List(a), state");
  const fold = find(results, "List.fold");
  assert.ok(fold, "List.fold not found");
  assert.strictEqual(fold.score, 50);
  assert.strictEqual(fold.matchKind, "args_prefix");
});

// score 20: substring match (plain query)
test("substring match (score 20)", () => {
  const results = searchBySig(items, "OutOfBounds");
  const m = find(results, "List.get");
  assert.ok(m, "List.get not found");
  assert.strictEqual(m.score, 20);
  assert.strictEqual(m.matchKind, "substring");
});

// score 10: substring match with returnOnly prefix
// "-> OutOfBounds": returnOnly=true; normRet of List.get ≠ "OutOfBounds"
// but the full normSig contains it → substring fallback
test("substring match with -> prefix (score 10)", () => {
  const results = searchBySig(items, "-> OutOfBounds");
  const m = find(results, "List.get");
  assert.ok(m, "List.get not found");
  assert.strictEqual(m.score, 10);
  assert.strictEqual(m.matchKind, "substring");
});
