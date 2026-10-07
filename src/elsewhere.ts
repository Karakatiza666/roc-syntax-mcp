// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Selects the other corpora that a message names, and the number of matches in
// each.
//
// A pure function that takes all its inputs as arguments, as `resolvePackage`
// does. The important cases are configurations that the shipped registry cannot
// produce, for example a platform with no items, or a workspace that pins a
// platform this server does not load. A test can pass these as arguments.

/** A scope where the caller can retry, and the number of matches there. */
export interface Candidate {
  scope: string;
  count: number;
}

/**
 * Whether a message can name a platform that this workspace does not pin.
 *
 * Each value is correct in a different context, so the caller selects one by
 * name.
 *
 * `pinned` is for a footer on an answer that succeeded. A retry in a corpus that
 * the app cannot compile against leads a model to write code that does not
 * build.
 *
 * `anywhere` is for a total miss. The caller has a name that exists, and the
 * unpinned platform is the answer. A message such as "it is in basic-webserver,
 * which this workspace does not pin" tells the caller why nothing matched.
 */
export type Reach = "pinned" | "anywhere";

export interface ElsewhereQuery {
  /** Every corpus that the message can name. */
  from: readonly string[];
  /** The corpora that the answer already searched. The message does not name them. */
  shown: readonly string[];
  reach: Reach;
  /** The platform in the address space, or null when the workspace pins none. */
  platform: string | null;
  isPlatform: (scope: string) => boolean;
  /** The number of matches for the caller's request in the given scope. */
  count: (scope: string) => number;
}

/**
 * The scopes that the message names, each with the count from `count`.
 *
 * Different answers count different things: name matches, module members or
 * topic hits. So the caller supplies `count`. This function owns the rest of the
 * rule, so that no call site repeats it: which scopes are candidates, and that a
 * scope with a count of 0 is not named.
 */
export function elsewhere(q: ElsewhereQuery): Candidate[] {
  return q.from
    .filter((s) => !q.shown.includes(s))
    .filter((s) => q.reach === "anywhere" || !q.isPlatform(s) || q.platform === null || s === q.platform)
    .map((s) => ({ scope: s, count: q.count(s) }))
    .filter((c) => c.count > 0);
}
