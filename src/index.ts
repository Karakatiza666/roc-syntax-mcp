import { McpServer, ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as z from "zod";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { execFile } from "child_process";
import { promisify } from "util";

const execFileAsync = promisify(execFile);

const ROOT = path.join(import.meta.dirname, "..");
const FULL_SYNTAX_FILE = path.join(ROOT, "examples", "all_roc_syntax.roc");
const TOPICS_DIR = path.join(ROOT, "examples", "topics");
const BUILTIN_FILE = path.join(ROOT, "builtin", "Builtin.roc");

// -----------------------------------------------------------------------------
// Topics
// -----------------------------------------------------------------------------

interface TopicMeta {
  file: string;
  description: string;
  keywords: string[];
}

const TOPICS: Record<string, TopicMeta> = {
  operators: {
    file: "operators.roc",
    description: "Arithmetic, comparison, and boolean operators.",
    keywords: ["operator", "+", "-", "*", "/", "==", "!=", "<", ">", "and", "or", "not", "modulo", "remainder"],
  },
  pattern_matching: {
    file: "pattern_matching.roc",
    description: "`match` expressions: branches, exhaustiveness, tuple/tag patterns.",
    keywords: ["match", "pattern", "case", "switch", "branch"],
  },
  list_patterns: {
    file: "list_patterns.roc",
    description: "List destructuring with `..`, `as` bindings, and match guards.",
    keywords: ["list", "array", "spread", "..", "as", "guard"],
  },
  tag_unions: {
    file: "tag_unions.roc",
    description: "Tag unions (sum types), Try, multi-payload tags, open tag unions.",
    keywords: ["tag", "union", "variant", "enum", "Ok", "Err", "Try", "Result", "open", "extensible"],
  },
  try_operator: {
    file: "try_operator.roc",
    description: "The `?` postfix operator for short-circuiting on `Err`, including err mapping.",
    keywords: ["?", "try", "question mark", "early return", "result", "err"],
  },
  strings: {
    file: "strings.roc",
    description: "String literals, interpolation `${...}`, multi-line `\\\\`, unicode escapes.",
    keywords: ["string", "str", "multiline", "interpolation", "unicode", "escape"],
  },
  effects: {
    file: "effects.roc",
    description: "Effectful functions (`!` suffix, `=>` arrow). `echo!` is built-in.",
    keywords: ["effect", "effectful", "!", "io", "side effect", "echo"],
  },
  loops: {
    file: "loops.roc",
    description: "For loops, while loops, `break`, and reassignable `var $name`.",
    keywords: ["for", "loop", "while", "break", "var", "$", "mutable"],
  },
  conditionals: {
    file: "conditionals.roc",
    description: "`if`/`else`/`else if` expressions; one-liner, multiline, and block forms.",
    keywords: ["if", "else", "conditional", "branch"],
  },
  tuples: {
    file: "tuples.roc",
    description: "Tuples, destructuring, `.0`/`.1` index access, pattern matching.",
    keywords: ["tuple", "pair", "triple", ".0", ".1"],
  },
  records: {
    file: "records.roc",
    description: "Record literals, field access, destructuring, and `{ ..base, ... }` update.",
    keywords: ["record", "struct", "object", "field", "update", ".."],
  },
  types: {
    file: "types.roc",
    description: "Type annotations, type variables, `where` constraints, pure (`->`) vs effectful (`=>`) arrows.",
    keywords: ["type", "annotation", "signature", "where", "constraint", "variable", "->", "=>"],
  },
  numbers: {
    file: "numbers.roc",
    description: "Numeric types and literals (`5.U64`, `0x5`, `0o5`, `0b0101`). Default is `Dec`.",
    keywords: ["number", "int", "float", "decimal", "u8", "i64", "f64", "hex", "binary", "octal", "Dec"],
  },
  opaque: {
    file: "opaque.roc",
    description: "Opaque types (`::`) — hide representation; optional methods block.",
    keywords: ["opaque", "::", "newtype", "wrapper", "alias"],
  },
  nominal: {
    file: "nominal.roc",
    description: "Nominal types (`:=`) — distinct types with optional methods (`is_eq`, etc.).",
    keywords: ["nominal", ":=", "custom", "method", "is_eq"],
  },
  functions: {
    file: "functions.roc",
    description: "Function literals `|args| body`, blocks, `return`, and `...` placeholders.",
    keywords: ["function", "lambda", "anonymous", "return", "placeholder", "..."],
  },
  static_dispatch: {
    file: "static_dispatch.roc",
    description: "`.method()` static dispatch and `->fn(arg)` arrow application (replaces `|>`).",
    keywords: ["pipe", "|>", "static dispatch", ".method", "->", "pipeline"],
  },
  imports: {
    file: "imports.roc",
    description: "Module imports, aliases (`as`), and file embedding (`import \"x\" as y : Str`).",
    keywords: ["import", "module", "as", "alias", "embed"],
  },
  testing: {
    file: "testing.roc",
    description: "Testing with `expect`, multi-line `expect { ... }` blocks, and inline assertions.",
    keywords: ["test", "expect", "assert", "roc test"],
  },
  app_header: {
    file: "app_header.roc",
    description: "Headerless apps and `app [main!] { pf: platform \"...\" }` declarations.",
    keywords: ["app", "header", "platform", "main!", "entrypoint", "headerless"],
  },
  dbg_crash: {
    file: "dbg_crash.roc",
    description: "`dbg`, `crash`, and `return` statements.",
    keywords: ["dbg", "crash", "return", "debug", "panic"],
  },
  platforms: {
    file: "platforms.roc",
    description:
      "Writing/maintaining a Roc platform: platform header, `main_for_host!`, hosted FFI (wrapper and host-direct forms), closed vs open Try at the ABI boundary, single-variant tag discriminant, record field-order ABI, nested Try, and `()` vs `{}` unit arg.",
    keywords: [
      "platform",
      "host",
      "ffi",
      "abi",
      "main_for_host",
      "host_",
      "requires",
      "provides",
      "exposes",
      "targets",
      "basic-cli",
      "libhost",
      "roc_alloc",
      "linker",
      "RocSingleTagWrapper",
      "field order",
      "segfault",
      "nested Try",
    ],
  },
  builder_pattern: {
    file: "builder_pattern.roc",
    description:
      "The fluent/builder pattern: nominal record type + setter methods that take and return Self; terminal `!` executors. Used by basic-cli's `Cmd`.",
    keywords: [
      "builder",
      "fluent",
      "chain",
      "chaining",
      "setter",
      "with_",
      "configure",
      "Cmd",
      "Request",
      "constructor",
      "new",
    ],
  },
  error_design: {
    file: "error_design.roc",
    description:
      "Designing error tag unions: structured record payloads, per-subsystem wrappers (`StdoutErr(IOErr)`), open `[..]` for composability, `?` vs `? Tag` vs `.map_err`.",
    keywords: [
      "error",
      "errors",
      "Try",
      "Err",
      "tag union",
      "wrapper",
      "subsystem",
      "open union",
      "IOErr",
      "map_err",
      "map_ok",
      "Exit",
      "EndOfFile",
    ],
  },
};

function loadFullSyntax(): string {
  try {
    return fs.readFileSync(FULL_SYNTAX_FILE, "utf-8");
  } catch (err) {
    return `Error loading syntax reference: ${err}`;
  }
}

function loadTopic(topic: string): string | null {
  const meta = TOPICS[topic];
  if (!meta) return null;
  const filePath = path.join(TOPICS_DIR, meta.file);
  try {
    return fs.readFileSync(filePath, "utf-8");
  } catch {
    return null;
  }
}

function matchTopic(query: string): string | null {
  const q = query.toLowerCase().trim();
  if (TOPICS[q]) return q;
  // exact keyword match
  for (const [name, meta] of Object.entries(TOPICS)) {
    if (meta.keywords.some((k) => k.toLowerCase() === q)) return name;
  }
  // substring match against name or keywords
  for (const [name, meta] of Object.entries(TOPICS)) {
    if (name.includes(q) || q.includes(name)) return name;
    if (meta.keywords.some((k) => k.toLowerCase().includes(q) || q.includes(k.toLowerCase()))) {
      return name;
    }
  }
  return null;
}

// -----------------------------------------------------------------------------
// Builtin.roc parser
// -----------------------------------------------------------------------------

import { type BuiltinItem, type BuiltinIndex, parseBuiltin } from "./builtin_parser.js";

let builtinIndexCache: BuiltinIndex | null = null;

function getBuiltinIndex(): BuiltinIndex {
  if (!builtinIndexCache) {
    try {
      const content = fs.readFileSync(BUILTIN_FILE, "utf-8");
      builtinIndexCache = parseBuiltin(content);
    } catch (err) {
      console.error(`Failed to load Builtin.roc: ${err}`);
      builtinIndexCache = {
        items: [],
        byFullName: new Map(),
        byName: new Map(),
        modulePaths: new Set(),
      };
    }
  }
  return builtinIndexCache;
}

function formatBuiltinItem(item: BuiltinItem): string {
  const header = `## ${item.fullName}`;
  const sigBlock = "```roc\n" + `${item.name} : ${item.signature}` + "\n```";
  const docs = item.docs ? `\n${item.docs}` : "";
  return `${header}\n${sigBlock}${docs}`;
}

import { searchBySig } from "./sig_search.js";
import { type RocFileItem, discoverRocFiles, parseRocFile } from "./roc_parser.js";

// -----------------------------------------------------------------------------
// MCP server
// -----------------------------------------------------------------------------

const server = new McpServer({
  name: "roc-syntax",
  version: "2.0.0",
});

server.registerTool(
  "get_roc_syntax",
  {
    title: "Get Roc Syntax Reference",
    description: "Full Roc syntax reference (all_syntax_test.roc) — every language construct in the new compiler.",
    inputSchema: {},
    outputSchema: { syntax: z.string() },
  },
  async () => {
    const syntax = loadFullSyntax();
    return {
      content: [{ type: "text", text: syntax }],
      structuredContent: { syntax },
    };
  }
);

server.registerTool(
  "list_roc_topics",
  {
    title: "List Roc Syntax Topics",
    description: "Lists available syntax topics for use with search_roc_syntax.",
    inputSchema: {},
    outputSchema: {
      topics: z.array(z.object({ name: z.string(), description: z.string() })),
    },
  },
  async () => {
    const topics = Object.entries(TOPICS).map(([name, meta]) => ({
      name,
      description: meta.description,
    }));
    const formatted = topics.map((t) => `- **${t.name}**: ${t.description}`).join("\n");
    return {
      content: [{ type: "text", text: `# Roc Syntax Topics\n\n${formatted}` }],
      structuredContent: { topics },
    };
  }
);

server.registerTool(
  "search_roc_syntax",
  {
    title: "Search Roc Syntax by Topic",
    description: `Roc syntax snippet for a topic or keyword. Topics: ${Object.keys(TOPICS).join(", ")}.`,
    inputSchema: {
      query: z.string().describe("Topic name (e.g. 'pattern_matching') or a keyword."),
    },
    outputSchema: {
      topic: z.string(),
      description: z.string(),
      examples: z.string(),
    },
  },
  async ({ query }) => {
    const matched = matchTopic(query);
    if (!matched) {
      const list = Object.entries(TOPICS)
        .map(([n, m]) => `- ${n}: ${m.description}`)
        .join("\n");
      return {
        content: [
          {
            type: "text",
            text: `No topic matched "${query}". Available topics:\n\n${list}`,
          },
        ],
        structuredContent: {
          topic: "help",
          description: "Available topics",
          examples: list,
        },
      };
    }

    const meta = TOPICS[matched];
    const examples = loadTopic(matched) ?? "(example file missing)";
    return {
      content: [
        {
          type: "text",
          text: `## ${matched}\n\n${meta.description}\n\n\`\`\`roc\n${examples}\n\`\`\``,
        },
      ],
      structuredContent: {
        topic: matched,
        description: meta.description,
        examples,
      },
    };
  }
);

server.registerTool(
  "lookup_builtin",
  {
    title: "Look up a Roc Builtin",
    description: "Look up a builtin by name (`concat`, `Str.concat`, `List.map`, `Num.U64.from_str`). Returns signature and docstring.",
    inputSchema: {
      name: z.string().describe("Method or fully-qualified name, e.g. 'Str.concat' or 'map'."),
    },
    outputSchema: {
      matches: z.array(
        z.object({
          fullName: z.string(),
          modulePath: z.string(),
          name: z.string(),
          signature: z.string(),
          docs: z.string(),
          line: z.number(),
        })
      ),
    },
  },
  async ({ name }) => {
    const idx = getBuiltinIndex();
    const query = name.trim();
    const matches: BuiltinItem[] = [];

    if (query.includes(".")) {
      // Try exact fully-qualified match first.
      const exact = idx.byFullName.get(query);
      if (exact) {
        matches.push(exact);
      } else {
        // Maybe the user wrote `U64.from_str` and the actual path is `Num.U64.from_str`.
        const suffix = query;
        for (const item of idx.items) {
          if (item.fullName === suffix || item.fullName.endsWith("." + suffix)) {
            matches.push(item);
          }
        }
      }
    } else {
      const bucket = idx.byName.get(query);
      if (bucket) matches.push(...bucket);
    }

    if (matches.length === 0) {
      // Fall back to substring search across names.
      const lower = query.toLowerCase();
      for (const item of idx.items) {
        if (item.name.toLowerCase().includes(lower)) {
          matches.push(item);
          if (matches.length >= 25) break;
        }
      }
    }

    if (matches.length === 0) {
      return {
        content: [
          {
            type: "text",
            text: `No builtin matched "${name}". Use \`list_roc_topics\` or call \`get_builtin_module\` with a module name like Str, List, Num, U64, I64, Dec, Bool.`,
          },
        ],
        structuredContent: { matches: [] },
      };
    }

    const text = matches.map(formatBuiltinItem).join("\n\n");
    return {
      content: [{ type: "text", text }],
      structuredContent: {
        matches: matches.map((m) => ({
          fullName: m.fullName,
          modulePath: m.modulePath,
          name: m.name,
          signature: m.signature,
          docs: m.docs,
          line: m.line,
        })),
      },
    };
  }
);

server.registerTool(
  "get_builtin_module",
  {
    title: "Get a Roc Builtin Module",
    description: "All methods in a builtin module (`Str`, `List`, `Bool`, `Num`, `Dec`, …). Bare names like `U64` resolve to `Num.U64`.",
    inputSchema: {
      module: z.string().describe("Module name, e.g. 'Str', 'List', 'U64', 'Num.Dec'."),
    },
    outputSchema: {
      module: z.string(),
      methods: z.array(
        z.object({
          name: z.string(),
          signature: z.string(),
          docs: z.string(),
          line: z.number(),
        })
      ),
    },
  },
  async ({ module: modName }) => {
    const idx = getBuiltinIndex();
    const requested = modName.trim();

    // Resolve module path.
    let resolved: string | null = null;
    if (idx.modulePaths.has(requested)) {
      resolved = requested;
    } else {
      // Look for a path that ends with `.<requested>` or equals it case-insensitively.
      for (const p of idx.modulePaths) {
        if (p === requested || p.endsWith("." + requested)) {
          resolved = p;
          break;
        }
      }
      if (!resolved) {
        const lower = requested.toLowerCase();
        for (const p of idx.modulePaths) {
          if (p.toLowerCase() === lower) {
            resolved = p;
            break;
          }
        }
      }
    }

    if (!resolved) {
      const list = [...idx.modulePaths].sort().join(", ");
      return {
        content: [
          {
            type: "text",
            text: `Unknown module "${modName}". Available modules: ${list}`,
          },
        ],
        structuredContent: { module: modName, methods: [] },
      };
    }

    const methods = idx.items.filter((it) => it.modulePath === resolved);
    const text =
      `# ${resolved}\n\n` +
      methods.map((m) => formatBuiltinItem(m)).join("\n\n");

    return {
      content: [{ type: "text", text }],
      structuredContent: {
        module: resolved,
        methods: methods.map((m) => ({
          name: m.name,
          signature: m.signature,
          docs: m.docs,
          line: m.line,
        })),
      },
    };
  }
);

server.registerTool(
  "list_builtin_modules",
  {
    title: "List Roc Builtin Modules",
    description: "Lists all builtin module paths accepted by get_builtin_module.",
    inputSchema: {},
    outputSchema: {
      modules: z.array(z.string()),
    },
  },
  async () => {
    const idx = getBuiltinIndex();
    const modules = [...idx.modulePaths].sort();
    return {
      content: [
        {
          type: "text",
          text: `# Builtin Modules\n\n${modules.map((m) => `- ${m}`).join("\n")}`,
        },
      ],
      structuredContent: { modules },
    };
  }
);

// -----------------------------------------------------------------------------
// roc check
// -----------------------------------------------------------------------------

type RocCheckResult = {
  ok: boolean;
  exit_code: number;
  stdout: string;
  stderr: string;
  checked_path: string;
  [key: string]: unknown;
};

async function runRocCheck(targetPath: string): Promise<RocCheckResult> {
  try {
    const { stdout, stderr } = await execFileAsync("roc", ["check", targetPath], {
      timeout: 30_000,
      maxBuffer: 4 * 1024 * 1024,
    });
    return { ok: true, exit_code: 0, stdout, stderr, checked_path: targetPath };
  } catch (err: any) {
    if (err?.code === "ENOENT") {
      throw new Error(
        "The `roc` binary was not found on PATH. Install a nightly build " +
          "of the new compiler from https://github.com/roc-lang/nightlies/releases " +
          "and ensure `roc version` runs in your shell."
      );
    }
    if (err?.killed) {
      throw new Error(`\`roc check\` timed out after 30s on ${targetPath}.`);
    }
    // Non-zero exit from `roc check` is the expected failure path — return it.
    return {
      ok: false,
      exit_code: typeof err?.code === "number" ? err.code : 1,
      stdout: err?.stdout ?? "",
      stderr: err?.stderr ?? String(err?.message ?? err),
      checked_path: targetPath,
    };
  }
}

server.registerTool(
  "roc_check",
  {
    title: "Type-check Roc source with `roc check`",
    description: "Type-check Roc code. Pass `code` (source string) or `path` (absolute .roc path). Returns exit code and compiler output. Requires `roc` on PATH.",
    inputSchema: {
      code: z
        .string()
        .optional()
        .describe("Roc source code to type-check. Mutually exclusive with `path`."),
      path: z
        .string()
        .optional()
        .describe("Absolute path to an existing .roc file to type-check. Mutually exclusive with `code`."),
    },
    outputSchema: {
      ok: z.boolean(),
      exit_code: z.number(),
      stdout: z.string(),
      stderr: z.string(),
      checked_path: z.string(),
    },
  },
  async ({ code, path: filePath }) => {
    if ((code === undefined || code === "") && !filePath) {
      return {
        content: [
          { type: "text", text: "Provide either `code` (Roc source) or `path` (an absolute .roc path)." },
        ],
        structuredContent: {
          ok: false,
          exit_code: -1,
          stdout: "",
          stderr: "Missing input: provide `code` or `path`.",
          checked_path: "",
        },
        isError: true,
      };
    }
    if (code !== undefined && code !== "" && filePath) {
      return {
        content: [
          { type: "text", text: "Pass `code` OR `path`, not both." },
        ],
        structuredContent: {
          ok: false,
          exit_code: -1,
          stdout: "",
          stderr: "Conflicting inputs: pass `code` or `path`, not both.",
          checked_path: "",
        },
        isError: true,
      };
    }

    let target: string;
    let cleanup: (() => void) | null = null;

    if (filePath) {
      if (!path.isAbsolute(filePath)) {
        return {
          content: [{ type: "text", text: `\`path\` must be absolute, got: ${filePath}` }],
          structuredContent: {
            ok: false,
            exit_code: -1,
            stdout: "",
            stderr: `path must be absolute, got: ${filePath}`,
            checked_path: filePath,
          },
          isError: true,
        };
      }
      target = filePath;
    } else {
      const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "roc-check-"));
      target = path.join(tmpDir, "main.roc");
      fs.writeFileSync(target, code!, "utf-8");
      cleanup = () => {
        try {
          fs.rmSync(tmpDir, { recursive: true, force: true });
        } catch {
          /* ignore */
        }
      };
    }

    try {
      const result = await runRocCheck(target);
      const summary = result.ok
        ? `\`roc check\` passed.${result.stderr ? "\n\n" + result.stderr : ""}${
            result.stdout ? "\n\n" + result.stdout : ""
          }`
        : `\`roc check\` failed (exit ${result.exit_code}).\n\n--- stderr ---\n${result.stderr}${
            result.stdout ? "\n--- stdout ---\n" + result.stdout : ""
          }`;
      return {
        content: [{ type: "text", text: summary }],
        structuredContent: result,
        isError: !result.ok,
      };
    } catch (err: any) {
      const message = err?.message ?? String(err);
      return {
        content: [{ type: "text", text: message }],
        structuredContent: {
          ok: false,
          exit_code: -1,
          stdout: "",
          stderr: message,
          checked_path: target,
        },
        isError: true,
      };
    } finally {
      cleanup?.();
    }
  }
);

