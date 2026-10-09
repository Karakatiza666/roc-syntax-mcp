// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The query grammar of `search_symbols`: a name, a type, or both, written as a
// Roc annotation `name : Type`. `docs/design/symbol-search.md` has every rule,
// from the parse to the order of a failed search.

/** A name part: the module filter and the words that the bare name must contain. */
export interface NamePattern {
  /** The name part as written, with a space after a trailing `.` removed. An exact lookup reads it. */
  raw: string;
  /** Empty when the name part names no module. */
  module: string;
  /** Empty when the name part names only a module, as in `Path.` or `F32`. */
  parts: string[];
}

export type SymbolQuery =
  /** One name, which an exact lookup reads first. */
  | { kind: "name"; name: string }
  /** Several words. No symbol has a name of several words, so there is no exact lookup. */
  | { kind: "words"; name: NamePattern }
  | { kind: "type"; type: string }
  | { kind: "both"; name: NamePattern; type: string }
  | { kind: "error"; message: string };

const NAME = /^[A-Za-z_][\w!]*(\.[A-Za-z_][\w!]*)*\.?$/;
/** A word after the first token: lowercase, no module, and `!` only at its end. */
const WORD = /^(?!_!?$)[a-z_]\w*!?$/;
/** Only a type can contain these. */
const TYPE_ONLY = /[()[\]{},]|->|=>|\.\./;

const SHAPE_ERROR =
  "Join a module to the name with a dot, as in `F32.try ceil`. " +
  "Write type arguments in parentheses, as in `: List(a)`.";

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
 * Reads a name part: one name, or a first token and words. Null when the text
 * is not made of names at all, so it can be a type. Words in a wrong shape are
 * an error, because `F32 try` can be a module filter or an old-style type
 * `List a`, and a guess gives a wrong answer that looks right.
 */
function readName(text: string): { kind: "name"; name: string } | { kind: "words"; name: NamePattern } | { kind: "error"; message: string } | null {
  const tokens = text.split(/\s+/).filter(Boolean);
  // `F32. try` is `F32.try`: the exact lookup comes first, and it can only help.
  if (tokens.length > 1 && tokens[0].endsWith(".")) tokens.splice(0, 2, tokens[0] + tokens[1]);
  if (tokens.length === 0 || !tokens.every((t) => NAME.test(t))) return null;
  if (tokens.length === 1) return { kind: "name", name: tokens[0] };
  const [first, ...words] = tokens;
  // Only the first token can name a module, and it must join the first word with a dot.
  if (/^[A-Z]/.test(first.slice(first.lastIndexOf(".") + 1)) || !words.every((w) => WORD.test(w))) {
    return { kind: "error", message: SHAPE_ERROR };
  }
  return { kind: "words", name: namePattern(tokens.join(" ")) };
}

/**
 * Why a type part cannot match, or null. In this Roc, two identifiers that only
 * a space separates are never a type outside a `where` clause, because type
 * arguments are in parentheses.
 */
function typeError(type: string): string | null {
  const body = type.replace(/\bwhere\b[\s\S]*$/, "").trim();
  if (/^[a-z_][\w!]*(\s+[a-z_][\w!]*)+$/.test(body)) {
    return `\`${body}\` is not a type. To search names, put the words before the colon: \`${body} :\`.`;
  }
  const pair = body.match(/(?<![\w.!])([A-Za-z_][\w.!]*)\s+([A-Za-z_][\w!]*)/);
  if (pair) return `\`${pair[0]}\` is not a type. Write type arguments in parentheses, as in \`${pair[1]}(${pair[2]})\`.`;
  return null;
}

/**
 * Splits a query at its first top-level `:`. Without one, a query of names is
 * a name, and anything else is a type. So `Str` is a name, and a type query of
 * one word needs the colon: `: Str`. The design doc has the full table.
 */
