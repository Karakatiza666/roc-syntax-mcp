// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The words of a free-text question, as `get_roc_syntax(topic:)` and the docs
// fallback of `search_symbols` read them.

/**
 * Splits a name or a question into lowercase words.
 *
 * Each character that is not a letter or a digit is a separator, so
 * `key_pressed` and "key pressed" give the same words.
 */
export function words(text: string): string[] {
  return text.toLowerCase().match(/[a-z0-9]+/g) ?? [];
}

/**
 * The singular form of an English plural, so that "pattern" matches the
 * `list_patterns` topic. The question and the text it is compared with go
 * through the same function, so a wrong singular such as "alias" to "alia"
 * changes no match.
 */
export function singular(word: string): string {
  if (word.length <= 3) return word;
  if (word.endsWith("ies")) return word.slice(0, -3) + "y";
  if (/(s|x|z|ch|sh)es$/.test(word)) return word.slice(0, -2);
  if (word.endsWith("s") && !/(ss|us|is)$/.test(word)) return word.slice(0, -1);
  return word;
}

/**
 * Words that occur in questions about any topic, so they do not help to select
 * one. "if then else expression syntax" has three content words, not five.
 */
const STOP_WORDS = new Set(
  ("a an the of on in to for with and or how do does i is it my me this that what can from by as at into " +
    "use using write syntax expression example").split(" ")
);

/** The builtin modules that a question names by an English word. "string length" means `Str`. */
const MODULE_WORDS: Record<string, string> = { string: "str", dictionary: "dict", boolean: "bool" };

/** A question as singular words, and the positions of the words that are not stop words. */
export interface Question {
  asked: string[];
  content: Set<number>;
}

export function question(text: string): Question {
  const raw = words(text);
  const asked = raw.map(singular);
  return { asked, content: new Set(raw.flatMap((w, i) => (STOP_WORDS.has(w) || STOP_WORDS.has(asked[i]) ? [] : [i]))) };
}

/** Whether content word `i` of a question is a word of a symbol's name or module path. */
function inName(q: Question, i: number, named: Set<string>): boolean {
  return named.has(q.asked[i]) || named.has(MODULE_WORDS[q.asked[i]] ?? "");
}

function nameWords(item: { name: string; modulePath: string }): Set<string> {
  return new Set([...words(item.name), ...words(item.modulePath)].map(singular));
}

/** How many content words of a question the name or the module path of a symbol contains. */
export function nameCoverage(q: Question, item: { name: string; modulePath: string }): number {
  const named = nameWords(item);
  return [...q.content].filter((i) => inName(q, i, named)).length;
}

/**
 * How well a symbol answers a question: 2 for each content word in its name or
 * its module path, and 1 for each other content word in the first paragraph of
 * its docs. 0 when no content word occurs. A name word counts more, because
 * the docs of most `Str` functions contain "string".
 */
export function symbolScore(q: Question, item: { name: string; modulePath: string; docs: string }): number {
  const named = nameWords(item);
  const documented = new Set(words(item.docs.split(/\n\s*\n/)[0] ?? "").map(singular));
  let score = 0;
  for (const i of q.content) {
    if (inName(q, i, named)) score += 2;
    else if (documented.has(q.asked[i])) score += 1;
  }
  return score;
}
