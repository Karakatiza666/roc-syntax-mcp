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

/**
 * Normalize a Roc type expression for structural comparison:
 * 1. Strip `where` clauses; take only the first line.
 * 2. Collapse whitespace.
 * 3. Rename type variables (lowercase identifiers) alphabetically in
 *    left-to-right order of first appearance — so `List x, (x -> y) -> List y`
 *    and `List a, (a -> b) -> List b` normalize to the same string.
 *
 * Concrete types (uppercase-starting, possibly module-qualified) and operators
 * are preserved verbatim.
 */
export function normalizeTypeSig(expr: string): string {
  const firstLine = expr.split("\n")[0].replace(/\bwhere\b.*$/, "").trim();
  const collapsed = firstLine.replace(/\s+/g, " ").trim();

  const varMap = new Map<string, string>();
  let varCount = 0;

  // Two-char ops first, then dotted UpperIdents, lower idents, `..`, punctuation.
  const TOKEN = /->|=>|\.\.|[A-Z]\w*(?:\.[A-Z]\w*)*|[a-z_]\w*|[(),\[\]{}:]|[*]|\S/g;
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
 */
function scoreItem(
  normQuery: string,
  normSig: string,
  returnOnly: boolean,
  trailingArrow: boolean,
): { score: number; matchKind: string } {
  if (!returnOnly && !trailingArrow && normSig === normQuery) return { score: 100, matchKind: "exact" };

  const arrowIdx = lastTopLevelArrow(normSig);
  if (arrowIdx >= 0) {
    // Re-normalize each half independently so type-var numbering resets.
    const normRet = normalizeTypeSig(normSig.slice(arrowIdx + 2).trim());
    const normArgs = normalizeTypeSig(normSig.slice(0, arrowIdx).trim());

    if (returnOnly) {
      if (normRet === normQuery) return { score: 90, matchKind: "return_type" };
      if (normSig.includes(normQuery)) return { score: 10, matchKind: "substring" };
    } else if (trailingArrow) {
      if (normArgs === normQuery) return { score: 70, matchKind: "exact_args" };
      if (normArgs.startsWith(normQuery)) return { score: 50, matchKind: "args_prefix" };
    } else {
      if (normRet === normQuery) return { score: 80, matchKind: "return_type" };
      if (normArgs === normQuery) return { score: 60, matchKind: "args" };
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
    const normSig = normalizeTypeSig(item.signature.split("\n")[0]);
    const { score, matchKind } = scoreItem(normQuery, normSig, returnOnly, trailingArrow);
    if (score > 0) hits.push({ item, score, matchKind });
  }

  return hits.sort((a, b) => b.score - a.score).slice(0, max);
}
