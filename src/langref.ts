// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Loads the upstream language reference (corpus/language/langref/*.md) and splits
// each page into sections. The server does not serve these pages. The topics
// carry their ideas, and corpus/language/langref-map.txt names the topics that
// carry each section. src/langref.test.ts holds the map to the sections that
// this parser finds, and scripts/langref-diff.roc splits the pages the same way.

import * as fs from "node:fs";
import * as path from "node:path";

export interface LangrefSection {
  slug: string;   // anchor to address the section by
  title: string;  // heading text, decoration stripped
  level: number;  // 2 for `##`, 3 for `###`
  body: string;   // markdown up to the next heading of any level
  isTodo: boolean;
  parent: string | null; // slug of the enclosing `##`, for a nested `###`
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

/**
 * Parse every `<name>.md` in `dir` into a page, keyed by basename. A file that
 * cannot be read is left out of the map and throws no error.
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
      pages.set(name, parseLangrefPage(name, fs.readFileSync(path.join(dir, file), "utf-8")));
    } catch {
      // A page that cannot be read is absent from the map.
    }
  }
  return pages;
}
