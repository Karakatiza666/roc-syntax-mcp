// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { type BuiltinItem, parseBuiltin } from "./builtin_parser.ts";
import { allHints, hintFor, hintKeys } from "./builtin_hints.ts";

const ROOT = path.join(import.meta.dirname, "..");
const index = parseBuiltin(fs.readFileSync(path.join(ROOT, "corpus", "language", "Builtin.roc"), "utf-8"));

/** A stand-in item, for exercising rules no real builtin currently reaches. */
function item(fullName: string): BuiltinItem {
  const parts = fullName.split(".");
  const name = parts.pop()!;
  return { kind: "value", tier: "public", name, modulePath: parts.join("."), fullName, signature: "_", docs: "", line: 0 };
}

// A hint for a builtin that upstream renamed or removed stops rendering with no
// error, so every key must resolve.
test("every hint key names a builtin that exists", () => {
  const { exact, numeric, universal } = hintKeys();

  for (const fullName of exact) {
    assert.ok(index.byFullName.has(fullName), `EXACT hint for missing builtin: ${fullName}`);
  }

  for (const name of numeric) {
    const found = index.items.some((i) => i.modulePath.startsWith("Num.") && i.name === name);
    assert.ok(found, `NUMERIC hint for a name no Num.* module has: ${name}`);
  }

  for (const name of universal) {
    assert.ok(index.byName.has(name), `UNIVERSAL hint for missing name: ${name}`);
  }
});

test("hints are single-line and short enough to be free", () => {
  for (const hint of allHints()) {
    assert.ok(!hint.includes("\n"), `multi-line hint: ${hint}`);
    assert.ok(hint.length <= 66, `hint is ${hint.length} chars, too long: ${hint}`);
    // Rendered as `# ${hint}` inside a roc block, so a stray `#` reads as a comment.
    assert.ok(!hint.startsWith("#"), `hint starts with #: ${hint}`);
    assert.ok(hint.trim() === hint, `hint has padding: ${JSON.stringify(hint)}`);
  }
});

test("the hinted set is exactly what the three layers declare", () => {
  const { exact, numeric, universal } = hintKeys();
  assert.ok(exact.length > 0 && numeric.length > 0 && universal.length > 0);

  // Derive the expected set from the rules, then compare against what renders.
  // Catches a hint that fails to apply and one that applies too widely.
  const expected = new Set<string>();
  for (const it of index.items) {
    if (
      exact.includes(it.fullName) ||
      (it.modulePath.startsWith("Num.") && numeric.includes(it.name)) ||
      universal.includes(it.name)
    ) {
      expected.add(it.fullName);
    }
  }

  const actual = new Set(index.items.filter((it) => hintFor(it)).map((it) => it.fullName));

  const missing = [...expected].filter((n) => !actual.has(n));
  const extra = [...actual].filter((n) => !expected.has(n));
  assert.deepEqual(missing, [], "declared but not rendered");
  assert.deepEqual(extra, [], "rendered but not declared");

  // The layers reach beyond one item each: NUMERIC covers every numeric width,
  // UNIVERSAL crosses modules.
  assert.ok(
    index.items.filter((it) => it.name === "from_numeral" && hintFor(it)).length > 5,
    "NUMERIC should reach every numeric width"
  );
  assert.deepEqual(
    index.byName.get("subscript")!.filter((it) => hintFor(it)).map((it) => it.fullName).sort(),
    ["Dict.subscript", "List.subscript", "Set.subscript"]
  );

  // Most builtins need no hint at all.
  assert.ok(actual.size < index.items.length / 4, `${actual.size} of ${index.items.length} hinted`);
  assert.strictEqual(hintFor(index.byFullName.get("List.len")!), undefined);
  assert.strictEqual(hintFor(index.byFullName.get("Str.concat")!), undefined);
});

test("layer precedence and scoping", () => {
  const { exact, numeric, universal } = hintKeys();

  // No real builtin exercises EXACT-over-NUMERIC today. Should one appear, add a
  // case for it here rather than trusting the ?? chain.
  const shadowed = exact.filter((k) => k.startsWith("Num.") && numeric.includes(k.split(".").pop()!));
  assert.deepEqual(shadowed, [], "EXACT and NUMERIC overlap. Test which one wins");

  // Every NUMERIC name happens to be Num.*-only upstream, so no real builtin
  // proves the guard holds. Check it against a stand-in item instead.
  for (const name of numeric) {
    if (universal.includes(name)) continue; // UNIVERSAL would answer anyway
    assert.strictEqual(
      hintFor(item(`List.${name}`)),
      undefined,
      `NUMERIC hint for ${name} leaked outside Num.*`
    );
  }

  // UNIVERSAL still applies inside Num.*, where NUMERIC is checked first.
  for (const name of universal) {
    if (numeric.includes(name)) continue;
    assert.ok(hintFor(item(`Num.U8.${name}`)), `UNIVERSAL hint for ${name} lost inside Num.*`);
  }
});

test("hints stay a small fraction of the signature list", () => {
  for (const modulePath of ["List", "Str", "Try", "Num.Dec"]) {
    const methods = index.items.filter((i) => i.modulePath === modulePath);
    const sigs = methods.reduce((n, m) => n + m.name.length + m.signature.length + 4, 0);
    const hints = methods.reduce((n, m) => n + (hintFor(m)?.length ?? 0) + 3, 0);
    assert.ok(
      hints < sigs / 2,
      `${modulePath}: ${hints} chars of hints against ${sigs} of signatures`
    );
  }
});
