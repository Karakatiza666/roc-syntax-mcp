// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Hoogle-style structural type-signature search for Roc builtins. The scores
// and the tie-breaks are listed in `docs/design/symbol-search.md`.

export interface SigSearchItem {
  fullName: string;
  signature: string;
  docs: string;
  /** The signature with full type names, from `qualifySignatures`. The search reads it when it is set. */
  qualifiedSignature?: string;
}

export interface SigMatch<T extends SigSearchItem = SigSearchItem> {
  item: T;
  score: number;
  matchKind: string;
}

// Two-char ops first, then dotted UpperIdents, lower idents, `..`, punctuation.
const TOKEN = /->|=>|\.\.|[A-Z]\w*(?:\.[A-Z]\w*)*|[a-z_]\w*|[(),\[\]{}:]|[*]|\S/g;

/**
 * Normalize a Roc type expression for structural comparison:
 * 1. Flatten to one line, then strip any `where` clause.
 * 2. Collapse whitespace, and drop the `..` of an open union or record.
 * 3. Rename type variables (lowercase identifiers) alphabetically in
 *    left-to-right order of first appearance. For example,
 *    `List x, (x -> y) -> List y` and `List a, (a -> b) -> List b` normalize to
 *    the same string.
 *
 * Concrete types (uppercase-starting, possibly module-qualified) and operators
 * stay unchanged.
 */
export function normalizeTypeSig(expr: string): string {
  // A wrapped signature is one type, so flatten it before stripping `where`.
  const flat = expr.replace(/\s+/g, " ").trim();
  const bounded = flat.replace(/\bwhere\b.*$/, "").trim();
  // Nearly every fallible builtin returns an open union, so a caller who writes
  // the closed `[OutOfRange]` is asking the same question as `[OutOfRange, ..]`.
  const collapsed = bounded.replace(/,\s*\.\.(?=\s*[\]}])/g, "");

  const varMap = new Map<string, string>();
  let varCount = 0;

  TOKEN.lastIndex = 0;
  const out: string[] = [];
  let last = 0;
  let m: RegExpExecArray | null;

  while ((m = TOKEN.exec(collapsed)) !== null) {
    if (m.index > last) out.push(collapsed.slice(last, m.index));
    last = m.index + m[0].length;
    const tok = m[0];
    if (/^[a-z]/.test(tok) && tok !== "_") {
      if (!varMap.has(tok)) varMap.set(tok, String.fromCharCode(97 + varCount++));
      out.push(varMap.get(tok)!);
    } else {
      out.push(tok);
    }
  }
  if (last < collapsed.length) out.push(collapsed.slice(last));
  return out.join("");
}

/**
 * The full name of the declared type that `name` refers to in `modulePath`, or
 * null. The innermost module wins: in `Crypto.SHA256.Hasher`, `Hasher` is that
 * type, and in `Str`, `Hasher` is the top-level type.
 */
function resolveType(name: string, modulePath: string, types: ReadonlySet<string>): string | null {
  for (let scope = modulePath; ; scope = scope.slice(0, Math.max(scope.lastIndexOf("."), 0))) {
    const full = scope ? `${scope}.${name}` : name;
    if (types.has(full)) return full;
    if (!scope) return null;
  }
}

/**
 * `signature` with each name of a declared type written as its full name. A
 * module writes its own types without the module, so `Draw.text!` takes a
 * `Frame` and `Text.draw_prepared!` takes a `Draw.Frame`. Both become
 * `Draw.Frame`. A tag stays as written, because a tag and a type can have the
 * same name.
 */
export function qualifyTypeNames(signature: string, modulePath: string, types: ReadonlySet<string>): string {
  const open: string[] = [];
  let prev = "";
  return signature.replace(TOKEN, (tok) => {
    const isTag = open.at(-1) === "[" && (prev === "[" || prev === ",");
    if (tok === "(" || tok === "[" || tok === "{") open.push(tok);
    else if (tok === ")" || tok === "]" || tok === "}") open.pop();
    prev = tok;
    if (isTag || !/^[A-Z]/.test(tok)) return tok;
    return resolveType(tok, modulePath, types) ?? tok;
  });
}

/** Sets `qualifiedSignature` on each value of one corpus whose signature names a type of that corpus by a shorter name. */
export function qualifySignatures(
  items: { kind: string; fullName: string; modulePath: string; signature: string; qualifiedSignature?: string }[]
): void {
  const types = new Set(items.filter((it) => it.kind === "type").map((it) => it.fullName));
  for (const it of items) {
    if (it.kind !== "value") continue;
    const qualified = qualifyTypeNames(it.signature, it.modulePath, types);
    if (qualified !== it.signature) it.qualifiedSignature = qualified;
  }
}

/** A normalized type variable. Normalization renames every variable to a single letter. */
function isVar(token: string): boolean {
  return /^[a-z]$/.test(token);
}

