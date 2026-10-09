// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import * as fs from "fs";
import * as path from "path";

import { type Catalog, ROOT, type ScopeName, type ScopeTopic } from "./scopes.ts";
import { question, type Question, singular, words } from "./words.ts";

const TOPICS_DIR = path.join(ROOT, "corpus", "language", "topics");

// -----------------------------------------------------------------------------
// Topics
// -----------------------------------------------------------------------------

export interface TopicMeta {
  file: string;
  description: string;
  keywords: string[];
  /** Which corpus the topic teaches. Omitted means `language`. */
  scope?: ScopeName;
  /**
   * The plugin name of the documented package that the topic teaches. Such a
   * topic is filed under `language` because a package works on any platform.
   * The topic lets a caller find the package before any app pins it.
   */
  package?: string;
  /**
   * Directory holding `file`, relative to the repo root. Omitted means
   * `corpus/language/topics`. A platform topic lives beside its platform so the same
   * check script that verifies the examples verifies it too.
   */
  dir?: string;
}

const BUILTIN_TOPICS: Record<string, TopicMeta> = {
  idioms: {
    file: "idioms.roc",
    description: "Which construct to use when several would work: anonymous tag unions for errors, structural before nominal, derive before hand-write, chains before pipes.",
    keywords: ["idiom", "idioms", "best practice", "convention", "style", "anonymous",
      "structural", "algebraic", "error handling", "prefer", "when to use", "guideline"],
  },
  iterators: {
    file: "iterators.roc",
    description: "`Iter` (pure) and `Stream` (effectful) iterators, the `iter`/`next` methods behind `for ... in`, `for!` over a `Stream`, and the adapters.",
    keywords: ["iterator", "iter", "Iter", "Stream", "next", "for", "for!", "map", "keep_if", "fold",
      "collect", "iter_rev", "size_hint", "custom", "unfold", "lazy"],
  },
  ranges: {
    file: "ranges.roc",
    description: "Range operators `..<` and `..=`, the `Range(num)` value, `step_by`, `iter_rev`, and custom numeric ranges.",
    keywords: ["range", "..<", "..=", "Range", "step_by", "iter_rev", "size_hint",
      "exclusive", "inclusive", "range_exclusive_to", "range_inclusive_to"],
  },
  record_fields: {
    file: "record_fields.roc",
    description: "Defaulted (`field : Type ?? default`) and optional (`field ?: Type`) record fields, `.?field` reads, and the `..rest` pattern.",
    keywords: ["record", "field", "default", "defaulted", "optional", "??", "?:", ".?",
      "MissingField", "rest", "..rest", "update"],
  },
  derived_methods: {
    file: "derived_methods.roc",
    description: "The `method : _` compiler-derived opt-in, the full well-known-method table, and the literal-conversion hooks.",
    keywords: ["derive", "derived", "_", "is_eq", "to_hash", "parser_for", "encoder_for",
      "map", "map!", "to_inspect", "from_numeral", "from_quote", "from_interpolation",
      "well-known", "method"],
  },
  json: {
    file: "json.roc",
    description: "`Json` (`Encoding.Json`) parse/encode, the `parser_for`/`encoder_for` codec protocol, its `Encodable`/`Parseable` where aliases, the `Default`/`CamelCase`/`TrailingCommas` dialects, and missing fields.",
    keywords: ["json", "Json", "encoding", "Encoding", "parse", "to_str", "parser_for",
      "encoder_for", "Encodable", "Parseable", "codec", "serialize", "deserialize",
      "camelCase", "trailing comma"],
  },
  hashing: {
    file: "hashing.roc",
    description: "`to_hash` and the `Hasher.write_*` methods, plus `Crypto.SHA256`/`Crypto.BLAKE3` digests.",
    keywords: ["hash", "to_hash", "Hasher", "write_str", "write_u64", "Crypto", "SHA256",
      "BLAKE3", "digest", "Digest", "to_hex", "from_hex", "dict key", "set key"],
  },
  operators: {
    file: "operators.roc",
    description: "Arithmetic, comparison, boolean, range (`..<`/`..=`), and `??` operators, with their method desugaring.",
    keywords: ["operator", "+", "-", "*", "/", "//", "%", "==", "!=", "<", ">", "and", "or", "not",
      "modulo", "remainder", "range", "..<", "..=", "??", "default", "desugar", "subscript"],
  },
  pattern_matching: {
    file: "pattern_matching.roc",
    description: "`match` expressions: alternatives, guards, literal and code-point patterns, `as`, exhaustiveness and redundancy, destructuring, string captures.",
    keywords: ["match", "pattern", "case", "switch", "branch", "capture", "route"],
  },
  list_patterns: {
    file: "list_patterns.roc",
    description: "List destructuring with `..`, `as` bindings, and match guards.",
    keywords: ["list", "array", "spread", "..", "as", "guard"],
  },
  tag_unions: {
    file: "tag_unions.roc",
    description: "Tag unions, nominal `Try`, multi-payload tags, open unions and `..others` pass-through, qualified tags, nominal vs structural tags, and the empty union `[]`.",
    keywords: ["tag", "union", "variant", "enum", "Ok", "Err", "Try", "Result", "open", "extensible"],
  },
  try_operator: {
    file: "try_operator.roc",
    description: "The `?` postfix operator for short-circuiting on `Err`, including err mapping.",
    keywords: ["?", "try", "question mark", "early return", "result", "err"],
  },
  strings: {
    file: "strings.roc",
    description: "String literals, interpolation `${...}`, multi-line `\\\\`, unicode escapes, UTF-8 conversion, `Str.len`, single-quote code points, equality without normalization, and bidi controls.",
    keywords: ["string", "str", "multiline", "interpolation", "unicode", "escape"],
  },
  effects: {
    file: "effects.roc",
    description: "Effectful functions (`!` suffix, `=>` arrow), purity inference, the errors and the warning for wrong purity, and the `!` twins of higher-order builtins. `echo!` is built-in and appends no newline.",
    keywords: ["effect", "effectful", "!", "io", "side effect", "echo", "newline", "stdout"],
  },
  loops: {
    file: "loops.roc",
    description: "For loops, while loops, `break`, and reassignable `var $name`.",
    keywords: ["for", "loop", "while", "break", "var", "$", "mutable"],
  },
  conditionals: {
    file: "conditionals.roc",
    description: "`if`/`else`/`else if` expressions. `else` is optional when the body is `{}`. Short-circuiting `and`/`or`.",
    keywords: ["if", "else", "else if", "conditional", "branch", "and", "or", "short-circuit"],
  },
  tuples: {
    file: "tuples.roc",
    description: "Tuples, destructuring, `.0`/`.1` index access, pattern matching.",
    keywords: ["tuple", "pair", "triple", ".0", ".1"],
  },
  records: {
    file: "records.roc",
    description: "Record literals, puns, field access, record patterns, `{ ..base, ... }` update and its limits, and open records.",
    keywords: ["record", "struct", "object", "field", "update", ".."],
  },
  types: {
    file: "types.roc",
    description: "Type annotations, type variables (`_`, `_elem`), generalization, `where` clauses and `where` aliases, `Thing : thing`, rank-1 and no-HKT limits, aliases, and recursive types.",
    keywords: ["type", "annotation", "signature", "where", "where alias", "constraint",
      "variable", "->", "=>"],
  },
  compile_time: {
    file: "compile_time.roc",
    description: "Compile-time evaluation of top-level constants and pure calls, compile-time crashes as compile errors, no effects at build time, empty collections, binary size, and code with errors.",
    keywords: ["compile time", "comptime", "constant", "top-level", "build time", "lookup table",
      "with_capacity", "binary size"],
  },
  dict_set: {
    file: "dict_set.roc",
    description: "`Dict` and `Set`: building them with `empty`/`single`/`from_list`, `get` with `??`, `insert`/`remove`/`update`, insertion-order iteration and how `remove` changes it, set operations, and what a key type needs.",
    keywords: ["dict", "set", "hashmap", "dictionary", "from_list", "iteration order", "KeyNotFound",
      "intersection", "difference"],
  },
  memory: {
    file: "memory.roc",
    description: "Immutable values, reference counting, opportunistic in-place updates (`List.set`), no pointers or value identity, no reference cycles.",
    keywords: ["memory", "reference counting", "refcount", "heap", "allocation", "mutation", "in place",
      "copy", "clone", "pointer", "identity", "cycle", "garbage collection"],
  },
  naming: {
    file: "naming.roc",
    description: "Naming rules for values, types and `var`s, definition order, unused-name warnings, shadowing and duplicate definitions, and the rules for capturing a `var`.",
    keywords: ["name", "naming", "identifier", "shadow", "shadowing", "duplicate definition", "redefine",
      "unused", "_name", "underscore", "capture", "closure", "before definition"],
  },
  numbers: {
    file: "numbers.roc",
    description: "Numeric types and literals (`5.U64`, `0x5`, `1.5e-2`, underscores), `Dec` versus floats, literal defaulting, and custom number types through `from_numeral` and `Numeral`.",
    keywords: ["number", "numeric", "literal", "suffix", "integer", "int", "float", "decimal", "u8", "i64",
      "f32", "f64", "hex", "binary", "octal", "Dec"],
  },
  opaque: {
    file: "opaque.roc",
    description: "Opaque types (`::`) hide the representation. Methods are optional.",
    keywords: ["opaque", "::", "newtype", "wrapper", "alias"],
  },
  nominal: {
    file: "nominal.roc",
    description: "Distinct nominal types (`:=`), explicit construction and destructuring (`T.(v)`, `T.{...}`), when literals lift, and associated constants.",
    keywords: ["nominal", ":=", "custom", "method", "is_eq"],
  },
  functions: {
    file: "functions.roc",
    description: "Function literals `|args| body`, blocks, `return`, `...`, recursion, top-level cycles, and tail calls (accumulators, modulo cons).",
    keywords: ["function", "lambda", "anonymous", "return", "placeholder", "...", "recursion", "recursive",
      "tail call", "stack overflow", "accumulator"],
  },
  static_dispatch: {
    file: "static_dispatch.roc",
    description: "`.method()` static dispatch, the `|>` pipe operator, and well-known methods.",
    keywords: ["pipe", "|>", "pizza", "static dispatch", ".method", "pipeline", "where", "well-known method"],
  },
  imports: {
    file: "imports.roc",
    description: "Module imports, aliases (`as`), file embedding (`import \"x\" as y : Str` or `List(U8)`), and mutually recursive types in a void module.",
    keywords: ["import", "as", "alias", "embed"],
  },
  modules: {
    file: "modules.roc",
    description: "Type modules (one nominal type per file, named like the file), what a module hides, nested types (`Url.ParseErr`), void modules (`Util :: [].{ ... }`), no import cycles, and the four module kinds and their headers.",
    keywords: ["module", "type module", "void module", "namespace", "nested type", "private", "hide", "pub",
      "import cycle", "Util"],
  },
  packages: {
    file: "packages.roc",
    description: "Package headers and dependencies: `package [...] { ... }`, URL (`.tar.zst`, hash) and path packages, version resolution, shorthands, platform-specific packages, and nominal type identity across packages.",
    keywords: ["package", "dependency", "dependencies", "version", "semver", "shorthand", "tar.zst"],
  },
  comments: {
    file: "comments.roc",
    description: "Comments: `#`, `##` doc comments in Markdown, code blocks and `[Name]` autolinks in docs, `roc docs`, shebang lines, and the ban on bidirectional controls.",
    keywords: ["comment", "doc comment", "##", "docs", "roc docs", "autolink", "shebang", "bidi", "documentation"],
  },
  testing: {
    file: "testing.roc",
    description: "Testing with `expect`, multi-line `expect { ... }` blocks, inline assertions, `?` inside `expect`, and the control flow rules inside `expect`.",
    keywords: ["test", "expect", "assert", "roc test"],
  },
  compiler: {
    file: "compiler.roc",
    description: "The `roc` command line: check, test, run and build, exit codes, `--opt` levels and their per-command defaults, `--target`, `fmt`, `deps` with `--replace-dep`, `docs`, `bundle`, `bump`, and `roc glue`.",
    keywords: ["compiler", "toolchain", "roc command", "roc check", "roc build", "roc run", "roc fmt", "roc glue",
      "glue", "build", "run", "compile", "optimize", "optimized", "optimized binary", "executable",
      "optimization", "--opt", "speed", "size",
      "release", "target", "--target", "cross compile", "musl", "exit code", "format", "deps",
      "--replace-dep", "bundle", "publish", "bump", "semver", "docs", "install", "repl", "watch"],
  },
  app_header: {
    file: "app_header.roc",
    description: "Headerless apps and `app [main!] { pf: platform \"...\" }` declarations.",
    keywords: ["app", "header", "platform", "main!", "entrypoint", "headerless"],
  },
  dbg_crash: {
    file: "dbg_crash.roc",
    description: "`dbg` output (stderr, `to_inspect`, compile time), `crash`, and the planned `continue`.",
    keywords: ["dbg", "crash", "debug", "panic", "continue"],
  },
  platforms: {
    file: "platforms.roc",
    description:
      "Writing/maintaining a Roc platform: platform header, `requires` forms, reserved `roc__` symbols, `main_for_host!`, hosted FFI (wrapper and host-direct forms) and its rules, and the host side. The ABI edge cases are in `platform_abi`.",
    keywords: [
      "platform",
      "host",
      "ffi",
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
    ],
  },
  platform_abi: {
    file: "platform_abi.roc",
    description:
      "The host ABI of a platform: closed hosted results, the single-tag discriminant byte, record field order and `_ : {}`, three-state returns, `()` vs `{}` for the unit argument, the representations of `Path`, and a shared `IOErr`.",
    keywords: ["abi", "RocSingleTagWrapper", "field order", "layout", "padding", "segfault", "nested Try",
      "unit argument", "glue"],
  },
  builder_pattern: {
    file: "builder_pattern.roc",
    description:
      "The fluent/builder pattern: nominal record type + setter methods that take and return Self. Terminal `!` executors. Used by basic-cli's `Cmd`. Also record builders, `{ ... }.Type` over `map2`.",
    keywords: [
      "builder",
      "record builder",
      "map2",
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
  scripting: {
    file: "scripting.roc",
    dir: "corpus/platforms/basic-cli/topics",
    description:
      "Writing and running a standalone .roc utility script: how `roc run`/`test`/`build`/`bundle` and a `#!` line reach it, argument dispatch to exit code, CSV and YAML into records and ad-hoc parsing with `lukewilliamboswell/roc-parser`, stdin pipelines, and the one place errors become messages. Assumes basic-cli.",
    keywords: [
      "script",
      "scripts",
      "scripting",
      "standalone",
      "utility",
      "shebang",
      "roc run",
      "roc build",
      "roc bundle",
      "roc install",
      "roc test",
      "roc fmt",
      "executable",
      "shell",
      "pipeline",
      "stdin",
      "automation",
      "one file",
      "single file",
      "shell script",
      "roc script",
      "utility script",
      "run",
      "execute",
      "roc file",
    ],
  },
  error_design: {
    file: "error_design.roc",
    description:
      "Designing error tag unions: anonymous over declared, structured record payloads, per-subsystem wrappers (`StdoutErr(IOErr)`), open `[..]` for composability, `?` vs `? Tag` vs `.map_err`.",
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
  webserver_handler: {
    file: "webserver_handler.roc",
    scope: "basic-webserver",
    dir: "corpus/platforms/basic-webserver/topics",
    description: "The basic-webserver request handler: `init!`/`respond!`/`shutdown!`, routing on method and target, reading the streaming body, and the four `Server.Outcome` constructors.",
    keywords: ["handler", "respond", "respond!", "init!", "shutdown!", "route", "routing",
      "request", "Request", "Response", "Outcome", "Server", "webserver", "web server",
      "http server", "endpoint", "status", "body", "read_all!", "Context", "program", "404", "405"],
  },
  webserver_sqlite: {
    file: "webserver_sqlite.roc",
    scope: "basic-webserver",
    dir: "corpus/platforms/basic-webserver/topics",
    description: "SQLite from a request handler: open the pool in `init!`, `query_many!` with derived row codecs, `execute!` writes, transactions, and prepared statements.",
    keywords: ["sqlite", "Sqlite", "database", "db", "Db", "sql", "query", "query_many!",
      "execute!", "prepare!", "begin!", "commit!", "transaction", "params", "row", "pool",
      "QueryError", "migration"],
  },
  webserver_sse: {
    file: "webserver_sse.roc",
    scope: "basic-webserver",
    dir: "corpus/platforms/basic-webserver/topics",
    description: "Server-sent events: `Server.stream` over an `Sse.unfold!` state machine, the `Emit`/`Wait`/`End` step, wake scheduling, and named events with ids and retry.",
    keywords: ["sse", "Sse", "server-sent", "server sent events", "stream", "streaming",
      "EventSource", "unfold!", "Emit", "Wait", "End", "Step", "Source", "wake", "retry",
      "event_id", "Last-Event-ID", "push", "long poll"],
  },
  webserver_html: {
    file: "webserver_html.roc",
    scope: "basic-webserver",
    dir: "corpus/platforms/basic-webserver/topics",
    description: "Server-rendered HTML with `Html` and `Attribute`: escaped text by default, `element`/`void_element` for tags without helpers, and the one unescaped-HTML call.",
    keywords: ["html", "Html", "Attribute", "render", "template", "templating", "escape",
      "escaping", "xss", "element", "void_element", "text", "Node", "attribute", "class",
      "href", "dangerously_include_unescaped_html", "markup"],
  },
  webserver_forms: {
    file: "webserver_forms.roc",
    scope: "basic-webserver",
    dir: "corpus/platforms/basic-webserver/topics",
    description: "Form bodies: `parse_form_url_encoded` into a `Dict`, and `parse_multipart_form_data` into raw parts with their disposition and content type.",
    keywords: ["form", "forms", "multipart", "MultipartFormData", "urlencoded",
      "url-encoded", "x-www-form-urlencoded", "parse_form_url_encoded",
      "parse_multipart_form_data", "FormData", "upload", "file upload", "POST", "field",
      "boundary", "disposition"],
  },
  webserver_static: {
    file: "webserver_static.roc",
    scope: "basic-webserver",
    dir: "corpus/platforms/basic-webserver/topics",
    description: "Serving files: `FileRoot` and `RelativeFile`, native routes the host answers without entering Roc, and `file_response_with` for a transfer Roc authorized.",
    keywords: ["static", "static files", "file", "files", "asset", "assets", "download",
      "FileRoot", "RelativeFile", "file_root", "relative_file", "file_response",
      "file_response_with", "static_mount", "static_file", "native route", "with_native_routes",
      "cache", "attachment", "favicon"],
  },
  cli_app: {
    file: "cli_app.roc",
    scope: "basic-cli",
    dir: "corpus/platforms/basic-cli/topics",
    description: "The basic-cli application contract: `main!`, the `List(OsStr)` arguments, `Err(Exit(code))`, and turning error tags into messages at the edge.",
    keywords: ["main!", "app", "cli", "cli program", "cli tool", "command line", "command-line", "argument", "args",
      "argv", "OsStr", "exit", "Exit", "exit code", "entry point", "basic-cli", "usage",
      "error handling", "drop_first"],
  },
  cli_files: {
    file: "cli_files.roc",
    scope: "basic-cli",
    dir: "corpus/platforms/basic-cli/topics",
    description: "Files and directories through `Path`: whole-file reads and writes, metadata, `PathErr` matching, directory trees, and the buffered `File.Reader`.",
    keywords: ["file", "files", "path", "Path", "directory", "dir", "read", "write",
      "read_utf8!", "write_utf8!", "read_bytes!", "list!", "create_dir!", "create_all!",
      "delete!", "delete_all!", "PathErr", "IOErr", "NotFound", "metadata", "size",
      "File.Reader", "open_reader!", "buffered", "join", "filename", "ext"],
  },
  cli_command: {
    file: "cli_command.roc",
    scope: "basic-cli",
    dir: "corpus/platforms/basic-cli/topics",
    description: "Running other programs: `Cmd.exec!`, the chained `Cmd` builder, captured output, a controlled environment, and exit codes.",
    keywords: ["command", "Cmd", "exec", "exec!", "exec_cmd!", "exec_output!", "subprocess",
      "process", "spawn", "shell", "run", "stdout", "exit code", "exec_exit_code!",
      "check_available!", "env", "envs", "clear_envs", "arg", "args"],
  },
  cli_http: {
    file: "cli_http.roc",
    scope: "basic-cli",
    dir: "corpus/platforms/basic-cli/topics",
    description: "The HTTP client: `Http.get_utf8!`, `Http.send!`, JSON through `get!`/`send_json!`/`decode_json_response`, and the `roc-lang/http` request and response types.",
    keywords: ["http", "Http", "client", "request", "Request", "response", "Response",
      "get", "get!", "get_utf8!", "send!", "send_json!", "json", "REST", "api", "fetch",
      "curl", "header", "Header", "Method", "GET", "POST", "status", "TransportErr"],
  },
  cli_sqlite: {
    file: "cli_sqlite.roc",
    scope: "basic-cli",
    dir: "corpus/platforms/basic-cli/topics",
    description: "SQLite: `execute!` writes, `query!` and `query_many!` reads, hand-built row decoders, prepared statements, and the `Binding` value type.",
    keywords: ["sqlite", "Sqlite", "database", "db", "sql", "query", "query!", "query_many!",
      "execute!", "prepare!", "Stmt", "binding", "Binding", "row", "rows", "decoder",
      "nullable", "DecodeErr", "ErrCode", "NoSuchField", "transaction"],
  },
  cli_terminal: {
    file: "cli_terminal.roc",
    scope: "basic-cli",
    dir: "corpus/platforms/basic-cli/topics",
    description: "Standard streams, raw mode, and the small effects around them: `Stdin`/`Stdout`/`Stderr`, `Tty`, `Env`, `Utc`, `Sleep`, `Random`, `Locale`.",
    keywords: ["stdout", "Stdout", "stdin", "Stdin", "stderr", "Stderr", "print", "line!",
      "write!", "read", "input", "prompt", "EndOfFile", "tty", "Tty", "raw mode", "terminal",
      "env", "Env", "environment", "variable", "var!", "cwd", "time", "Utc", "now!",
      "timestamp", "iso8601", "sleep", "Sleep", "random", "Random", "seed", "locale", "Locale"],
  },
  cli_net: {
    file: "cli_net.roc",
    scope: "basic-cli",
    dir: "corpus/platforms/basic-cli/topics",
    description: "TCP streams and URL parsing: `Tcp.connect!`, the four reads and their per-call timeouts, and `Url.parse` with its accessors and relative resolution.",
    keywords: ["tcp", "Tcp", "socket", "stream", "Stream", "connect!", "read_line!",
      "read_exactly!", "read_until!", "read_up_to!", "write_utf8!", "timeout", "ConnectErr",
      "url", "Url", "parse", "resolve", "scheme", "host", "port", "query", "fragment"],
  },
};

/**
 * Merges this server's topics with the topics of every declared plugin.
 *
 * `get_roc_syntax(topic:)` finds a topic by its name, so two corpora cannot share
 * one name. A plugin topic with a name that is already served goes into
 * `conflicts` and is not served. This server's own names win, because a plugin
 * must never change the answer to an existing call.
 */
export function mergeTopics(
  builtin: Record<string, TopicMeta>,
  scopes: readonly ScopeName[],
  defs: Record<string, { topics?: readonly ScopeTopic[] }>,
  conflicts: string[],
  packages: readonly { name: string; topics?: readonly ScopeTopic[] }[] = []
): Record<string, TopicMeta> {
  const merged: Record<string, TopicMeta> = { ...builtin };
  const sources = [
    ...scopes.map((scope) => ({ from: scope, topics: defs[scope]?.topics, tag: { scope } })),
    ...packages.map((doc) => ({ from: doc.name, topics: doc.topics, tag: { package: doc.name } })),
  ];
  for (const { from, topics, tag } of sources) {
    for (const topic of topics ?? []) {
      if (merged[topic.name]) {
        conflicts.push(`${from} declares topic ${topic.name}, which is already served`);
        continue;
      }
      merged[topic.name] = {
        file: path.basename(topic.file),
        dir: path.dirname(topic.file),
        description: topic.description,
        keywords: [...topic.keywords],
        ...tag,
      };
    }
  }
  return merged;
}

/** The topics a catalog serves, and the ones it declared and could not serve. */
export interface TopicTable {
  topics: Record<string, TopicMeta>;
  conflicts: readonly string[];
}

const tables = new WeakMap<Catalog, TopicTable>();

export function topicsFor(catalog: Catalog): TopicTable {
  let table = tables.get(catalog);
  if (!table) {
    const conflicts: string[] = [];
    const topics = mergeTopics(BUILTIN_TOPICS, catalog.scopes, catalog.scopeDefs, conflicts, catalog.packageDocs);
    table = { topics, conflicts };
    tables.set(catalog, table);
  }
  return table;
}

/**
 * The path of a topic's program, for a topic from this server or from a plugin.
 *
 * `path.resolve` keeps the absolute directory of a plugin as it is and does not
 * put it under `ROOT`.
 */
export function topicPath(meta: TopicMeta): string {
  return meta.dir ? path.resolve(ROOT, meta.dir, meta.file) : path.join(TOPICS_DIR, meta.file);
}

export function loadTopic(topic: string, topics: Record<string, TopicMeta>): string | null {
  const meta = topics[topic];
  if (!meta) return null;
  const filePath = topicPath(meta);
  try {
    return fs.readFileSync(filePath, "utf-8");
  } catch {
    return null;
  }
}

/** Where `needle` starts inside `hay` as a run of whole words, or -1. */
function phraseAt(hay: readonly string[], needle: readonly string[]): number {
  if (needle.length === 0 || needle.length > hay.length) return -1;
  return hay.findIndex((_, i) => needle.every((w, j) => hay[i + j] === w));
}

/** One topic that covers some content words of a question. */
export interface TopicRank {
  name: string;
  /** How many content words of the question the topic's name words and keywords cover. */
  covered: number;
}

/**
 * The answer to `get_roc_syntax(topic:)`. `topic` is null when no topic is a
 * sure match, and the caller then shows `ranked` as pointers. When `topic` is
 * set, `ranked` holds the other candidates.
 */
export interface TopicMatch {
  topic: string | null;
  /** The step that found `topic`. `keyword` means a keyword that no other topic has, and `words` the words of a question. */
  by?: "name" | "keyword" | "words";
  /** The content words of the question that `topic` covers, when the words found it. */
  covered?: number;
  ranked: TopicRank[];
}

/**
 * Finds the topic for a name, a keyword or a question. The steps go from strict
 * to loose:
 *   1. A topic name.
 *   2. A keyword that only one topic has. A keyword such as "parse" that three
 *      topics share goes to step 3.
 *   3. The topic that covers clearly more content words of the question than
 *      any other. "Clearly more" is 1 word for a question with fewer than 5
 *      content words, and 2 words for a longer one.
 * Any other query gets no topic, because a wrong topic costs a whole program of
 * tokens and a list of pointers costs a few lines.
 */
export function matchTopic(
  query: string,
  scopes: readonly string[] | undefined,
  /** The table to search: `topicsFor(catalog).topics` for a server's own. */
  table: Record<string, TopicMeta>
): TopicMatch {
  const q = query.toLowerCase().trim();
  const entries = Object.entries(table).filter(
    ([, meta]) => !scopes || scopes.includes(meta.scope ?? "language")
  );
  const asked = question(q);
  const ranked = rankTopics(asked, entries);
  const others = (name: string) => ranked.filter((r) => r.name !== name);
  if (entries.some(([n]) => n === q)) return { topic: q, by: "name", ranked: others(q) };
  const owners = entries.filter(([, meta]) => meta.keywords.some((k) => k.toLowerCase() === q));
  if (owners.length === 1) return { topic: owners[0][0], by: "keyword", ranked: others(owners[0][0]) };

  const [top, next] = ranked;
  const margin = asked.content.size >= 5 ? 2 : 1;
  if (top && top.covered - (next?.covered ?? 0) >= margin) return { topic: top.name, by: "words", covered: top.covered, ranked: others(top.name) };
  return { topic: null, ranked };
}

/**
 * The topics that cover content words of the question, most first. Ties keep
 * declaration order.
 *
 * Every word of a topic name counts alone, so "pattern match on a list" reaches
 * `list_patterns`. A keyword counts as a phrase of whole words. A raw substring
 * match is wrong because `str`, a keyword of `strings`, is inside "how do I
 * structure a game". A keyword under three characters counts only in step 2 of
 * `matchTopic`, because `_` is a keyword of `derived_methods` and every
 * snake_case query contains `_`.
 */
function rankTopics({ asked, content }: Question, entries: [string, TopicMeta][]): TopicRank[] {
  const ranked: TopicRank[] = [];
  for (const [name, meta] of entries) {
    const hit = new Set<number>();
    const cover = (phrase: readonly string[]) => {
      const at = phraseAt(asked, phrase);
      if (at === -1) return;
      for (let i = 0; i < phrase.length; i++) if (content.has(at + i)) hit.add(at + i);
    };
    for (const w of words(name)) cover([singular(w)]);
    for (const raw of meta.keywords) {
      if (raw.length >= 3) cover(words(raw).map(singular));
    }
    if (hit.size > 0) ranked.push({ name, covered: hit.size });
  }
  return ranked.sort((a, b) => b.covered - a.covered);
}

