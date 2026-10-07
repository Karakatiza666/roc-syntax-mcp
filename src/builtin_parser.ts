// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

export interface BuiltinItem {
  /** `"value"` for a method or constant, `"type"` for a type declaration. */
  kind: "value" | "type";
  /**
   * `"public"` is reachable from an application. `"host"` is the ABI boundary
   * that a platform author works on and an app author must never call. The
   * parser sets `"host"` from the name. `"private"` is a declaration that an app
   * cannot name. The corpus loader, which knows the module layout, also assigns
   * `"host"` and `"private"`.
   */
  tier: "public" | "host" | "private";
  name: string;        // e.g. "concat", or "Method"
  modulePath: string;  // e.g. "Str" or "Num.U64", or empty for a top-level type
  fullName: string;    // e.g. "Str.concat", or "Method"
  /** For a value, its type. For a type, its declaration body. */
  signature: string;
  docs: string;        // accumulated `## ...` doc lines
  line: number;        // 1-based line in the source file
  /** Types only: the declaration operator, one of `::`, `:=`, `:`. */
  decl?: "::" | ":=" | ":";
  /** Types only: the left-hand side as written, e.g. `Iter(item)`. */
  head?: string;
  /**
   * Set on a value the source never annotated. Its `signature` is the lambda
   * head the definition opens with, not a type, so it must be rendered as a
   * definition and kept out of signature search.
   */
  unannotated?: true;
}

export interface BuiltinIndex {
  items: BuiltinItem[];
  byFullName: Map<string, BuiltinItem>;
  byName: Map<string, BuiltinItem[]>;
  modulePaths: Set<string>;
}

function countLeadingTabs(line: string): number {
  let n = 0;
  while (n < line.length && line[n] === "\t") n++;
  return n;
}

/**
 * Spaces per indentation level, for a file that uses no tabs at all.
 *
 * Upstream uses tab indentation, with one exception: basic-cli's
 * `InternalSqlite.roc` uses four spaces. A parser that counts only tabs reads
 * every line of that file as top-level and indexes nothing. Returns 0 for a file
 * with any tab indentation. The parser then counts only tabs in that file and
 * makes no guess about mixed indentation.
 */
function spaceUnit(lines: string[]): number {
  let unit = 0;
  for (const line of lines) {
    if (line.startsWith("\t")) return 0;
    const m = line.match(/^( +)\S/);
    if (m && (unit === 0 || m[1].length < unit)) unit = m[1].length;
  }
  return unit;
}

