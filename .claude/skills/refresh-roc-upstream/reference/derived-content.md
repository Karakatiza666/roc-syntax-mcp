# Reconciling the derived content

All content outside the three copied trees is ours, written for a version of Roc
that the refresh has just changed. None of it shows a clear failure by itself.

## 1. Find the reversed claims

The most costly failure is a topic file that teaches the opposite of the truth.
An agent that reads it writes code that does not compile, with confidence, and
trusts the bundled reference over the compiler error.

Read the report of `scripts/langref-diff.roc` first. Upstream's own prose names
what changed, and the report names the topics that carry each changed section.

Then search for the patterns that go out of date:

| Pattern | Why it goes out of date |
|---|---|
| "no longer", "was removed", "replaces", "instead of" | States a change relative to a version that has changed again |
| Operator spellings | Upstream removed `\|>`, then restored it. `->`, `??`, `?`, `..<`, `..=` have all changed |
| "must", "always", "every ... needs" | `if` needed an `else`, and then it did not |
| "not implemented yet" | Describes the compiler at one date, not the language |
| Any builtin name | Resolve it against the new index. See section 2 |

```bash
grep -rniE 'no longer|removed|replaces|deprecated|not implemented' corpus/language/topics/ corpus/language/overview/
```

## 2. Resolve every builtin that a topic names

Upstream deletes and renames builtins freely. The 2026-08 refresh removed 34
builtins, including `List.join_with`, `List.encode`, and the full
`shift_left_by` / `shift_right_by` / `shift_right_zf_by` family on every integer
type. A topic file that names a deleted builtin will cause a compile error.
`check-roc.sh` finds the name only where it is in code that the script checks,
not in a comment.

```bash
node --import tsx/esm -e '
import * as fs from "node:fs";
import { parseBuiltin } from "./src/builtin_parser.ts";
const i = parseBuiltin(fs.readFileSync("corpus/language/Builtin.roc", "utf-8"));
const text = fs.readFileSync("/dev/stdin", "utf-8");
const named = new Set(text.match(/\b[A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)*\.[a-z_][A-Za-z0-9_]*!?/g) ?? []);
// Accept a partially qualified name: `I64.from_str` is `Num.I64.from_str`.
const resolves = (n) => i.byFullName.has(n) ||
  (i.byName.get(n.split(".").pop()) ?? []).some((it) => it.fullName.endsWith("." + n));
for (const n of [...named].sort()) if (!resolves(n)) console.log("missing", n);
' < <(cat corpus/language/topics/*.roc corpus/language/overview/language.md corpus/language/overview/builtins.md)
```

Give the script the two language pages by name, not
`corpus/language/overview/*.md`. The platform overview pages are in that
directory too. They correctly name platform modules that the builtin index does
not have, and those names hide the real results. The glob reports 118 names,
and the form with the two pages reports 34.

At commit `2d69988`, all 34 are false positives, in four shapes:

1. Platform modules that the bundled content mentions but does not index
   (`Stdout.line!`, `File.read_utf8!`, `Utc.now!`).
2. Types defined inside the examples (`Celsius.from_numeral`, `Counter.new`,
   `Secret.new`).
3. File names and tarball names that look like qualified names (`Builtin.roc`,
   `README.md`).
4. Dispatch through a local module alias. `Encoding : encoding` binds a type
   parameter, and `Encoding.parse_str` resolves through it and does not name a
   builtin (`corpus/language/topics/json.roc:104`).

A name outside these four shapes is a real dangling reference.

## 3. Add topics only for areas that an agent would get wrong

A new builtin module does not automatically need a topic file. The standard is
this: an agent with the builtin index would still write the code wrong. On this
basis, the 2026-08 refresh added six topics (`iterators`, `ranges`,
`record_fields`, `derived_methods`, `json`, `hashing`). It skipped the SIMD
types, because their index entries are clear without a topic.

A new topic needs four edits. If you forget one, callers cannot reach or find
the topic:

1. `corpus/language/topics/<name>.roc`
2. A `BUILTIN_TOPICS` entry in `src/topics.ts` with a description and keyword list
3. A row in the README topic table
4. A run of `check:roc`, since the file is new and unverified

## 4. Upstream's own examples do not always compile

`corpus/language/langref/` is prose, not a test suite. At commit `a3dc89b`,
these three examples were wrong. Our topic files differ from them on purpose,
and each difference has a comment in the topic file that says why. Check them
again on a refresh. Do not copy upstream over them without a check.

| Upstream | Problem | Ours |
|---|---|---|
| `modules.md:596` | `main! = \|_args\| echo!("Hello, World!")` returns `{}`, but Echo's `main!` must return `Try(_, [Exit(I8), ..])` | `app_header.roc` appends `Ok({})` |
| `static-dispatch.md:277` | `Ok({ degrees })` builds a plain record where the nominal `Celsius` is required | `numbers.roc` uses `Celsius.{ degrees }` |
| `tag-unions.md:49` | Open-union example that the compiler cannot handle | `tag_unions.roc` teaches the same idea without it |

Keep the copied `corpus/language/langref/` byte-for-byte identical to upstream
anyway. A fix there would break the diff against the next refresh, and that diff
is the main value of the pin. The server does not serve it, so a wrong upstream
example reaches no agent.

## 5. What each test suite asserts

Read a failure as a statement about the content, not about the test.

| Suite | Asserts |
|---|---|
| `builtin_parser.test.ts` | No empty module paths, no duplicate names, wrapped signatures intact, deleted builtins gone, current ones present |
| `builtin_hints.test.ts` | Every hint key names a real builtin. Hints stay one line and a small fraction of the signature list. The hinted set matches what the three layers declare |
| `langref.test.ts` | Every bundled page parses, and slugs are unique per page. `langref-map.txt` has one line for each section, and each line names language topics or a reason to skip |
| `overview.test.ts` | Token budgets. Every builtin and module named exists. The builtins page quotes no counts. Every tool named is real. No placeholder text |
| `resources.test.ts` | Runs a real JSON-RPC session. Resource sizes, `readOnlyHint` on every tool, the packaged version, the protocol revision, input schemas that survive the wire |
| `sig_search.test.ts` | The score ladder of signature search, and its tie-breaks |

The three suites that fail most often on a refresh are `builtin_hints` on a
rename, `overview` on a method count, and `builtin_parser` on a new file shape.

## 6. Token budgets

The server is worth keeping loaded only if it uses few tokens. Tests assert two
budgets, and you measure one by hand:

- Overview pages: `language` under 1,800 tokens, `builtins` under 1,600, and
  both together under 3,400, at 3.5 characters per token. `overview.test.ts`
  asserts these budgets.
- Static resources stay small enough to read. `roc-syntax://builtin` serves an
  index, not the 800 KB file. `resources.test.ts` asserts this.
- Tool-list cost, measured by `scripts/tool-cost.mjs` in this skill. `resources.test.ts`
  asserts the 2800-token ceiling. Compare against the number in `SKILL.md`, and
  justify any growth.

When a description must grow, remove the same length from another place.
Argument semantics belong in parameter descriptions, which cost nothing until a
client calls the tool. Tool descriptions cost tokens on every `tools/list`. The
merge of the three `list_*` tools into `list_roc_index` made the same trade at
the tool level.