// -----------------------------------------------------------------------------
// roc fmt
// -----------------------------------------------------------------------------

type RocFmtResult = {
  ok: boolean;
  exit_code: number;
  formatted: string;
  stderr: string;
  unchanged: boolean;
  [key: string]: unknown;
};

server.registerTool(
  "roc_fmt",
  {
    title: "Format Roc source with `roc fmt`",
    description: "Format Roc source code. Pass `code` (string); returns canonical text and whether it changed. Requires `roc` on PATH.",
    inputSchema: {
      code: z.string().describe("Roc source code to format."),
    },
    outputSchema: {
      ok: z.boolean(),
      exit_code: z.number(),
      formatted: z.string(),
      stderr: z.string(),
      unchanged: z.boolean(),
    },
  },
  async ({ code }) => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "roc-fmt-"));
    const target = path.join(tmpDir, "main.roc");
    fs.writeFileSync(target, code, "utf-8");

    try {
      try {
        const { stderr } = await execFileAsync("roc", ["fmt", target], {
          timeout: 30_000,
          maxBuffer: 4 * 1024 * 1024,
        });
        const formatted = fs.readFileSync(target, "utf-8");
        const result: RocFmtResult = {
          ok: true,
          exit_code: 0,
          formatted,
          stderr,
          unchanged: formatted === code,
        };
        const summary = result.unchanged
          ? "`roc fmt` made no changes — source was already canonical."
          : "`roc fmt` reformatted the source. The canonical version is in `formatted`.";
        return {
          content: [
            { type: "text", text: `${summary}\n\n\`\`\`roc\n${formatted}\n\`\`\`` },
          ],
          structuredContent: result,
        };
      } catch (err: any) {
        if (err?.code === "ENOENT") {
          const message =
            "The `roc` binary was not found on PATH. Install a nightly build " +
            "of the new compiler from https://github.com/roc-lang/nightlies/releases " +
            "and ensure `roc version` runs in your shell.";
          return {
            content: [{ type: "text", text: message }],
            structuredContent: {
              ok: false,
              exit_code: -1,
              formatted: "",
              stderr: message,
              unchanged: false,
            },
            isError: true,
          };
        }
        if (err?.killed) {
          const message = `\`roc fmt\` timed out after 30s.`;
          return {
            content: [{ type: "text", text: message }],
            structuredContent: {
              ok: false,
              exit_code: -1,
              formatted: "",
              stderr: message,
              unchanged: false,
            },
            isError: true,
          };
        }
        const stderr = err?.stderr ?? String(err?.message ?? err);
        const exit = typeof err?.code === "number" ? err.code : 1;
        return {
          content: [
            {
              type: "text",
              text: `\`roc fmt\` failed (exit ${exit}).\n\n--- stderr ---\n${stderr}`,
            },
          ],
          structuredContent: {
            ok: false,
            exit_code: exit,
            formatted: "",
            stderr,
            unchanged: false,
          },
          isError: true,
        };
      }
    } finally {
      try {
        fs.rmSync(tmpDir, { recursive: true, force: true });
      } catch {
        /* ignore */
      }
    }
  }
);

