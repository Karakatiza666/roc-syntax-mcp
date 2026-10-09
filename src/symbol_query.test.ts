// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import { nameQuality, namePattern, nameRank, parseSymbolQuery } from "./symbol_query.ts";

const pat = (raw: string, module: string, parts: string[]) => ({ raw, module, parts });

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
    ["ceil : -> F32", { kind: "both", name: pat("ceil", "", ["ceil"]), type: "-> F32" }],
    ["read! : Str => _", { kind: "both", name: pat("read!", "", ["read!"]), type: "Str => _" }],
    ["F32.ceil : F32 ->", { kind: "both", name: pat("F32.ceil", "F32", ["ceil"]), type: "F32 ->" }],
    ["Path. : => Bool", { kind: "both", name: pat("Path.", "Path", []), type: "=> Bool" }],
  ];
  for (const [query, want] of cases) assert.deepEqual(parseSymbolQuery(query), want, query);
  assert.equal(parseSymbolQuery("foo-bar : Str").kind, "error");
  assert.equal(parseSymbolQuery("  ").kind, "error");
  assert.equal(parseSymbolQuery(":").kind, "error");
});

// Two identifiers that only a space separates are never a type in this Roc, so
// words are always a name, with or without a colon and a type.
test("words are a name, alone or before a type", () => {
  const cases: [string, ReturnType<typeof parseSymbolQuery>][] = [
    ["size window", { kind: "words", name: pat("size window", "", ["size", "window"]) }],
    ["F32.try ceil", { kind: "words", name: pat("F32.try ceil", "F32", ["try", "ceil"]) }],
    ["F32.try ceil :", { kind: "words", name: pat("F32.try ceil", "F32", ["try", "ceil"]) }],
    ["read utf8!", { kind: "words", name: pat("read utf8!", "", ["read", "utf8!"]) }],
    ["size window : -> F32", { kind: "both", name: pat("size window", "", ["size", "window"]), type: "-> F32" }],
    // The space after a module that ends in `.` joins it to the first word, so the exact lookup runs first.
    ["F32. try", { kind: "name", name: "F32.try" }],
    ["F32. try ceil", { kind: "words", name: pat("F32.try ceil", "F32", ["try", "ceil"]) }],
  ];
  for (const [query, want] of cases) assert.deepEqual(parseSymbolQuery(query), want, query);
});

// A capitalized word after the first token, or a module without its dot, is a
// module filter or an old-style type. A guess gives a wrong answer that looks right.
test("words in a wrong shape are an error that shows the right shape", () => {
  for (const query of ["F32 try ceil", "Str concat", "List a", "ceil F32", "try Ceil", "ceil F32 : Str", "a _"]) {
    const q = parseSymbolQuery(query);
    assert.equal(q.kind, "error", query);
    assert.match((q as { message: string }).message, /`F32\.try ceil`.*`: List\(a\)`/, query);
  }
  const words = parseSymbolQuery(": size window");
  assert.deepEqual(words, { kind: "error", message: "`size window` is not a type. To search names, put the words before the colon: `size window :`." });
  for (const [query, shown] of [[": List a", "List(a)"], ["List a -> a", "List(a)"], ["Dict k v, k -> v", "Dict(k)"]]) {
    const q = parseSymbolQuery(query);
    assert.equal(q.kind, "error", query);
    assert.match((q as { message: string }).message, new RegExp(`as in \`${shown.replace(/[()]/g, "\\$&")}\``), query);
  }
});

test("an uppercase last segment names a module only", () => {
  assert.deepEqual(namePattern("F32"), pat("F32", "F32", []));
  assert.deepEqual(namePattern("Num.F32"), pat("Num.F32", "Num.F32", []));
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
  // Case separates a type from a value.
  assert.equal(nameQuality({ name: "Snapshot", modulePath: "Devices" }, namePattern("snapshot")), -1);
  assert.equal(nameQuality({ name: "Snapshot", modulePath: "Devices" }, pat("Snap", "", ["Snap"])), 2);
});

// Every word must match, so the weakest word sets the level.
test("words take the level of the weakest word, then the order of the query", () => {
  const sw = namePattern("size window");
  assert.equal(nameQuality({ name: "window_size_try", modulePath: "Window" }, sw), 1);
  assert.equal(nameQuality({ name: "window_size", modulePath: "Window" }, namePattern("window size")), 1);
  assert.equal(nameQuality({ name: "window_title", modulePath: "Window" }, sw), -1);
  const ct = namePattern("ceil try");
  const rank = (name: string) => nameRank({ name, modulePath: "Num.F32" }, ct);
  assert.ok(rank("ceil_try") > rank("try_ceil"), "the order of the query breaks a tie");
  assert.equal(nameQuality({ name: "ceil_try", modulePath: "Num.F32" }, namePattern("F32.try ceil")), 1);
  assert.equal(nameQuality({ name: "ceil_try", modulePath: "Num.F64" }, namePattern("F32.try ceil")), -1);
});
