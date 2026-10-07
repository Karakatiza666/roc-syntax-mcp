// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Hoogle-style structural type-signature search for Roc builtins.

export interface SigSearchItem {
  fullName: string;
  signature: string;
  docs: string;
}

export interface SigMatch {
  item: SigSearchItem;
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

/** A normalized type variable. Normalization renames every variable to a single letter. */
function isVar(token: string): boolean {
  return /^[a-z]$/.test(token);
}

function tokenize(norm: string): string[] {
  return norm.match(TOKEN) ?? [];
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
    return s[si] === token && walk(q, qi + 1, s, si + 1, bound, budget);
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
 * Whether `normSig` matches `normQuery` when the query's type variables act as
 * wildcards. For example, `F32 -> Try(U64, err)` finds
 * `F32 -> Try(U64, [OutOfRange])`. Plain isomorphism matching misses this match,
 * because a variable and a concrete union are different strings however they
 * are renamed.
 *
 * The match is one-directional on purpose. A variable in the signature is not
 * widened, so a query for `-> Try(U64, [NotFound])` does not match every
 * `-> Try(a, b)`.
 */
function unifies(normQuery: string, normSig: string): boolean {
  const q = tokenize(normQuery);
  // No variable to widen, or a bare variable that matches every signature.
  if (q.length < 2 || !q.some(isVar)) return false;
  return walk(q, 0, tokenize(normSig), 0, new Map(), { left: UNIFY_STEPS });
}

/** Equal after normalization, or equal once the query's variables are wildcards. */
function relate(normQuery: string, norm: string): "" | "_unified" | null {
  if (norm === normQuery) return "";
  return unifies(normQuery, norm) ? "_unified" : null;
}

/**
 * Ties are common. For example, `-> Bool` matches 193 signatures exactly. In
 * file order, undocumented `Encoding.Json` lexer helpers fill the default 10
 * slots. So documented items and items in shallower modules rank first, and
 * then the name keeps the order stable.
 */
function compareMatches(a: SigMatch, b: SigMatch): number {
  if (a.score !== b.score) return b.score - a.score;

  const aDoc = a.item.docs.trim() !== "" ? 1 : 0;
  const bDoc = b.item.docs.trim() !== "" ? 1 : 0;
  if (aDoc !== bDoc) return bDoc - aDoc;

  const aDepth = a.item.fullName.split(".").length;
  const bDepth = b.item.fullName.split(".").length;
  if (aDepth !== bDepth) return aDepth - bDepth;

  return a.item.fullName < b.item.fullName ? -1 : a.item.fullName > b.item.fullName ? 1 : 0;
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
  normQuery: string,
  normSig: string,
  returnOnly: boolean,
  trailingArrow: boolean,
): { score: number; matchKind: string } {
  if (!returnOnly && !trailingArrow) {
    const full = relate(normQuery, normSig);
    if (full !== null) return { score: full ? 95 : 100, matchKind: `exact${full}` };
  }

  const arrowIdx = lastTopLevelArrow(normSig);
  if (arrowIdx >= 0) {
    // Re-normalize each half independently so type-var numbering resets.
    const normRet = normalizeTypeSig(normSig.slice(arrowIdx + 2).trim());
    const normArgs = normalizeTypeSig(normSig.slice(0, arrowIdx).trim());
    if (returnOnly) {
      const ret = relate(normQuery, normRet);
      if (ret !== null) return { score: ret ? 85 : 90, matchKind: `return_type${ret}` };
      if (normSig.includes(normQuery)) return { score: 10, matchKind: "substring" };
    } else if (trailingArrow) {
      const args = relate(normQuery, normArgs);
      if (args !== null) return { score: args ? 65 : 70, matchKind: `exact_args${args}` };
      if (normArgs.startsWith(normQuery)) return { score: 50, matchKind: "args_prefix" };
    } else {
      const ret = relate(normQuery, normRet);
      if (ret !== null) return { score: ret ? 75 : 80, matchKind: `return_type${ret}` };
      const args = relate(normQuery, normArgs);
      if (args !== null) return { score: args ? 55 : 60, matchKind: `args${args}` };
      // Elevated prefix match: query is a prefix of the args (not just anywhere in the sig).
      if (normArgs.startsWith(normQuery)) return { score: 50, matchKind: "args_prefix" };
      if (normSig.includes(normQuery)) return { score: 20, matchKind: "substring" };
    }
  } else if (!returnOnly && !trailingArrow && normSig.includes(normQuery)) {
    return { score: 20, matchKind: "substring" };
  }

  return { score: 0, matchKind: "" };
}

/**
 * Search `items` for builtins whose signature structurally matches `query`.
 *
 * Prefix `query` with `->` to restrict to return-type matching only.
 * Returns results sorted descending by score, capped at `max`.
 */
export function searchBySig(items: SigSearchItem[], query: string, max = 10): SigMatch[] {
  const raw = query.trim();
  if (!raw) return [];

  const returnOnly = raw.startsWith("->") || raw.startsWith("=>");
  const trailingArrow = !returnOnly && (raw.endsWith("->") || raw.endsWith("=>"));
  const queryExpr = returnOnly ? raw.slice(2).trim()
    : trailingArrow ? raw.slice(0, -2).trim()
    : raw;
  const normQuery = normalizeTypeSig(queryExpr);

  const hits: SigMatch[] = [];
  for (const item of items) {
    const normSig = normalizeTypeSig(item.signature);
    const { score, matchKind } = scoreItem(normQuery, normSig, returnOnly, trailingArrow);
    if (score > 0) hits.push({ item, score, matchKind });
  }

  return hits.sort(compareMatches).slice(0, max);
}
