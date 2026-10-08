// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The query grammar of `search_symbols`: a name, a type, or both, written as a
// Roc annotation `name : Type`. `docs/design/symbol-search.md` has every rule,
// from the parse to the order of a failed search.

/** A name part: the module filter and the text that the bare name must contain. */
export interface NamePattern {
  /** The name part as written, which an exact lookup reads. */
  raw: string;
  /** Empty when the name part names no module. */
  module: string;
  /** Empty when the name part names only a module, as in `Path.` or `F32`. */
  part: string;
}

export type SymbolQuery =
  | { kind: "name"; name: string }
  | { kind: "type"; type: string }
  | { kind: "both"; name: NamePattern; type: string }
  | { kind: "error"; message: string };

const NAME = /^[A-Za-z_][\w!]*(\.[A-Za-z_][\w!]*)*\.?$/;

/** The index of the first `:` outside brackets, or -1. The `:` of a record field or a `where` clause is inside brackets. */
function topLevelColon(text: string): number {
  let depth = 0;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === "(" || ch === "[" || ch === "{") depth++;
    else if (ch === ")" || ch === "]" || ch === "}") depth--;
    else if (ch === ":" && depth === 0) return i;
  }
  return -1;
}

/**
 * Splits a query at its first top-level `:`. Without one, a query that is a
 * valid name is a name, and anything else is a type. So `Str` is a name, and a
 * type query of one word needs the colon: `: Str`.
 */
export function parseSymbolQuery(query: string): SymbolQuery {
  const raw = query.trim();
  const colon = topLevelColon(raw);
  if (colon < 0) {
    if (!raw) return { kind: "error", message: "Empty query." };
    return NAME.test(raw) ? { kind: "name", name: raw } : { kind: "type", type: raw };
  }
  const name = raw.slice(0, colon).trim();
  const type = raw.slice(colon + 1).trim();
  if (name && !NAME.test(name)) {
    return {
      kind: "error",
      message:
        `\`${name}\` is not a name. Write \`name : Type\`, where the name is an identifier or a ` +
        "dotted path such as `Str.concat` or `Path.`. Leave the name out to search by type: `: Str`.",
    };
  }
  if (!type) return name ? { kind: "name", name } : { kind: "error", message: "Empty query." };
  return name ? { kind: "both", name: namePattern(name), type } : { kind: "type", type };
}

/**
 * Reads a name part. An uppercase last segment or a trailing dot names a module
 * only: `F32 : -> Bool` and `F32. : -> Bool` both mean "in `F32`".
 */
export function namePattern(raw: string): NamePattern {
  const trimmed = raw.endsWith(".") ? raw.slice(0, -1) : raw;
  const dot = trimmed.lastIndexOf(".");
  const last = trimmed.slice(dot + 1);
  if (raw.endsWith(".") || /^[A-Z]/.test(last)) return { raw, module: trimmed, part: "" };
  return { raw, module: dot > 0 ? trimmed.slice(0, dot) : "", part: last };
}

/**
 * How well an item's name matches `pattern`, or -1 for no match. The match
 * ignores case.
 *
 *   3  the whole name, as `floor` matches `floor`
 *   2  a prefix, as `ceil` matches `ceiling`
 *   1  the start of a word after `_`, as `ceil` matches `div_ceil_by`
 *   0  anywhere else in the name
 *
 * A pattern with no part matches every item in its module at level 0.
 */
export function nameQuality(item: { name: string; modulePath: string }, pattern: NamePattern): number {
  const { module, part } = pattern;
  if (module && item.modulePath !== module && !item.modulePath.endsWith("." + module)) return -1;
  if (!part) return 0;
  const name = item.name.toLowerCase();
  const want = part.toLowerCase();
  if (name === want) return 3;
  if (name.startsWith(want)) return 2;
  if (name.includes("_" + want)) return 1;
  return name.includes(want) ? 0 : -1;
}