function tokenize(norm: string): string[] {
  return norm.match(TOKEN) ?? [];
}

/** A type name in the query matches the same name, or a full name that ends with it: `Frame` matches `Draw.Frame`. */
function sameToken(q: string, s: string): boolean {
  return q === s || (/^[A-Z]/.test(q) && s.endsWith("." + q));
}

/** Whether the tokens of `q` match the tokens of `s` from index `at`, one by one. */
function matchesAt(q: string[], s: string[], at: number): boolean {
  if (at + q.length > s.length) return false;
  return q.every((t, i) => sameToken(t, s[at + i]));
}

function equalTokens(q: string[], s: string[]): boolean {
  return q.length === s.length && matchesAt(q, s, 0);
}

function containsTokens(s: string[], q: string[]): boolean {
  for (let at = 0; at + q.length <= s.length; at++) if (matchesAt(q, s, at)) return true;
  return false;
}

/**
 * The ends of every balanced type expression starting at `from`, shortest
 * first. A span never crosses a separator at depth 0, so a variable standing
 * for one argument cannot swallow the next one.
 */
function spans(tokens: string[], from: number): number[] {
  const ends: number[] = [];
  let depth = 0;
  for (let i = from; i < tokens.length; i++) {
    const t = tokens[i];
    if (t === "(" || t === "[" || t === "{") depth++;
    else if (t === ")" || t === "]" || t === "}") {
      if (depth === 0) break;
      depth--;
    } else if (depth === 0 && (t === "," || t === "->" || t === "=>")) break;
    if (depth === 0) ends.push(i + 1);
  }
  return ends;
}

/** Backtracking limit. Real queries finish in tens of steps, and the limit only stops a pathological query. */
const UNIFY_STEPS = 5000;

function walk(
  q: string[],
  qi: number,
  s: string[],
  si: number,
  bound: Map<string, string>,
  budget: { left: number }
): boolean {
  if (budget.left-- <= 0) return false;
  if (qi === q.length) return si === s.length;
  const token = q[qi];
  if (!isVar(token)) {
    return si < s.length && sameToken(token, s[si]) && walk(q, qi + 1, s, si + 1, bound, budget);
  }
  const already = bound.get(token);
  for (const end of spans(s, si)) {
    const text = s.slice(si, end).join(" ");
    // One variable, one type: `List a -> a` must not match `List Str -> U64`.
    if (already !== undefined && already !== text) continue;
    const next = already === undefined ? new Map(bound).set(token, text) : bound;
    if (walk(q, qi + 1, s, end, next, budget)) return true;
  }
  return false;
}

/**
 * Whether the signature tokens `s` match the query tokens `q` when the query's
 * type variables act as wildcards. For example, `F32 -> Try(U64, err)` finds
 * `F32 -> Try(U64, [OutOfRange])`. Plain isomorphism matching misses this match,
 * because a variable and a concrete union are different strings however they
 * are renamed.
 *
 * The match is one-directional on purpose. A variable in the signature is not
 * widened, so a query for `-> Try(U64, [NotFound])` does not match every
 * `-> Try(a, b)`.
 */
function unifies(q: string[], s: string[]): boolean {
  // No variable to widen, or a bare variable that matches every signature.
  if (q.length < 2 || !q.some(isVar)) return false;
  return walk(q, 0, s, 0, new Map(), { left: UNIFY_STEPS });
}

/** Equal after normalization, or equal once the query's variables are wildcards. */
function relate(q: string[], norm: string): "" | "_unified" | null {
  const s = tokenize(norm);
  if (equalTokens(q, s)) return "";
  return unifies(q, s) ? "_unified" : null;
}

/**
 * Ties are common. For example, `-> Bool` matches 193 signatures exactly. In
 * file order, undocumented `Encoding.Json` lexer helpers fill the default 10
 * slots. So documented items and items in shallower modules rank first, and
 * then the name keeps the order stable.
 */
function compareMatches(a: SigMatch, b: SigMatch, rank?: (item: SigSearchItem) => number): number {
  if (a.score !== b.score) return b.score - a.score;
  if (rank) {
    const diff = rank(b.item) - rank(a.item);
    if (diff !== 0) return diff;
  }
  return compareItems(a.item, b.item);
}

/** The order of items that rank the same: documented first, then shallower modules, then by name. */
export function compareItems(a: SigSearchItem, b: SigSearchItem): number {
  const aDoc = a.docs.trim() !== "" ? 1 : 0;
  const bDoc = b.docs.trim() !== "" ? 1 : 0;
  if (aDoc !== bDoc) return bDoc - aDoc;

  const aDepth = a.fullName.split(".").length;
  const bDepth = b.fullName.split(".").length;
  if (aDepth !== bDepth) return aDepth - bDepth;

  return a.fullName < b.fullName ? -1 : a.fullName > b.fullName ? 1 : 0;
}

