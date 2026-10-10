// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { parseBuiltin } from "./builtin_parser.ts";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const index = parseBuiltin(fs.readFileSync(path.join(ROOT, "corpus", "language", "Builtin.roc"), "utf8"));

// Record-body fields must never enter the index as methods. Each name below is a
// field of a type header, an argument record, or an uppercase record alias.
const PHANTOMS = [
  // Bug A: multi-line type header leaks body fields to the enclosing module.
  "Num.lower", "Num.upper", "Num.step", "Num.upper_bound", "Num.direction",
  "Num.len_if_known", "Num.is_negative", "Num.digits_before_pt",
  "Num.digits_after_pt", "Num.digits_after_pt_count",
  // Bug B: continuation lines re-read as their own items.
  "Num.Range.lower", "Num.Range.upper", "Num.Range.step",
  "Num.Range.upper_bound", "Num.Range.direction", "Num.Range.len_if_known",
  "Encoding.ParseTagUnionSpec.tag", "Encoding.ParseTagUnionSpec.encoding",
  "Encoding.ParseTagUnionSpec.state", "Encoding.ParseTagUnionSpec.start_payloads",
  "Encoding.ParseTagUnionSpec.next_payload",
  "Encoding.ParseTagUnionSpec.finish_payloads",
  "Encoding.ParseTagUnionSpec.missing",
  // Bug C: uppercase record alias fields land on the parent module.
  "Dict.entries", "Dict.buckets", "Dict.max_entries_before_grow", "Dict.shifts",
];

// Genuine methods whose signature wraps onto following lines, so they look like
// record fields to any comma-based heuristic.
const GENUINE = [
  "Num.Numeral.is_negative", "Num.Numeral.digits_before_pt",
  "Num.Numeral.digits_after_pt", "Num.Numeral.digits_after_pt_count",
  "Num.Range.custom", "Encoding.FieldName.name",
  "Encoding.ParseTagUnionSpec.parse", "Encoding.JsonEncoding.parse_record_field",
  "Encoding.HttpHeaderEncoding.parse_record_field",
  "Encoding.HttpHeader.parse_record_field_from_headers",
];

test("every method has a module path", () => {
  const orphans = index.items.filter((i) => i.kind === "value" && i.modulePath === "");
  assert.deepEqual(orphans.map((i) => `${i.name}:${i.line}`), []);
});

// A type declared directly inside `Builtin` has no enclosing module, so an empty
// modulePath is correct for it and only for it. `Try := [Ok(ok), Err(err)]` is
// the shape a caller looks up by the bare name `Try`.
test("top-level types are the only items without a module path", () => {
  const orphans = index.items.filter((i) => i.modulePath === "").map((i) => i.fullName);
  assert.deepEqual(orphans.sort(), [
    "Bool", "Dict", "Hasher", "Iter", "ScannedJsonString", "Set", "Stream", "Try",
  ]);
});

test("record fields are not indexed as methods", () => {
  const present = PHANTOMS.filter((n) => index.byFullName.has(n));
  assert.deepEqual(present, []);
});

test("genuine methods survive", () => {
  const missing = GENUINE.filter((n) => !index.byFullName.has(n));
  assert.deepEqual(missing, []);
});

test("no duplicate full names", () => {
  const seen = new Set<string>();
  const dupes: string[] = [];
  for (const i of index.items) {
    if (seen.has(i.fullName)) dupes.push(i.fullName);
    seen.add(i.fullName);
  }
  assert.deepEqual(dupes, []);
});

test("signatures of wrapped methods stay intact", () => {
  const custom = index.byFullName.get("Num.Range.custom");
  assert.ok(custom, "Num.Range.custom missing");
  assert.match(custom!.signature, /lower/);
  assert.match(custom!.signature, /upper_bound/);

  const name = index.byFullName.get("Encoding.FieldName.name");
  assert.ok(name, "Encoding.FieldName.name missing");
  assert.match(name!.signature, /FieldName\(_shape\)\s*->\s*Str/);
});

const INT_WIDTHS = ["I8", "I16", "I32", "I64", "I128", "U8", "U16", "U32", "U64", "U128"];