/** True if a type line ends mid-expression, so the next line continues it. */
function wantsMore(text: string): boolean {
  return /(,|->|=>|\||where)$/.test(text.replace(/#.*$/, "").trim());
}

/**
 * Whether `name` is a glue method that converts between Roc types and the flat
 * shapes a host writes.
 *
 * The regexes are anchored on purpose. A bare `_host` substring also matches
 * `Server.Target.authority_host`, `Header.raw_host`, and
 * `Server.Authority.validate_host`. These are about the HTTP Host header, and an
 * app author needs them.
 */
function isHostBoundary(name: string): boolean {
  return /^(to|from)_host(_|$)/.test(name) || /_(to|from)_host$/.test(name) || /_for_host!?$/.test(name);
}

/** Net bracket depth of a line, ignoring any trailing `#` comment. */
function bracketDelta(trimmed: string): number {
  const code = trimmed.replace(/#.*$/, "");
  let depth = 0;
  for (const ch of code) {
    if (ch === "{" || ch === "[" || ch === "(") depth++;
    else if (ch === "}" || ch === "]" || ch === ")") depth--;
  }
  return depth;
}

/** An open type declaration, whether single-line or spanning a bracketed body. */
interface PendingDecl {
  name: string;
  head: string;
  decl: "::" | ":=" | ":";
  indent: number;
  line: number;
  docs: string[];
  /** False for a declaration too deep to be a real type. See `atModuleTop`. */
  emit: boolean;
  body: string;
}

export function parseBuiltin(
  content: string,
  /**
   * Also index declarations at column 0. `Builtin.roc` and platform modules
   * wrap everything in one block, but an app or a headerless file declares its
   * functions at the top.
   */
  opts: { topLevel?: boolean } = {}
): BuiltinIndex {
  const lines = content.split("\n");
  const unit = spaceUnit(lines);
  const indentOf = (line: string) =>
    unit === 0 ? countLeadingTabs(line) : Math.floor(line.match(/^ */)![0].length / unit);
  const items: BuiltinItem[] = [];
  const stack: { name: string; indent: number }[] = [];
  // Set while a multi-line type header (`Iter(item) :: {` ... `}.{`) is open. Its
  // record or tag-union body is type structure, not methods, so the parser
  // captures no members until the header closes.
  let header: PendingDecl | null = null;
  let pendingDocs: string[] = [];

  // The indent a member declaration sits at, or -1 where none can.
  const memberIndent = () =>
    stack.length > 0 ? stack[stack.length - 1].indent + 1 : opts.topLevel ? 0 : -1;

  const modulePathAt = () => stack.map((s) => s.name).filter((n) => n !== "Builtin").join(".");

  const emitType = (d: PendingDecl, rawBody: string) => {
    // A trailing `.{}` is an empty method block, not part of the type.
    const body = rawBody.replace(/\.\{\s*\}$/, "").trim();
    // `[]`, `{}`, and `[ProvidedByCompiler]` declare a namespace or a compiler
    // primitive. If indexed, `Str :: [ProvidedByCompiler]` comes before the `Str`
    // module on an exact-name lookup.
    if (!d.emit || /^(\[\s*\]|\{\s*\}|\[\s*ProvidedByCompiler\s*\])$/.test(body)) return;
    const modulePath = modulePathAt();
    items.push({
      kind: "type",
      tier: "public",
      name: d.name,
      modulePath,
      fullName: modulePath ? `${modulePath}.${d.name}` : d.name,
      signature: body,
      docs: d.docs.join("\n").trim(),
      line: d.line,
      decl: d.decl,
      head: d.head,
    });
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();
    const indent = indentOf(line);

    if (trimmed === "") continue;

    if (header) {
      if (indent <= header.indent && /^[}\])]/.test(trimmed)) {
        header.body += "\n" + line;
        // `}.{` opens a method block, so the type becomes a module. A bare `}` or
        // `].{}` means the declaration was a plain type with no methods.
        const opensMethods = /\.\{\s*$/.test(trimmed);
        emitType(header, header.body.replace(/\.\{\s*$/, "").trim());
        if (opensMethods) stack.push({ name: header.name, indent: header.indent });
        header = null;
        pendingDocs = [];
        continue;
      }
      if (indent > header.indent) {
        header.body += "\n" + line; // still inside the header body
        continue;
      }
      header = null; // Unterminated header. Process this line again as a normal line.
    }

    if (trimmed.startsWith("##")) {
      const text = trimmed === "##" ? "" : trimmed.replace(/^##\s?/, "");
      pendingDocs.push(text);
      continue;
    }

    if (trimmed === "}" && stack.length > 0 && indent === stack[stack.length - 1].indent) {
      stack.pop();
      pendingDocs = [];
      continue;
    }

    // `::` and `:=` declare nominal and opaque types. A lone `:` declares an
    // uppercase type alias, and the parser skips its body the same way.
    const declMatch = trimmed.match(/^([A-Z]\w*)((?:\([^)]*\))?)\s+(::|:=|:)(?=\s|$)/);
    if (declMatch) {
      // A declaration exactly one level inside its enclosing module is a real
      // type. Anything deeper is a local annotation in a function body. For
      // example, `Shape : a` appears five times inside `expect` blocks in
      // Builtin.roc, and indexing those adds 20 items with duplicate full names.
      const parentIndent = stack.length > 0 ? stack[stack.length - 1].indent : -1;
      const rhs = trimmed.slice(declMatch[0].length).trim();
      const pending: PendingDecl = {
        name: declMatch[1],
        head: declMatch[1] + declMatch[2],
        decl: declMatch[3] as "::" | ":=" | ":",
        indent,
        line: i + 1,
        docs: pendingDocs,
        emit: indent === parentIndent + 1,
        body: rhs,
      };

      // Check `.{` before bracket depth, because `Method := [A, B].{` leaves a
      // brace open and looks like a multi-line header.
      if (/\.\{\s*$/.test(trimmed)) {
        emitType(pending, rhs.replace(/\.\{\s*$/, "").trim());
        stack.push({ name: pending.name, indent });
      } else if (bracketDelta(trimmed) > 0) {
        header = pending;
      } else {
        emitType(pending, rhs);
      }
      pendingDocs = [];
      continue;
    }

    // Only a signature exactly one level inside its module is a member. For
    // example, `expect { snapshot : Snapshot ... }` in roc-ray's Gamepad is a
    // local annotation. If indexed, it adds a member name that the module does
    // not have, and two of them in one module make `validate` report a duplicate.
    const sigMatch = trimmed.match(/^([a-z_]\w*!?)\s+:\s+(.+)$/);
    if (sigMatch && indent === memberIndent()) {
      let sig = sigMatch[2];
      let depth = bracketDelta(sig);
      let wants = wantsMore(sig);
      let j = i + 1;
      while (j < lines.length) {
        const next = lines[j];
        const nextTrim = next.trim();
        if (nextTrim === "") break;
        if (nextTrim.startsWith("##")) break;
        // A signature continues while it sits inside unclosed brackets, while the
        // previous line ended mid-type, or onto lines indented past the declaration.
        if (depth <= 0 && !wants && indentOf(next) <= indent) break;
        sig += "\n" + next;
        depth += bracketDelta(nextTrim);
        wants = wantsMore(nextTrim);
        j++;
      }
      const modulePath = modulePathAt();
      const fullName = modulePath ? `${modulePath}.${sigMatch[1]}` : sigMatch[1];
      items.push({
        kind: "value",
        tier: isHostBoundary(sigMatch[1]) ? "host" : "public",
        name: sigMatch[1],
        modulePath,
        fullName,
        signature: sig,
        docs: pendingDocs.join("\n").trim(),
        line: i + 1,
      });
      pendingDocs = [];
      i = j - 1; // Consumed continuation lines must not be re-read as declarations.
      continue;
    }

    // A definition the source never annotated. `Sqlite.query_many!`,
    // `Tcp.connect!`, `File.open_reader!` and every `Html` element helper are
    // declared this way, so skipping them drops the primary API of four
    // modules. Only a definition exactly one level inside its module block
    // qualifies. A binding in a function body or an `expect` block is deeper.
    const defMatch = trimmed.match(/^([a-z_]\w*!?)\s*=(?!=)\s*(.*)$/);
    if (defMatch && indent === memberIndent()) {
      const modulePath = modulePathAt();
      const fullName = modulePath ? `${modulePath}.${defMatch[1]}` : defMatch[1];
      // The annotated form, which the branch above emits, wins. The annotation
      // is the better answer, and the `name = ...` line below it is the same
      // declaration.
      if (!items.some((it) => it.fullName === fullName && it.kind === "value")) {
        items.push({
          kind: "value",
          tier: isHostBoundary(defMatch[1]) ? "host" : "public",
          name: defMatch[1],
          modulePath,
          fullName,
          // The lambda head is the only shape information in the source. A
          // constant has none. No bundled corpus has an unannotated constant,
          // and the fallback text invents no shape.
          signature: /^\|/.test(defMatch[2])
            ? defMatch[2].match(/^\|[^|]*\|/)?.[0] ?? defMatch[2]
            : "(no type annotation upstream)",
          docs: pendingDocs.join("\n").trim(),
          line: i + 1,
          unannotated: true,
        });
      }
      pendingDocs = [];
      continue;
    }

    pendingDocs = [];
  }

  const byFullName = new Map<string, BuiltinItem>();
  const byName = new Map<string, BuiltinItem[]>();
  const modulePaths = new Set<string>();
  for (const item of items) {
    byFullName.set(item.fullName, item);
    const bucket = byName.get(item.name);
    if (bucket) bucket.push(item);
    else byName.set(item.name, [item]);
    // Only a type with methods is a module. A bare nominal type is not.
    if (item.kind === "value" && item.modulePath) modulePaths.add(item.modulePath);
  }

  return { items, byFullName, byName, modulePaths };
}
