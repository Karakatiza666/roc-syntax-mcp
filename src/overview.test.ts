// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { parseBuiltin } from "./builtin_parser.ts";
import { loadOverview } from "./overview.ts";

const ROOT = path.join(import.meta.dirname, "..");
const OVERVIEW_DIR = path.join(ROOT, "corpus", "language", "overview");
const index = parseBuiltin(fs.readFileSync(path.join(ROOT, "corpus", "language", "Builtin.roc"), "utf-8"));

const language = loadOverview(OVERVIEW_DIR, ["language.md"]);
const builtins = loadOverview(OVERVIEW_DIR, ["builtins.md"]);
const BOTH = ["language.md", "builtins.md"];

/** The estimate used elsewhere in this server: about 3.5 characters per token. */
function tokens(text: string): number {
  return Math.round(text.length / 3.5);
}

// An agent reads the overview at the start of every session, so it must be
// cheap. Over these budgets it has no advantage over the other documents.
test("each page stays inside its token budget", () => {
  assert.ok(tokens(language) < 1800, `language page is ~${tokens(language)} tokens`);
  assert.ok(tokens(builtins) < 1600, `builtins page is ~${tokens(builtins)} tokens`);
  assert.ok(
    tokens(loadOverview(OVERVIEW_DIR, BOTH)) < 3400,
    `both pages are ~${tokens(loadOverview(OVERVIEW_DIR, BOTH))} tokens`
  );
});

test("omitting the scope concatenates the language and builtins pages", () => {
  const both = loadOverview(OVERVIEW_DIR, BOTH);
  assert.ok(both.includes(language) && both.includes(builtins));
  assert.ok(both.length > language.length && both.length > builtins.length);
});

test("a missing page degrades instead of throwing", () => {
  const text = loadOverview(path.join(ROOT, "does-not-exist"), ["language.md"]);
  assert.match(text, /Overview unavailable/);
});

/**
 * Every `Module.method` that the pages mention, in prose and in code. The regex
 * runs over the raw text, not inside backticks, because fenced blocks make it
 * impossible to pair inline backticks.
 */
function qualifiedNames(text: string): string[] {
  const pattern = /\b[A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)*\.[a-z_][a-z_0-9]*!?/g;
  const hits = new Set(text.match(pattern) ?? []);
  // `Builtin.roc` and `Url.roc` are filenames, not methods.
  return [...hits].filter((n) => !n.endsWith(".roc")).sort();
}

// After an upstream rename, the overview is wrong. The overview is not attached
// to the items it describes, as the hints are, so no other test catches this.
test("every builtin the overview names still exists", () => {
  const named = qualifiedNames(language + "\n" + builtins);
  assert.ok(named.length > 8, `only ${named.length} qualified names found. The regex is probably broken`);

  const missing = named.filter((n) => !index.byFullName.has(n));
  assert.deepEqual(missing, [], "named in the overview but absent from Builtin.roc");
});

test("every module the overview tabulates still exists", () => {
  const paths = new Set<string>();
  for (const [, span] of builtins.matchAll(/`(Num\.[A-Z][A-Za-z0-9]*|[A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)*)`/g)) {
    if (index.modulePaths.has(span)) paths.add(span);
  }
  // The table names one module per row plus the numeric and SIMD range endpoints.
  assert.ok(paths.size >= 12, `only ${paths.size} module paths recognized`);
  assert.ok(paths.has("Encoding.Json") && paths.has("Crypto.SHA256") && paths.has("Num.U8x16"));
});

// Each count on this page is a number that every refresh must update, and
// `roc-syntax://builtin` already serves the live counts.
test("the builtins page quotes no method counts", () => {
  assert.doesNotMatch(builtins, /\d+ (methods|modules|type declarations)\b/);
  assert.doesNotMatch(builtins, /^\|[^|\n]+\| \d[\d, +-]*( each)? \|/m, "a module row carries a count column");
});

// The pages tell the reader which tool to call next, and a renamed tool makes
// that advice wrong. `resources.test.ts` checks the names against the live tool
// list.
test("the language page points at the server's own verification tools", () => {
  assert.match(language, /roc_check/);
  assert.match(builtins, /get_builtin_module/);
  assert.match(builtins, /search_symbols/);
});

test("neither page is a placeholder", () => {
  for (const [name, text] of [["language", language], ["builtins", builtins]] as const) {
    assert.ok(!/\bTODO\b/.test(text), `${name} page still has a TODO`);
    assert.match(text, /^# Roc /, `${name} page has no heading`);
  }
});