// -----------------------------------------------------------------------------
// Unified search
// -----------------------------------------------------------------------------

interface SearchHit {
  kind: "topic" | "builtin";
  id: string;            // topic name or builtin fullName
  title: string;
  snippet: string;
  score: number;
  [key: string]: unknown;
}

function scoreTopic(query: string, name: string, meta: TopicMeta): number {
  const q = query.toLowerCase();
  let s = 0;
  if (name === q) s += 100;
  else if (name.includes(q)) s += 40;
  else if (q.includes(name)) s += 25;
  for (const k of meta.keywords) {
    const kl = k.toLowerCase();
    if (kl === q) s += 30;
    else if (kl.includes(q) || q.includes(kl)) s += 8;
  }
  if (meta.description.toLowerCase().includes(q)) s += 5;
  return s;
}

function scoreBuiltin(query: string, item: BuiltinItem): number {
  const q = query.toLowerCase();
  let s = 0;
  if (item.fullName.toLowerCase() === q) s += 100;
  if (item.name.toLowerCase() === q) s += 80;
  if (item.fullName.toLowerCase().endsWith("." + q)) s += 50;
  if (item.name.toLowerCase().includes(q)) s += 20;
  if (item.modulePath.toLowerCase() === q) s += 30;
  if (item.modulePath.toLowerCase().includes(q)) s += 5;
  if (item.docs.toLowerCase().includes(q)) s += 2;
  return s;
}

