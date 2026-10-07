// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Loads the upstream language reference (corpus/language/langref/*.md) and splits each
// page into sections that a tool can address by name.
//
// Upstream sometimes leaves a section empty, with only "TODO" as its text. To
// fill such a section, put this server's own text for it in
// corpus/language/langref/local/<page>.md. These files are the overlay. This
// module merges an overlay page into its upstream page, but only where upstream
// has a TODO. When upstream writes the section, upstream's text wins and a test
// tells you to delete the overlay copy.

import * as fs from "node:fs";
import * as path from "node:path";

export interface LangrefSection {
  slug: string;   // anchor to address the section by
  title: string;  // heading text, decoration stripped
  level: number;  // 2 for `##`, 3 for `###`
  body: string;   // markdown up to the next heading of any level
  isTodo: boolean;
  parent: string | null; // slug of the enclosing `##`, for a nested `###`
  source: "upstream" | "local"; // who wrote this body
}

export interface LangrefPage {
  name: string;   // file basename without `.md`
  title: string;  // `#` heading
  intro: string;  // text between the `#` heading and the first `##`
  sections: LangrefSection[];
  isTodo: boolean; // no prose on this page yet
  raw: string;
}

/**
 * Prefixes every body that the overlay supplies. A reader can then tell this
 * server's prose from roc-lang/roc's prose wherever a section is quoted: in a
 * whole page, in one section, or in a search hit. The merge inserts the marker,
 * and the overlay files never contain it.
 */
export const OVERLAY_MARKER = "> (roc-syntax-mcp, not yet written upstream)";

/**
 * Upstream headings carry two kinds of decoration: a self-link
 * (`## [`continue`](#continue)`) and an explicit anchor (`{#empty-record}`).
 * Returns the readable title plus the anchor when one was given.
 */
function parseHeading(text: string): { title: string; anchor: string | null } {
  let title = text.trim();
  let anchor: string | null = null;

  const explicit = title.match(/\s*\{#([^}]+)\}\s*$/);
  if (explicit) {
    anchor = explicit[1];
    title = title.slice(0, explicit.index).trim();
  }

  // `[text](target)` -> `text`
  title = title.replace(/\[([^\]]*)\]\([^)]*\)/g, "$1").trim();

  return { title, anchor };
}

