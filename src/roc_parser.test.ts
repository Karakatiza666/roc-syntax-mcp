// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import { parseRocFile } from "./roc_parser.ts";

const names = (src: string) => parseRocFile(src, "/p/Geo.roc", "/p").map((it) => it.fullName);

// Methods are indented inside `Name := [].{ ... }` blocks. A parser that reads
// only column 0 indexes nothing in a type module.
test("methods and types inside a type block are indexed, qualified by the type", () => {
  const src = [
    "Geo := [].{",
    "\t## Scales a point.",
    "\tscale : (F64, F64), F64 -> (F64, F64)",
    "\tscale = |(x, y), k| (x * k, y * k)",
    "",
    "\tPoint : { x : F64, y : F64 }",
    "",
    "\tnorm : Point",
    "\t\t-> F64",
    "\tnorm = |p| p.x",
    "}",
  ].join("\n");
  const items = parseRocFile(src, "/p/Geo.roc", "/p");
  assert.deepEqual(items.map((it) => it.fullName), ["Geo.scale", "Geo.Point", "Geo.norm"]);
  // A name search reads the name and the module, and a type prints with its operator.
  assert.deepEqual([items[1].kind, items[1].name, items[1].modulePath, items[1].decl], ["type", "Point", "Geo", ":"]);
  assert.equal(items[0].docs, "Scales a point.");
  assert.equal(items[0].file, "Geo.roc");
  assert.equal(items[0].line, 3);
  assert.equal(items[2].signature, "Point\n\t\t-> F64");
});

test("top-level annotations are still indexed", () => {
  const src = "parse : Str -> U64\nparse = |s| s.count_utf8_bytes()\n";
  assert.deepEqual(names(src), ["parse"]);
});

// A local annotation in a body and a record field in a header are not
// declarations of the module. `main!` and `local` are declarations, with no
// annotation.
test("annotations nested in a body or a header are left out", () => {
  const src = [
    "app [main!] {",
    "\tpf: platform \"x\",",
    "}",
    "main! = |_args| {",
    "\tn : U64",
    "\tn = 1",
    "\tOk({})",
    "}",
    "Geo := [].{",
    "\tlocal = |s| {",
    "\t\tinner : Str -> Str",
    "\t\tinner = |c| c",
    "\t\tinner(s)",
    "\t}",
    "}",
  ].join("\n");
  assert.deepEqual(names(src), ["main!", "Geo.local"]);
});

// A search by name must find a function that the author did not annotate.
test("an unannotated value is indexed with its lambda head", () => {
  const items = parseRocFile("Geo := [].{\n\thelper = |a| a\n\tport = 8080\n}\n", "/p/Geo.roc", "/p");
  assert.deepEqual(
    items.map((it) => [it.fullName, it.signature, it.unannotated, it.line]),
    [["Geo.helper", "|a|", true, 2], ["Geo.port", "(no type annotation)", true, 3]]
  );
});