server.registerTool(
  "search",
  {
    title: "Search Roc syntax topics and builtins",
    description:
      "Ranked free-text search across syntax topics and builtins. Use when unsure whether the answer is in a topic or a builtin.",
    inputSchema: {
      query: z.string().describe("Free-text query, e.g. 'parse integer', 'while loop', 'concat'."),
      limit: z.number().int().positive().optional().describe("Max number of hits (default 10)."),
    },
    outputSchema: {
      hits: z.array(
        z.object({
          kind: z.enum(["topic", "builtin"]),
          id: z.string(),
          title: z.string(),
          snippet: z.string(),
          score: z.number(),
        })
      ),
    },
  },
  async ({ query, limit }) => {
    const q = query.trim();
    const max = limit ?? 10;
    if (!q) {
      return {
        content: [{ type: "text", text: "Empty query." }],
        structuredContent: { hits: [] },
      };
    }

    const hits: SearchHit[] = [];

    for (const [name, meta] of Object.entries(TOPICS)) {
      const score = scoreTopic(q, name, meta);
      if (score > 0) {
        hits.push({
          kind: "topic",
          id: name,
          title: name,
          snippet: meta.description,
          score,
        });
      }
    }

    const idx = getBuiltinIndex();
    for (const item of idx.items) {
      const score = scoreBuiltin(q, item);
      if (score > 0) {
        const firstDocLine = item.docs.split("\n").find((l) => l.trim() !== "") ?? "";
        hits.push({
          kind: "builtin",
          id: item.fullName,
          title: item.fullName,
          snippet: `${item.name} : ${item.signature.split("\n")[0]}${firstDocLine ? " — " + firstDocLine : ""}`,
          score,
        });
      }
    }

    hits.sort((a, b) => b.score - a.score);
    const top = hits.slice(0, max);

    const text =
      top.length === 0
        ? `No hits for "${q}".`
        : top
            .map(
              (h, i) =>
                `${i + 1}. **[${h.kind}] ${h.title}** (score ${h.score})\n   ${h.snippet}`
            )
            .join("\n");

    return {
      content: [{ type: "text", text }],
      structuredContent: { hits: top },
    };
  }
);

