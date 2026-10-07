// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import * as fs from "node:fs";
import {
  loadLangref,
  mergeLangref,
  overlayPath,
  overlayProblems,
  parseLangrefPage,
  renderLangref,
} from "./langref.ts";

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

test("renderLangref returns the whole page or one section", () => {
  const numbers = pages.get("numbers")!;
  assert.equal(renderLangref(numbers), numbers.raw);

  const ranges = renderLangref(numbers, "ranges");
  assert.ok(ranges);
  assert.match(ranges!, /^## Ranges/);
  assert.match(ranges!, /start\.\.<end/);
  // A section must not bleed into the next heading.
  assert.ok(!ranges!.includes("## Custom Number Types"));

  assert.equal(renderLangref(numbers, "no-such-section"), null);
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

// -----------------------------------------------------------------------------
// The overlay: this server's text for sections that upstream ships as `TODO`.
// -----------------------------------------------------------------------------

const LANGREF_DIR = path.join(ROOT, "corpus", "language", "langref");
const overlayNames = fs.existsSync(path.join(LANGREF_DIR, "local"))
  ? fs
      .readdirSync(path.join(LANGREF_DIR, "local"))
      .filter((f) => f.endsWith(".md"))
      .map((f) => f.replace(/\.md$/, ""))
  : [];

const UPSTREAM_STUB = "# T\n\n## Filled\n\nTODO\n\n## Written\n\nUpstream prose.\n";

test("an overlay fills a TODO section and is marked as ours", () => {
  const { raw, local } = mergeLangref("t", UPSTREAM_STUB, "# T\n\n## Filled\n\nOur prose.\n");
  const page = parseLangrefPage("t", raw);
  const filled = page.sections.find((s) => s.slug === "filled")!;

  assert.deepEqual([...local], ["filled"]);
  assert.equal(filled.isTodo, false);
  assert.match(filled.body, /Our prose\./);
  assert.match(filled.body, /roc-syntax-mcp/);
  assert.match(page.sections.find((s) => s.slug === "written")!.body, /Upstream prose\./);
});

test("upstream prose wins over an overlay that duplicates it", () => {
  const { raw, local } = mergeLangref("t", UPSTREAM_STUB, "# T\n\n## Written\n\nOurs.\n");
  const page = parseLangrefPage("t", raw);

  assert.deepEqual([...local], []);
  assert.match(page.sections.find((s) => s.slug === "written")!.body, /Upstream prose\./);
  assert.deepEqual(
    overlayProblems("t", UPSTREAM_STUB, "# T\n\n## Written\n\nOurs.\n"),
    ["t#written: upstream has written it. Remove it from the overlay"]
  );
});

test("a page upstream ships as a bare stub takes the overlay's own headings", () => {
  const { raw, local } = mergeLangref(
    "t",
    "# T\n\nTODO\n",
    "# T\n\nWhat the page is.\n\n## Invented\n\nOur prose.\n"
  );
  const page = parseLangrefPage("t", raw);

  assert.deepEqual([...local], ["invented"]);
  assert.equal(page.isTodo, false);
  assert.match(page.intro, /What the page is\./);
  assert.deepEqual(page.sections.map((s) => s.slug), ["invented"]);
  assert.deepEqual(overlayProblems("t", "# T\n\nTODO\n", "# T\n\nx\n\n## Invented\n\ny\n"), []);
});

test("an overlay heading that upstream does not have on a written page is a problem", () => {
  const problems = overlayProblems("t", UPSTREAM_STUB, "# T\n\n## Invented\n\nOur prose.\n");
  assert.deepEqual(problems, [
    "t#invented: no such heading upstream, and the page is not a stub",
  ]);
});

test("an empty overlay section is a problem", () => {
  assert.deepEqual(overlayProblems("t", UPSTREAM_STUB, "# T\n\n## Filled\n\nTODO\n"), [
    "t#filled: the overlay section is empty",
  ]);
});

test("every shipped overlay page merges cleanly", () => {
  // Empty since upstream 130536d wrote every stub page. The rules apply to any future overlay page.
  for (const name of overlayNames) {
    const upstream = fs.readFileSync(path.join(LANGREF_DIR, `${name}.md`), "utf-8");
    const overlay = fs.readFileSync(overlayPath(LANGREF_DIR, name), "utf-8");
    assert.deepEqual(overlayProblems(name, upstream, overlay), [], `${name} overlay`);

    const page = pages.get(name)!;
    const ours = page.sections.filter((s) => s.source === "local");
    assert.ok(ours.length > 0, `${name} merged nothing`);
    for (const section of ours) {
      assert.equal(section.isTodo, false, `${name}#${section.slug} is still a placeholder`);
      assert.match(section.body, /roc-syntax-mcp/, `${name}#${section.slug} is unmarked`);
    }
  }
});

test("every link an overlay page writes resolves", () => {
  for (const name of overlayNames) {
    const text = fs.readFileSync(overlayPath(LANGREF_DIR, name), "utf-8");
    for (const [, target] of text.matchAll(/\]\(([^)]+)\)/g)) {
      if (/^https?:/.test(target)) continue;
      const [pageRef, slug] = target.split("#");
      const page = pages.get(pageRef === "" ? name : pageRef);
      assert.ok(page, `${name}: no langref page named ${pageRef}`);
      if (!slug) continue;
      assert.ok(
        page!.sections.some((s) => s.slug === slug),
        `${name}: ${pageRef} has no section ${slug}`
      );
    }
  }
});

test("the merge leaves a blank line before every heading", () => {
  for (const name of overlayNames) {
    const lines = pages.get(name)!.raw.split("\n");
    let inFence = false;
    lines.forEach((line, i) => {
      if (/^\s*```/.test(line)) inFence = !inFence;
      if (inFence || i === 0 || !/^#{1,3} /.test(line)) return;
      assert.equal(lines[i - 1], "", `${name}: no blank line before ${line}`);
    });
  }
});

// The server sends a whole langref page by default, so every read pays for a
// long overlay. The three ceilings come from upstream's own numbers, at the 3.5
// chars per token that the overview budgets use:
//
// | Unit                   | Ceiling | Upstream reference                       |
// |------------------------|---------|------------------------------------------|
// | One overlay section    | 350     | median section 165, p90 524              |
// | The overlay of a page  | 1,600   | 75th-percentile page (tag-unions, 1,566) |
// | The whole overlay      | 12,000  | a third of the 38,000-token mirror       |
test("the overlay stays inside its token budget", () => {
  let total = 0;
  for (const name of overlayNames) {
    for (const section of pages.get(name)!.sections.filter((s) => s.source === "local")) {
      const tokens = Math.ceil(section.body.length / 3.5);
      assert.ok(tokens < 350, `${name}#${section.slug} is ${tokens} tokens`);
    }
    const page = Math.ceil(fs.readFileSync(overlayPath(LANGREF_DIR, name), "utf-8").length / 3.5);
    assert.ok(page < 1600, `the ${name} overlay is ${page} tokens`);
    total += page;
  }
  assert.ok(total < 12000, `the overlay is ${total} tokens`);
});