test("upstream-deleted builtins do not resolve", () => {
  const gone = ["List.encode", "List.join_with", "Num.Dec.to_i128_try", "Num.Dec.to_i128_wrap", "Try.from_interpolation"];
  for (const t of INT_WIDTHS) {
    gone.push(`Num.${t}.shift_left_by`, `Num.${t}.shift_right_by`, `Num.${t}.shift_right_zf_by`);
  }
  // `compare` became `order_relative_to` at commit 2d69988, on every numeric
  // type that had it. `Num.F32`/`F64` never had one.
  for (const t of [...INT_WIDTHS, "Dec"]) gone.push(`Num.${t}.compare`);
  assert.equal(gone.length, 46);
  assert.deepEqual(gone.filter((n) => index.byFullName.has(n)), []);
});

test("current builtins resolve", () => {
  for (const n of ["Str.join_with", "List.subscript", "Iter.next", "Crypto.SHA256.hash",
                   "Hasher.write_str", "Stream.next!", "Try.catch", "Num.Range.iter",
                   "List.capacity", "List.sort", "List.sort_by_reversed"]) {
    assert.ok(index.byFullName.has(n), `${n} missing`);
  }

  // The ordering rename and the overflow predicates landed on every width at once.
  for (const t of [...INT_WIDTHS, "Dec"]) {
    assert.ok(index.byFullName.has(`Num.${t}.order_relative_to`), `Num.${t}.order_relative_to missing`);
  }
  for (const t of INT_WIDTHS) {
    for (const op of ["plus", "minus", "times"]) {
      assert.ok(index.byFullName.has(`Num.${t}.${op}_overflows`), `Num.${t}.${op}_overflows missing`);
    }
  }
});

// The tag union that sorting returns, renamed from [LT, EQ, GT] at 2d69988. A
// caller copies the signature, so pin the spelling and not only the name.
test("three-way ordering answers Before/Same/After", () => {
  assert.equal(
    index.byFullName.get("Num.U8.order_relative_to")!.signature,
    "U8, U8 -> [Before, Same, After]"
  );
  assert.equal(
    index.byFullName.get("List.sort_with")!.signature,
    "List(item), (item, item -> [Before, Same, After]) -> List(item)"
  );
});