/** Index of the last top-level `->` or `=>` (not nested inside parens/brackets/braces). */
function lastTopLevelArrow(sig: string): number {
  let depth = 0;
  let idx = -1;
  for (let i = 0; i < sig.length - 1; i++) {
    const ch = sig[i];
    if (ch === "(" || ch === "[" || ch === "{") depth++;
    else if (ch === ")" || ch === "]" || ch === "}") depth--;
    else if (depth === 0 && sig[i + 1] === ">" && (ch === "-" || ch === "=")) idx = i;
  }
  return idx;
}

/**
 * The highest score of a `substring` match. Such a match only contains the
 * tokens of the query somewhere in the signature. For example, `-> F32` matches `F32 -> Try(I32, [OutOfRange])`
 * at 10.
 */
export const SUBSTRING_SCORE = 20;

/**
 * Score a single item against the normalized query.
 *
 * Match levels:
 *   100 – exact full-signature match
 *    90 – return-type match (when `returnOnly`)
 *    80 – return-type match (full query)
 *    70 – exact args match, any return type (query ends with `->`)
 *    60 – args-only match
 *    50 – args prefix match (query args appear at start of function args)
 *    20 – substring of full sig (full query)
 *    10 – substring of full sig (returnOnly)
 *
 * A match reached by reading the query's variables as wildcards scores five
 * below its exact counterpart and carries the `_unified` suffix, so a
 * signature that answers the question literally still ranks first.
 */
function scoreItem(
  q: string[],
  normSig: string,
  returnOnly: boolean,
  trailingArrow: boolean,
): { score: number; matchKind: string } {
  if (!returnOnly && !trailingArrow) {
    const full = relate(q, normSig);
    if (full !== null) return { score: full ? 95 : 100, matchKind: `exact${full}` };
  }

  const arrowIdx = lastTopLevelArrow(normSig);
  if (arrowIdx >= 0) {
    // Re-normalize each half independently so type-var numbering resets.
    const normRet = normalizeTypeSig(normSig.slice(arrowIdx + 2).trim());
    const normArgs = normalizeTypeSig(normSig.slice(0, arrowIdx).trim());
    if (returnOnly) {
      const ret = relate(q, normRet);
      if (ret !== null) return { score: ret ? 85 : 90, matchKind: `return_type${ret}` };
      if (containsTokens(tokenize(normSig), q)) return { score: 10, matchKind: "substring" };
    } else if (trailingArrow) {
      const args = relate(q, normArgs);
      if (args !== null) return { score: args ? 65 : 70, matchKind: `exact_args${args}` };
      if (matchesAt(q, tokenize(normArgs), 0)) return { score: 50, matchKind: "args_prefix" };
    } else {
      const ret = relate(q, normRet);
      if (ret !== null) return { score: ret ? 75 : 80, matchKind: `return_type${ret}` };
      const args = relate(q, normArgs);
      if (args !== null) return { score: args ? 55 : 60, matchKind: `args${args}` };
      // Elevated prefix match: query is a prefix of the args (not just anywhere in the sig).
      if (matchesAt(q, tokenize(normArgs), 0)) return { score: 50, matchKind: "args_prefix" };
      if (containsTokens(tokenize(normSig), q)) return { score: 20, matchKind: "substring" };
    }
  } else if (!returnOnly && !trailingArrow && containsTokens(tokenize(normSig), q)) {
    return { score: 20, matchKind: "substring" };
  }

  return { score: 0, matchKind: "" };
}

/**
 * Search `items` for builtins whose signature structurally matches `query`.
 *
 * Prefix `query` with `->` to restrict to return-type matching only.
 * Returns results sorted descending by score, capped at `max`. `rank` orders
 * matches of equal score, higher first, before the default order applies.
 */
export function searchBySig<T extends SigSearchItem>(
  items: T[],
  query: string,
  max = 10,
  rank?: (item: T) => number
): SigMatch<T>[] {
  const raw = query.trim();
  if (!raw) return [];

  const returnOnly = raw.startsWith("->") || raw.startsWith("=>");
  const trailingArrow = !returnOnly && (raw.endsWith("->") || raw.endsWith("=>"));
  const queryExpr = returnOnly ? raw.slice(2).trim()
    : trailingArrow ? raw.slice(0, -2).trim()
    : raw;
  const q = tokenize(normalizeTypeSig(queryExpr));

  const hits: SigMatch<T>[] = [];
  for (const item of items) {
    const normSig = normalizeTypeSig(item.qualifiedSignature ?? item.signature);
    const { score, matchKind } = scoreItem(q, normSig, returnOnly, trailingArrow);
    if (score > 0) hits.push({ item, score, matchKind });
  }

  return hits.sort((a, b) => compareMatches(a, b, rank as ((item: SigSearchItem) => number) | undefined)).slice(0, max);
}
