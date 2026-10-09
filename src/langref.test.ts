// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import * as fs from "node:fs";
import { loadLangref, parseLangrefPage } from "./langref.ts";
import { CORE } from "./scopes.ts";
import { topicsFor } from "./topics.ts";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const pages = loadLangref(path.join(ROOT, "corpus", "language", "langref"));

test("every bundled page parses", () => {
  assert.ok(pages.size >= 20, `only ${pages.size} pages loaded`);
  for (const name of ["static-dispatch", "numbers", "operators", "loops", "modules", "types"]) {
    assert.ok(pages.has(name), `${name} missing`);
  }
});

test("H1 becomes the title, not a section", () => {
  const numbers = pages.get("numbers")!;
  assert.equal(numbers.title, "Numbers");
  assert.ok(!numbers.sections.some((s) => s.title === "Numbers"));
});

test("explicit {#anchor} decoration sets the slug and is stripped from the title", () => {
  const records = pages.get("records")!;
  const empty = records.sections.find((s) => s.slug === "empty-record");
  assert.ok(empty, "empty-record section missing");
  assert.equal(empty!.title, "The Empty Record (`{}`)");
});

test("self-link decoration is stripped from the title", () => {
  // statements.md writes: ## [`continue`](#continue) {#continue}
  const cont = pages.get("statements")!.sections.find((s) => s.slug === "continue");
  assert.ok(cont, "continue section missing");
  assert.equal(cont!.title, "`continue`");
  assert.match(cont!.body, /not been implemented yet/);
});

test("TODO-only sections are flagged, substantive ones are not", () => {
  // A synthetic page, because the overlay can fill any real placeholder, and a
  // filled placeholder makes this test fail.
  const page = parseLangrefPage("t", "# T\n\n## Empty\n\nTODO\n\n## Full\n\nProse.\n");
  assert.equal(page.sections.find((s) => s.slug === "empty")!.isTodo, true);
  assert.equal(page.sections.find((s) => s.slug === "full")!.isTodo, false);

  const records = pages.get("records")!;
  assert.equal(records.sections.find((s) => s.slug === "compared-to-dictionaries")!.isTodo, false);

  // A section that only says it is unimplemented is still real documentation.
  assert.equal(pages.get("statements")!.sections.find((s) => s.slug === "continue")!.isTodo, false);
});

test("headings inside fenced code blocks are not sections", () => {
  const page = parseLangrefPage("t", [
    "# Title",
    "intro text",
    "## Real Section",
    "body",
    "```roc",
    "# this is a Roc comment, not a heading",
    "## nor is this",
    "```",
    "more body",
  ].join("\n"));
  assert.deepEqual(page.sections.map((s) => s.slug), ["real-section"]);
  assert.match(page.sections[0].body, /nor is this/);
  assert.equal(page.intro, "intro text");
});

test("slugs are unique within a page", () => {
  for (const page of pages.values()) {
    const seen = new Set<string>();
    const dupes: string[] = [];
    for (const s of page.sections) {
      if (seen.has(s.slug)) dupes.push(s.slug);
      seen.add(s.slug);
    }
    assert.deepEqual(dupes, [], `${page.name} has duplicate slugs`);
  }
});

test("a page with no prose anywhere is marked isTodo", () => {
  // A synthetic page, so the test keeps working when no upstream page is a
  // stub.
  assert.equal(parseLangrefPage("stub", "# Stub\n\nTODO\n\n## One\n\nTODO\n").isTodo, true);

  // Pages with real content are not isTodo, even when some sections are TODO.
  // Upstream wrote the last five stub pages at 130536d, so the overlay is empty.
  for (const name of [
    "numbers", "static-dispatch", "operators", "modules",
    "dictionaries-and-sets", "iterators", "packages", "parsers", "pattern-matching",
  ]) {
    assert.equal(pages.get(name)!.isTodo, false, `${name} should not be isTodo`);
  }

  const partial = parseLangrefPage(
    "partial",
    "# Partial\n\nTODO\n\n## Written\n\nReal prose here.\n"
  );
  assert.equal(partial.isTodo, false);
});

// corpus/language/langref-map.txt names the topics that carry each section of
// the langref, or the reason that a section has none. scripts/langref-diff.roc
// reads it to say which topics a refresh must review. The Roc script splits the
// pages itself, and its `--check-map` holds the map to the same keys, so the two
// parsers must agree.
test("the section map has one line for each langref section, and names language topics", () => {
  const text = fs.readFileSync(path.join(ROOT, "corpus", "language", "langref-map.txt"), "utf-8");
  const rows = text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line !== "" && !line.startsWith("#"))
    .map((line) => {
      const key = line.split(" ")[0];
      return { key, value: line.slice(key.length).trim() };
    });
  const keys = [...pages.values()].flatMap((pg) => [pg.name, ...pg.sections.map((s) => `${pg.name}#${s.slug}`)]);
  const mapped = rows.map((r) => r.key);
  assert.deepEqual(mapped.filter((k) => !keys.includes(k)), [], "the map names keys that the langref does not have");
  assert.deepEqual(keys.filter((k) => !mapped.includes(k)), [], "the map has no line for these sections");
  assert.equal(new Set(mapped).size, mapped.length, "the map has a key twice");

  const topics = topicsFor(CORE).topics;
  for (const { key, value } of rows) {
    if (value.startsWith("skip:")) {
      assert.ok(value.slice("skip:".length).trim() !== "", `${key}: a skip needs a reason`);
      continue;
    }
    const names = value.split(",").map((n) => n.trim()).filter((n) => n !== "");
    assert.ok(names.length > 0, `${key}: names no topic and has no skip`);
    for (const name of names) {
      const meta = topics[name];
      assert.ok(meta && !meta.scope && !meta.package, `${key}: ${name} is not a language topic`);
    }
  }
});