export function parseSymbolQuery(query: string): SymbolQuery {
  const raw = query.trim();
  if (!raw || raw === ":") return { kind: "error", message: "Empty query." };
  const colon = topLevelColon(raw);
  if (colon < 0) {
    const name = TYPE_ONLY.test(raw) ? null : readName(raw);
    if (name) return name;
    const bad = typeError(raw);
    return bad ? { kind: "error", message: bad } : { kind: "type", type: raw };
  }
  const namePart = raw.slice(0, colon).trim();
  const type = raw.slice(colon + 1).trim();
  const name = namePart ? readName(namePart) : null;
  if (namePart && !name) {
    return {
      kind: "error",
      message:
        `\`${namePart}\` is not a name. Write \`name : Type\`, where the name is an identifier, a dotted path ` +
        "such as `Str.concat` or `Path.`, or words such as `size window`. Leave the name out to search by type: `: Str`.",
    };
  }
  if (name?.kind === "error") return name;
  if (!type) return name!;
  const bad = typeError(type);
  if (bad) return { kind: "error", message: bad };
  if (!name) return { kind: "type", type };
  return { kind: "both", name: name.kind === "name" ? namePattern(name.name) : name.name, type };
}

/**
 * Reads a name part. An uppercase last segment or a trailing dot names a module
 * only: `F32 : -> Bool` and `F32. : -> Bool` both mean "in `F32`". Words after
 * the first token are more words: `F32.try ceil` is `try` and `ceil` in `F32`.
 */
export function namePattern(raw: string): NamePattern {
  const [first, ...words] = raw.split(/\s+/).filter(Boolean);
  const trimmed = first.endsWith(".") ? first.slice(0, -1) : first;
  const dot = trimmed.lastIndexOf(".");
  const last = trimmed.slice(dot + 1);
  if (first.endsWith(".") || /^[A-Z]/.test(last)) return { raw, module: trimmed, parts: words };
  return { raw, module: dot > 0 ? trimmed.slice(0, dot) : "", parts: [last, ...words] };
}

/** How well `name` contains one word: 3 the whole name, 2 a prefix, 1 after `_`, 0 anywhere, -1 not at all. */
function wordLevel(name: string, word: string): number {
  if (name === word) return 3;
  if (name.startsWith(word)) return 2;
  if (name.includes("_" + word)) return 1;
  return name.includes(word) ? 0 : -1;
}

/**
 * How well an item's name matches `pattern`, or -1 for no match. The match
 * uses case, because in Roc case separates a type from a value. Each word gets
 * a level, and the name gets the lowest one, so every word must match:
 *
 *   3  the whole name, as `floor` matches `floor`
 *   2  a prefix, as `ceil` matches `ceiling`
 *   1  the start of a word after `_`, as `ceil` matches `div_ceil_by`
 *   0  anywhere else in the name
 *
 * A pattern with no words matches every item in its module at level 0.
 */
export function nameQuality(item: { name: string; modulePath: string }, pattern: NamePattern): number {
  const { module, parts } = pattern;
  if (module && item.modulePath !== module && !item.modulePath.endsWith("." + module)) return -1;
  let level = parts.length === 0 ? 0 : 3;
  for (const word of parts) level = Math.min(level, wordLevel(item.name, word));
  return level;
}

/** 1 when the words occur in the name in the order of the query, else 0. So `ceil try` puts `ceil_try` before `try_ceil`. */
export function wordOrder(name: string, pattern: NamePattern): number {
  let from = 0;
  for (const word of pattern.parts) {
    const at = name.indexOf(word, from);
    if (at < 0) return 0;
    from = at + word.length;
  }
  return 1;
}

/** The name level, then the word order, as one number that sorts higher first. -1 for no match. */
export function nameRank(item: { name: string; modulePath: string }, pattern: NamePattern): number {
  const level = nameQuality(item, pattern);
  return level < 0 ? -1 : level * 2 + wordOrder(item.name, pattern);
}