function slugify(title: string): string {
  return title
    .toLowerCase()
    .replace(/`/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

/** A section with no prose of its own is a placeholder, not documentation. */
function isTodoBody(body: string): boolean {
  const meaningful = body
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l !== "");
  if (meaningful.length === 0) return true;
  return meaningful.every((l) => /^\(?TODO\b/i.test(l));
}

/**
 * A page can repeat a subsection title under different parents, as tag-unions.md
 * does with two `### Limitations`. Unique slugs keep their bare form so they
 * match the upstream anchor. Only a duplicate slug gets its parent slug as a
 * prefix.
 */
function dedupeSlugs(sections: LangrefSection[]): void {
  const counts = new Map<string, number>();
  for (const s of sections) counts.set(s.slug, (counts.get(s.slug) ?? 0) + 1);

  const taken = new Set<string>();
  for (const s of sections) {
    if ((counts.get(s.slug) ?? 0) > 1) {
      const qualified = s.parent ? `${s.parent}-${s.slug}` : s.slug;
      let candidate = qualified;
      let n = 2;
      while (taken.has(candidate)) candidate = `${qualified}-${n++}`;
      s.slug = candidate;
    }
    taken.add(s.slug);
  }
}

export function parseLangrefPage(name: string, content: string): LangrefPage {
  const lines = content.split("\n");
  let title = name;
  const introLines: string[] = [];
  const sections: LangrefSection[] = [];

  let current:
    | { title: string; anchor: string | null; level: number; body: string[]; parent: string | null }
    | null = null;
  let parentSlug: string | null = null;
  let seenH1 = false;
  let inFence = false;

  const flush = () => {
    if (!current) return;
    const body = current.body.join("\n").trim();
    sections.push({
      slug: current.anchor ?? slugify(current.title),
      title: current.title,
      level: current.level,
      body,
      isTodo: isTodoBody(body),
      parent: current.parent,
      source: "upstream",
    });
    current = null;
  };

  for (const line of lines) {
    // Headings inside a fenced code block are content, not structure.
    if (/^\s*```/.test(line)) inFence = !inFence;

    const heading = inFence ? null : line.match(/^(#{1,3})\s+(.*)$/);
    if (heading) {
      const level = heading[1].length;
      if (level === 1) {
        flush();
        title = parseHeading(heading[2]).title;
        seenH1 = true;
        continue;
      }
      flush();
      const { title: t, anchor } = parseHeading(heading[2]);
      if (level === 2) parentSlug = anchor ?? slugify(t);
      current = { title: t, anchor, level, body: [], parent: level === 3 ? parentSlug : null };
      continue;
    }

    if (current) current.body.push(line);
    else if (seenH1) introLines.push(line);
  }
  flush();
  dedupeSlugs(sections);

  const intro = introLines.join("\n").trim();
  return {
    name,
    title,
    intro,
    sections,
    // A page is a placeholder only when neither its intro nor any section has prose.
    isTodo: isTodoBody(intro) && sections.every((s) => s.isTodo),
    raw: content,
  };
}

/** Where an overlay page lives, given the directory holding the upstream pages. */
export function overlayPath(dir: string, name: string): string {
  return path.join(dir, "local", `${name}.md`);
}

/**
 * Inserts the overlay's bodies into the upstream page text.
 *
 * The merge works on the text, not on the parsed structure, so `page.raw` stays
 * the single source. The resource read, `renderLangref` and search ranking then
 * need no overlay logic. Upstream always wins. A section that upstream has
 * written keeps its prose, and the merge drops the overlay copy.
 * `overlayProblems` reports each dropped copy, so the next refresh deletes it.
 */
export function mergeLangref(
  name: string,
  upstream: string,
  overlay: string
): { raw: string; local: Set<string> } {
  const up = parseLangrefPage(name, upstream);
  const ov = parseLangrefPage(name, overlay);
  const written = new Map(ov.sections.filter((s) => !s.isTodo).map((s) => [s.slug, s]));
  const local = new Set<string>();

  const out: string[] = [];
  let index = -1; // the upstream section that holds the current line
  let skipping = false;
  let inFence = false;

  for (const line of upstream.split("\n")) {
    if (/^\s*```/.test(line)) inFence = !inFence;
    const heading = inFence ? null : line.match(/^(#{1,3})\s+/);

    if (heading) {
      const level = heading[1].length;
      // A filled section ends on its last line of prose, so the next heading
      // needs the blank line upstream's own text would have put there.
      if (out.length > 0 && out[out.length - 1] !== "") out.push("");
      out.push(line);
      if (level === 1) {
        // A page whose intro is a placeholder takes the overlay's intro.
        skipping = isTodoBody(up.intro) && ov.intro !== "";
        if (skipping) out.push("", OVERLAY_MARKER, "", ov.intro);
        continue;
      }
      index += 1;
      const section = up.sections[index];
      const fill = section?.isTodo ? written.get(section.slug) : undefined;
      skipping = fill !== undefined;
      if (fill) {
        out.push("", OVERLAY_MARKER, "", fill.body);
        local.add(section!.slug);
      }
      continue;
    }

    if (!skipping) out.push(line);
  }

  // Headings that only the overlay has. Only a page that upstream ships as a
  // bare stub can have them, and `overlayProblems` enforces this rule.
  for (const section of ov.sections) {
    if (section.isTodo || local.has(section.slug)) continue;
    if (up.sections.some((s) => s.slug === section.slug)) continue;
    out.push("", `${"#".repeat(section.level)} ${section.title}`, "", OVERLAY_MARKER, "", section.body);
    local.add(section.slug);
  }

  return { raw: `${out.join("\n").trimEnd()}\n`, local };
}

/**
 * Lists the problems with an overlay page, each worded as its fix. When upstream
 * writes a section that the overlay fills, that is the expected end state. The
 * problem then tells you to delete the overlay copy.
 */
export function overlayProblems(name: string, upstream: string, overlay: string): string[] {
  const up = parseLangrefPage(name, upstream);
  const ov = parseLangrefPage(name, overlay);
  const problems: string[] = [];

  if (ov.intro !== "" && !isTodoBody(up.intro)) {
    problems.push(`${name}: upstream has written the page intro. Remove it from the overlay`);
  }

  for (const section of ov.sections) {
    if (section.isTodo) {
      problems.push(`${name}#${section.slug}: the overlay section is empty`);
      continue;
    }
    const match = up.sections.find((s) => s.slug === section.slug);
    if (match && !match.isTodo) {
      problems.push(`${name}#${section.slug}: upstream has written it. Remove it from the overlay`);
    }
    if (!match && !up.isTodo) {
      problems.push(`${name}#${section.slug}: no such heading upstream, and the page is not a stub`);
    }
  }

  return problems;
}

/**
 * Parse every `<name>.md` in `dir` into a page, keyed by basename.
 *
 * Where `local/<name>.md` exists beside them, `mergeLangref` merges it in first,
 * and each section from the overlay gets `source: "local"`. A file that cannot
 * be read is left out of the map and throws no error, so one bad page loses
 * only its own entry, not the whole index.
 */
export function loadLangref(dir: string): Map<string, LangrefPage> {
  const pages = new Map<string, LangrefPage>();
  let entries: string[];
  try {
    entries = fs.readdirSync(dir).filter((f) => f.endsWith(".md"));
  } catch {
    return pages;
  }
  for (const file of entries.sort()) {
    const name = file.replace(/\.md$/, "");
    try {
      const upstream = fs.readFileSync(path.join(dir, file), "utf-8");
      let overlay: string | null = null;
      try {
        overlay = fs.readFileSync(overlayPath(dir, name), "utf-8");
      } catch {
        // No overlay for this page, which is the common case.
      }
      if (overlay === null) {
        pages.set(name, parseLangrefPage(name, upstream));
        continue;
      }
      const merged = mergeLangref(name, upstream, overlay);
      const page = parseLangrefPage(name, merged.raw);
      for (const section of page.sections) {
        if (merged.local.has(section.slug)) section.source = "local";
      }
      pages.set(name, page);
    } catch {
      // A page that cannot be read is absent from the index.
    }
  }
  return pages;
}

/** Render a whole page, or one section of it when `slug` is given. */
export function renderLangref(page: LangrefPage, slug?: string): string | null {
  if (!slug) return page.raw;
  const section = page.sections.find((s) => s.slug === slug.toLowerCase());
  if (!section) return null;
  const hashes = "#".repeat(section.level);
  return `${hashes} ${section.title}\n\n${section.body}`.trim();
}
