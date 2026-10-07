// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Checks the authoring skill against the repo that it describes.
//
// A skill is prose, so no build fails when the skill is wrong. These tests
// check what the skill names: every repo path, every `plugin` subcommand and
// every `validate` check. Without them, a rename in the repo makes the skill
// wrong with no error, and an author's model reads the wrong text as fact.
//
// Only `author-roc-plugin` is checked. `refresh-roc-upstream` names paths
// inside the upstream repos that it vendors from, and those paths do not exist
// in this repo.

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { init, staticChecks } from "./plugin_cli.ts";

const ROOT = path.join(import.meta.dirname, "..");
const SKILL = path.join(ROOT, ".claude", "skills", "author-roc-plugin");

/** Every markdown page of the skill, keyed by its path relative to the skill. */
function pages(): Record<string, string> {
  const out: Record<string, string> = {};
  const walk = (dir: string) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const file = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(file);
      else if (entry.name.endsWith(".md")) out[path.relative(SKILL, file)] = fs.readFileSync(file, "utf-8");
    }
  };
  walk(SKILL);
  return out;
}

const inlineCode = (text: string): string[] => [...text.matchAll(/`([^`\n]+)`/g)].map((m) => m[1]);

/** Repo top-level names, so prose like `platform/` is not read as a path. */
const REPO_PATH = /^(src|docs|scripts|corpus|plugins|bin|\.claude)\/|^package\.json$/;

test("every repo path the skill names is there", () => {
  const missing: string[] = [];
  for (const [page, text] of Object.entries(pages())) {
    for (const token of inlineCode(text)) {
      // A placeholder is not a path, and neither is a glob.
      if (token.includes("<") || token.includes("*")) continue;
      const bare = token.split(":")[0];
      if (!REPO_PATH.test(bare)) continue;
      if (!fs.existsSync(path.join(ROOT, bare))) missing.push(`${page}: ${token}`);
    }
  }
  assert.deepEqual(missing, []);
});

// An author never opens a reference page that no page links to. A link to a
// missing page is worse, because it promises detail that does not exist.
test("every reference page is linked, and every link resolves", () => {
  const all = pages();
  const linked = new Set<string>();
  for (const text of Object.values(all)) {
    for (const token of inlineCode(text)) {
      if (token.startsWith("reference/") && token.endsWith(".md")) linked.add(token);
    }
  }
  for (const rel of linked) {
    assert.ok(fs.existsSync(path.join(SKILL, rel)), `${rel} is linked and not there`);
  }
  const present = Object.keys(all).filter((p) => p.startsWith("reference/"));
  assert.deepEqual(
    present.filter((p) => !linked.has(p)),
    []
  );
});

test("every plugin subcommand the skill shows is one the CLI dispatches", () => {
  const commands = new Set(["init", "index", "validate", "inspect", "doctor", "add", "remove", "list"]);
  const shown = new Set<string>();
  for (const text of Object.values(pages())) {
    for (const m of text.matchAll(/(?:roc-syntax-mcp|npm run) plugin (?:-- )?([a-z]+)/g)) shown.add(m[1]);
  }
  assert.deepEqual([...shown].filter((c) => !commands.has(c)), []);
  // The reverse check, because nobody runs a command that the skill does not
  // document.
  assert.deepEqual([...commands].filter((c) => !shown.has(c)), []);
});

// `validate` does all the mechanical checks for an author. If the skill does not
// explain a check that `validate` emits, the author cannot understand that
// failure.
test("every check validate emits is explained in the skill", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "roc-skill-"));
  try {
    // Give the name explicitly. Otherwise `init` takes the name from the temp
    // directory. A manifest with a name that does not load reduces
    // `staticChecks` to one line, and this test then passes with no real check.
    init(dir, { name: "roc-ray" });
    const checks = staticChecks(dir);
    assert.equal(checks[0].status, "ok", `the skeleton did not load: ${checks[0].detail}`);
    const emitted = checks.map((c) => c.name);
    assert.ok(emitted.length > 5, emitted.join(", "));
    const text = fs.readFileSync(path.join(SKILL, "SKILL.md"), "utf-8");
    const documented = new Set(inlineCode(text));
    assert.deepEqual(
      emitted.filter((name) => !documented.has(name)),
      []
    );
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