// -----------------------------------------------------------------------------
// Signature search (Hoogle-style)
// -----------------------------------------------------------------------------

server.registerTool(
  "search_builtin_signatures",
  {
    title: "Search Roc Builtins by Type Signature",
    description:
      "Hoogle-style structural signature search. Type variables are renamed for isomorphism matching: `List x, (x -> y) -> List y` finds `List.map`. Prefix with `->` to search by return type only. Argument order matters.",
    inputSchema: {
      query: z
        .string()
        .describe(
          "Type expression, e.g. `List a, (a -> b) -> List b` or `-> Bool` or `Str, U64 -> Str`."
        ),
      limit: z.number().int().positive().optional().describe("Max results (default 10)."),
    },
    outputSchema: {
      matches: z.array(
        z.object({
          fullName: z.string(),
          signature: z.string(),
          docs: z.string(),
          score: z.number(),
          match_kind: z.string(),
        })
      ),
    },
  },
  async ({ query, limit }) => {
    const raw = query.trim();
    if (!raw) {
      return {
        content: [{ type: "text", text: "Empty query." }],
        structuredContent: { matches: [] },
      };
    }

    const top = searchBySig(getBuiltinIndex().items, raw, limit ?? 10);

    if (top.length === 0) {
      return {
        content: [
          {
            type: "text",
            text: `No builtins found matching \`${raw}\`.\n\nTip: type variable names don't matter (structural match), but argument order does.`,
          },
        ],
        structuredContent: { matches: [] },
      };
    }

    const text = top
      .map(
        ({ item, score, matchKind }) =>
          `**${item.fullName}** (${matchKind}, score ${score})\n\`\`\`roc\n${item.fullName.split(".").pop()} : ${item.signature.split("\n")[0]}\n\`\`\`${item.docs ? "\n" + item.docs.split("\n")[0] : ""}`
      )
      .join("\n\n");

    return {
      content: [{ type: "text", text }],
      structuredContent: {
        matches: top.map(({ item, score, matchKind }) => ({
          fullName: item.fullName,
          signature: item.signature,
          docs: item.docs,
          score,
          match_kind: matchKind,
        })),
      },
    };
  }
);

