// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { after, test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { type ProjectSignature, type SignatureSource, ProjectIndex, parserSource } from "./project_index.ts";

const GEO = [
  "Geo := [].{",
  "\tscale : (F64, F64), F64 -> (F64, F64)",
  "\tscale = |(x, y), k| (x * k, y * k)",
  "\tpair_up = |a, b| (a, b)",
  "}",
  "",
].join("\n");

const made: string[] = [];
after(() => made.forEach((d) => fs.rmSync(d, { recursive: true, force: true })));

function project(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "roc-project-index-"));
  made.push(dir);
  fs.writeFileSync(path.join(dir, "Geo.roc"), GEO);
  return dir;
}

/** Stands in for a compiler-backed source: a type for every definition. */
function inferred(calls: { n: number }): SignatureSource {
  return {
    name: "fake",
    async index() {
      calls.n++;
      const at = (fullName: string, signature: string, line: number): ProjectSignature => ({
        kind: "value", name: fullName.split(".").pop()!, modulePath: "Geo",
        fullName, signature, docs: "", file: "Geo.roc", line, origin: "inferred",
      });
      return [at("Geo.scale", "(a, b), d -> (a, b)", 3), at("Geo.pair_up", "a, b -> (a, b)", 4)];
    },
  };
}

const byName = (items: ProjectSignature[]) =>
  Object.fromEntries(items.map((it) => [it.fullName, `${it.origin}: ${it.signature}`]));

// The annotation is the author's own wording, and the compiler checks the
// definition against it. An inferred type applies only where no annotation is.
test("an annotation wins over an inferred type, which fills in the rest", async () => {
  const snap = await new ProjectIndex([parserSource, inferred({ n: 0 })]).get(project());
  assert.deepEqual(byName(snap.items), {
    "Geo.scale": "annotated: (F64, F64), F64 -> (F64, F64)",
    "Geo.pair_up": "inferred: a, b -> (a, b)",
  });
  // The order the sources are listed in does not change who wins.
  const reversed = await new ProjectIndex([inferred({ n: 0 }), parserSource]).get(project());
  assert.equal(byName(reversed.items)["Geo.scale"], "annotated: (F64, F64), F64 -> (F64, F64)");
});

// A compiler-backed source costs seconds per project.
test("an unchanged project is answered from the cache, a changed one is indexed again", async () => {
  const dir = project();
  const calls = { n: 0 };
  const index = new ProjectIndex([inferred(calls)]);
  await index.get(dir);
  await index.get(dir);
  assert.equal(calls.n, 1);

  const later = new Date(Date.now() + 5000);
  fs.utimesSync(path.join(dir, "Geo.roc"), later, later);
  await index.get(dir);
  assert.equal(calls.n, 2);

  fs.writeFileSync(path.join(dir, "New.roc"), "x : U64\nx = 1\n");
  await index.get(dir);
  assert.equal(calls.n, 3);
});

test("two calls on the same project share one run", async () => {
  const calls = { n: 0 };
  const index = new ProjectIndex([inferred(calls)]);
  const dir = project();
  await Promise.all([index.get(dir), index.get(dir)]);
  assert.equal(calls.n, 1);
});

// When no compiler runs, or its output format changed, the annotations must
// still be served.
test("a source that fails becomes a note, and the others still answer", async () => {
  const broken: SignatureSource = { name: "lsp", index: async () => { throw new Error("no roc on PATH"); } };
  const absent: SignatureSource = { name: "absent", index: async () => null };
  const snap = await new ProjectIndex([parserSource, broken, absent]).get(project());
  assert.deepEqual(Object.keys(byName(snap.items)), ["Geo.scale"]);
  assert.deepEqual(snap.notes, ["lsp: no roc on PATH"]);
});