// `where [a.Encodable([])]` is a where alias declared inside `Encoding.Json`,
// not the structural clause it replaced. A caller copying the signature has to
// qualify it, which `corpus/language/topics/json.roc` teaches, so pin the shape here.
test("the JSON codec entry points carry named where clauses", () => {
  assert.equal(index.byFullName.get("Encoding.Json.to_str")!.signature, "a -> Str where [a.Encodable([])]");
  assert.match(index.byFullName.get("Encoding.Json.parse")!.signature, /where \[a\.Parseable\(/);
  assert.match(
    index.byFullName.get("Encoding.HttpHeader.parse")!.signature,
    /where \[output\.Parseable\(/
  );
});

// -----------------------------------------------------------------------------
// Type declarations
// -----------------------------------------------------------------------------

const values = index.items.filter((i) => i.kind === "value");
const types = index.items.filter((i) => i.kind === "type");

test("Builtin.roc yields 2297 methods and 29 types", () => {
  assert.equal(values.length, 2297);
  assert.equal(types.length, 29);
});

test("a nominal type carries its variants and its own operator", () => {
  const t = index.byFullName.get("Try");
  assert.ok(t, "Try missing");
  assert.equal(t!.kind, "type");
  assert.equal(t!.decl, ":=");
  assert.equal(t!.head, "Try(ok, err)");
  assert.equal(t!.signature, "[Ok(ok), Err(err)]");

  const b = index.byFullName.get("Bool");
  assert.equal(b!.signature, "[False, True]");
  assert.equal(b!.decl, ":=");
});

test("a parameterized type keeps its parameters in the head", () => {
  const fn = index.byFullName.get("Encoding.FieldName");
  assert.ok(fn, "Encoding.FieldName missing");
  assert.equal(fn!.head, "FieldName(_shape)");
  assert.equal(fn!.decl, "::");
});

// `Str :: [ProvidedByCompiler]` and `Num :: {}` are namespaces, not types.
// If indexed, a body with no content comes before the module on an exact-name
// lookup, which is worse than the fuzzy fallback.
test("namespace declarations are not indexed as types", () => {
  for (const n of ["Str", "List", "Box", "Num", "Encoding", "Crypto", "Num.U8", "Num.U8x16"]) {
    const hit = index.byFullName.get(n);
    assert.ok(hit === undefined || hit.kind === "value", `${n} indexed as a type`);
  }
});

// `Shape : a` at Builtin.roc:237 sits inside an `expect` block and appears five
// times. Without the depth rule each one lands in the index as a duplicate
// `Encoding.Json.Shape`.
test("local annotations inside function bodies are not types", () => {
  assert.equal(index.byFullName.has("Encoding.Json.Shape"), false);
  assert.equal(types.filter((t) => t.name === "Shape").length, 0);
});

test("types do not collide with methods", () => {
  const byKind = new Map<string, Set<string>>();
  for (const i of index.items) {
    const set = byKind.get(i.fullName) ?? new Set<string>();
    set.add(i.kind);
    byKind.set(i.fullName, set);
  }
  const clashes = [...byKind.entries()].filter(([, k]) => k.size > 1).map(([n]) => n);
  assert.deepEqual(clashes, []);
});

// -----------------------------------------------------------------------------
// Visibility tier
// -----------------------------------------------------------------------------

// Upstream files with layouts that a simple parser gets wrong. They are kept as
// fixtures because no release source is vendored beside the corpus. They are
// byte-identical to the tagged releases.
const PLATFORM_DIR = path.join(ROOT, "src", "testdata", "upstream", "basic-webserver-0.17.0");
const CLI_DIR = path.join(ROOT, "src", "testdata", "upstream", "basic-cli-0.24.0");

function parseFile(dir: string, file: string) {
  return parseBuiltin(fs.readFileSync(path.join(dir, file), "utf-8"));
}

test("no builtin is host-tier", () => {
  assert.deepEqual(index.items.filter((i) => i.tier === "host").map((i) => i.fullName), []);
});

test("glue methods inside an exposed module are host-tier", () => {
  const server = parseFile(PLATFORM_DIR, "Server.roc");
  const host = server.items.filter((i) => i.tier === "host").map((i) => i.fullName);
  assert.equal(host.length, 20);
  for (const n of ["Server.Config.to_host", "Server.Request.from_host", "Server.Outcome.to_host",
                   "Server.Body.digest_to_host", "Server.WritableRoot.path_to_host"]) {
    assert.ok(host.includes(n), `${n} not marked host`);
  }
});

// A substring rule on "host" hides the two methods that read the HTTP Host
// header, and an app author who routes by hostname needs them.
test("Host-header methods are not mistaken for the host boundary", () => {
  const server = parseFile(PLATFORM_DIR, "Server.roc");
  const url = parseFile(PLATFORM_DIR, "Url.roc");
  const authority = server.byFullName.get("Server.Authority.host");
  const urlHost = url.byFullName.get("Url.host");
  assert.ok(authority && urlHost, "Server.Authority.host or Url.host missing");
  assert.equal(authority!.tier, "public");
  assert.equal(urlHost!.tier, "public");
});

// -----------------------------------------------------------------------------
// Definitions the source never annotated
// -----------------------------------------------------------------------------

// Upstream annotates most of what it exports, but not all. These exports have
// no annotation, and an index of only annotated values drops them:
// - `Sqlite.query_many!`, the primary read of its module,
// - `Tcp.connect!`, the only way to open a stream,
// - every `Html` element helper.
test("a module member with no annotation is still indexed", () => {
  const sqlite = parseFile(CLI_DIR, "Sqlite.roc");
  const query = sqlite.byFullName.get("Sqlite.query_many!");
  assert.ok(query, "Sqlite.query_many! was not indexed");
  assert.equal(query!.unannotated, true);
  assert.equal(query!.tier, "public");
  // The lambda head is all the shape the source gives, and it is not a type.
  assert.match(query!.signature, /^\|\{/);
  assert.match(query!.docs, /decode multiple rows/);

  const tcp = parseFile(CLI_DIR, "Tcp.roc");
  assert.equal(tcp.byFullName.get("Tcp.connect!")?.signature, "|host, port, timeout_ms|");
});

// The annotation is the better answer, and `name : sig` followed by `name = ...`
// is one declaration seen twice.
test("an annotated member is not indexed a second time from its definition", () => {
  const sqlite = parseFile(CLI_DIR, "Sqlite.roc");
  const prepare = sqlite.items.filter((i) => i.fullName === "Sqlite.prepare!");
  assert.equal(prepare.length, 1);
  assert.equal(prepare[0].unannotated, undefined);
  assert.match(prepare[0].signature, /=>/);
});

// A binding inside a function body or an `expect` block sits deeper than one
// level in, and indexing those would fill the corpus with `actual`, `cols` and
// `helper!`.
test("a binding in a function body is not a module member", () => {
  const cli = parseFile(CLI_DIR, "Sqlite.roc");
  for (const local of ["Sqlite.cols", "Sqlite.decode_row!", "Sqlite.helper!"]) {
    assert.ok(!cli.byFullName.has(local), `${local} was indexed as a module member`);
  }
  // An annotated local is also a local, so the value branch must accept only
  // one level in. `from_state` is annotated inside the body of `Sse.unfold!`.
  const sse = parseFile(PLATFORM_DIR, "Sse.roc");
  assert.ok(!sse.byFullName.has("Sse.from_state"), "an annotated local was indexed as a member");
  assert.ok(sse.byFullName.has("Sse.unfold!"), "the function it sits inside is a member");
});

// Two `expect` blocks in roc-ray's `Gamepad` open with `snapshot : Snapshot`.
// Indexing both puts one name twice in one namespace, and `plugin validate`
// reports that as a duplicate.
test("an annotated binding inside an expect block is not a module member", () => {
  const parsed = parseBuiltin(
    [
      "Pad :: [].{",
      "\tlookup : Str -> Str",
      "\tlookup = |name| name",
      "",
      "\texpect {",
      "\t\tsnapshot : Str",
      "\t\tsnapshot = \"one\"",
      "\t\tlookup(snapshot) == \"one\"",
      "\t}",
      "",
      "\texpect {",
      "\t\tsnapshot : Str",
      "\t\tsnapshot = \"two\"",
      "\t\tlookup(snapshot) == \"two\"",
      "\t}",
      "}",
    ].join("\n")
  );
  assert.deepEqual(parsed.items.map((i) => i.fullName), ["Pad.lookup"]);
});

// Every builtin is annotated, so this branch must add nothing to the builtins.
test("indexing unannotated members leaves Builtin.roc untouched", () => {
  assert.deepEqual(index.items.filter((i) => i.unannotated).map((i) => i.fullName), []);
});

// One upstream file uses four spaces for indentation, not tabs. A parser that
// counts only tabs reads all of it as top-level and indexes nothing from it.
test("a space-indented source file is parsed like a tab-indented one", () => {
  const internal = parseFile(CLI_DIR, "InternalSqlite.roc");
  assert.deepEqual(
    internal.items.map((i) => i.fullName).sort(),
    ["InternalSqlite.SqliteBindings", "InternalSqlite.SqliteError",
     "InternalSqlite.SqliteState", "InternalSqlite.SqliteValue"]
  );
  assert.equal(internal.byFullName.get("InternalSqlite.SqliteValue")!.kind, "type");
});

// No bundled corpus has an unannotated constant, so the test checks the
// fallback against an inline source, not against the corpus.
test("an unannotated constant says it has no type rather than inventing one", () => {
  const parsed = parseBuiltin(
    ["Demo :: [].{", "\t## The default port.", "\tport = 8080", "}"].join("\n")
  );
  const item = parsed.byFullName.get("Demo.port");
  assert.ok(item, "Demo.port was not indexed");
  assert.equal(item!.unannotated, true);
  assert.equal(item!.signature, "(no type annotation)");
  assert.equal(item!.docs, "The default port.");
});