// -----------------------------------------------------------------------------
// Project signature search
// -----------------------------------------------------------------------------

server.registerTool(
  "search_project_signatures",
  {
    title: "Search Project Roc Files by Type Signature",
    description:
      "Structural type-signature search across all .roc files found under `root` (defaults to the server's working directory). " +
      "Uses the same matching as `search_builtin_by_signature`: type variable names are normalized so `List(x), x -> List(x)` " +
      "matches any function with that shape. Prefix query with `->` / `=>` for return-type-only search; " +
      "suffix with `->` / `=>` to match any return type. Results include file path and line number.",
    inputSchema: {
      query: z
        .string()
        .describe(
          "Type expression to search for, e.g. `List(a), U64 -> List(a)` or `-> Bool` or `Str, U64 ->`."
        ),
      root: z
        .string()
        .optional()
        .describe(
          "Absolute path to the project root to search. Defaults to the server's working directory."
        ),
      limit: z.number().int().positive().optional().describe("Max results to return (default 10)."),
    },
    outputSchema: {
      matches: z.array(
        z.object({
          fullName: z.string(),
          signature: z.string(),
          docs: z.string(),
          file: z.string(),
          line: z.number(),
          score: z.number(),
          match_kind: z.string(),
        })
      ),
      files_searched: z.number(),
      sigs_indexed: z.number(),
    },
  },
  async ({ query, root, limit }) => {
    const searchRoot = root ?? path.resolve(".");

    let files: string[];
    try {
      files = discoverRocFiles(searchRoot);
    } catch (err) {
      return {
        content: [{ type: "text", text: `Failed to discover .roc files under ${searchRoot}: ${err}` }],
        structuredContent: { matches: [], files_searched: 0, sigs_indexed: 0 },
      };
    }

    const items: RocFileItem[] = [];
    for (const file of files) {
      try {
        items.push(...parseRocFile(fs.readFileSync(file, "utf-8"), file, searchRoot));
      } catch {
        // skip unreadable files
      }
    }

    const raw = query.trim();
    if (!raw) {
      return {
        content: [
          {
            type: "text",
            text: `Empty query. Indexed ${items.length} signatures across ${files.length} .roc files under ${searchRoot}.`,
          },
        ],
        structuredContent: { matches: [], files_searched: files.length, sigs_indexed: items.length },
      };
    }

    const top = searchBySig(items, raw, limit ?? 10);

    if (top.length === 0) {
      return {
        content: [
          {
            type: "text",
            text: `No matches for \`${raw}\` across ${items.length} signatures in ${files.length} .roc files.\n\nTip: type variable names don't matter (structural match), but argument order does.`,
          },
        ],
        structuredContent: { matches: [], files_searched: files.length, sigs_indexed: items.length },
      };
    }

    const text = top
      .map(({ item, score, matchKind }) => {
        const fi = item as RocFileItem;
        return (
          `**${fi.fullName}** (${matchKind}, score ${score}) — \`${fi.file}:${fi.line}\`` +
          `\n\`\`\`roc\n${fi.fullName} : ${fi.signature.split("\n")[0]}\n\`\`\`` +
          (fi.docs ? "\n" + fi.docs.split("\n")[0] : "")
        );
      })
      .join("\n\n");

    return {
      content: [{ type: "text", text }],
      structuredContent: {
        matches: top.map(({ item, score, matchKind }) => {
          const fi = item as RocFileItem;
          return {
            fullName: fi.fullName,
            signature: fi.signature,
            docs: fi.docs,
            file: fi.file,
            line: fi.line,
            score,
            match_kind: matchKind,
          };
        }),
        files_searched: files.length,
        sigs_indexed: items.length,
      },
    };
  }
);

