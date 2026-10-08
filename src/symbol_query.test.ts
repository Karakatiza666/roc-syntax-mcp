// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import { nameQuality, namePattern, parseSymbolQuery } from "./symbol_query.ts";

test("a query splits at its first colon outside brackets", () => {
  const cases: [string, ReturnType<typeof parseSymbolQuery>][] = [
    ["Str.concat", { kind: "name", name: "Str.concat" }],
    ["read_utf8!", { kind: "name", name: "read_utf8!" }],
    // One word is a name. A type of one word needs the colon.
    ["Str", { kind: "name", name: "Str" }],
    [": Str", { kind: "type", type: "Str" }],
    ["ceil :", { kind: "name", name: "ceil" }],
    ["-> F32", { kind: "type", type: "-> F32" }],
    ["List(a), (a -> b) -> List(b)", { kind: "type", type: "List(a), (a -> b) -> List(b)" }],
    // A record field and a `where` clause are inside brackets.
    ["{ x : F32 } -> Str", { kind: "type", type: "{ x : F32 } -> Str" }],
    ["a -> Str where [a.to_str : a -> Str]", { kind: "type", type: "a -> Str where [a.to_str : a -> Str]" }],
    ["ceil : -> F32", { kind: "both", name: { raw: "ceil", module: "", part: "ceil" }, type: "-> F32" }],
    ["read! : Str => _", { kind: "both", name: { raw: "read!", module: "", part: "read!" }, type: "Str => _" }],
    ["F32.ceil : F32 ->", { kind: "both", name: { raw: "F32.ceil", module: "F32", part: "ceil" }, type: "F32 ->" }],
    ["Path. : => Bool", { kind: "both", name: { raw: "Path.", module: "Path", part: "" }, type: "=> Bool" }],
  ];
  for (const [query, want] of cases) assert.deepEqual(parseSymbolQuery(query), want, query);
  assert.equal(parseSymbolQuery("foo bar : Str").kind, "error");
  assert.equal(parseSymbolQuery("  ").kind, "error");
});

test("an uppercase last segment names a module only", () => {
  assert.deepEqual(namePattern("F32"), { raw: "F32", module: "F32", part: "" });
  assert.deepEqual(namePattern("Num.F32"), { raw: "Num.F32", module: "Num.F32", part: "" });
});

test("name quality ranks the whole name, then a prefix, then a word, then any substring", () => {
  const p = namePattern("ceil");
  const q = (name: string, modulePath = "Num.Dec") => nameQuality({ name, modulePath }, p);
  assert.deepEqual(
    ["ceil", "ceiling", "div_ceil_by", "preceil", "floor"].map((n) => q(n)),
    [3, 2, 1, 0, -1]
  );
  // `F32` matches the module path `Num.F32`, and not `Num.F32X`.
  const f32 = namePattern("F32.ceil");
  assert.equal(nameQuality({ name: "ceiling", modulePath: "Num.F32" }, f32), 2);
  assert.equal(nameQuality({ name: "ceiling", modulePath: "Num.F32X" }, f32), -1);
});