// -----------------------------------------------------------------------------
// MCP resources
// -----------------------------------------------------------------------------

function readUtf8(filePath: string): string {
  return fs.readFileSync(filePath, "utf-8");
}

// Full syntax reference as a single resource.
server.registerResource(
  "roc-syntax-reference",
  "roc-syntax://reference",
  {
    title: "Roc Syntax Reference",
    description:
      "Mirror of roc-lang/roc's all_syntax_test.roc — demonstrates every Roc language construct in the new compiler.",
    mimeType: "text/x-roc",
  },
  async (uri) => ({
    contents: [
      { uri: uri.href, mimeType: "text/x-roc", text: readUtf8(FULL_SYNTAX_FILE) },
    ],
  })
);

// Complete Builtin.roc as a single resource.
server.registerResource(
  "roc-builtin",
  "roc-syntax://builtin",
  {
    title: "Roc Builtin.roc",
    description:
      "The complete Builtin.roc from roc-lang/roc — every builtin type and method with signatures and docstrings.",
    mimeType: "text/x-roc",
  },
  async (uri) => ({
    contents: [
      { uri: uri.href, mimeType: "text/x-roc", text: readUtf8(BUILTIN_FILE) },
    ],
  })
);

// Per-topic example files exposed via a URI template.
server.registerResource(
  "roc-topic",
  new ResourceTemplate("roc-syntax://topic/{name}", {
    list: async () => ({
      resources: Object.entries(TOPICS).map(([name, meta]) => ({
        uri: `roc-syntax://topic/${name}`,
        name: `roc-topic-${name}`,
        title: name,
        description: meta.description,
        mimeType: "text/x-roc",
      })),
    }),
    complete: {
      name: async (value) =>
        Object.keys(TOPICS).filter((t) => t.startsWith(value.toLowerCase())),
    },
  }),
  {
    title: "Roc Syntax Topic",
    description:
      "Per-topic Roc syntax snippet. Use the URI roc-syntax://topic/<name> with one of the registered topic names.",
    mimeType: "text/x-roc",
  },
  async (uri, { name }) => {
    const topic = Array.isArray(name) ? name[0] : name;
    const text = loadTopic(topic);
    if (text === null) {
      throw new Error(`Unknown topic: ${topic}. Use list_roc_topics to see available topics.`);
    }
    return {
      contents: [{ uri: uri.href, mimeType: "text/x-roc", text }],
    };
  }
);

// -----------------------------------------------------------------------------
// Start
// -----------------------------------------------------------------------------

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Roc Syntax MCP Server running on stdio");
}

main().catch(console.error);
