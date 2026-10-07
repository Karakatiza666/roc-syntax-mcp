// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The two transforms roc_check applies, tested without a compiler.
//
// scripts/check-platform-examples.sh proves that the scaffold and a wrapped
// handler compile. These tests cover the rest:
// - which definitions the scaffold supplies,
// - where the caller's line 1 goes,
// - which diagnostics belong to the caller and which to a downloaded package.

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  LOCAL_TIMEOUT_MS,
  REMOTE_TIMEOUT_MS,
  formatReport,
  hasHeader,
  packageAliases,
  parseReport,
  remap,
  scaffold,
  scratchDir,
  timeoutFor,
  topLevelNames,
  type Diagnostic,
} from "./roc_check.ts";
import { CORE } from "./scopes.ts";

const HANDLER = `respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, _context| Ok(Server.respond(Response.from_status(200)))
`;

// -----------------------------------------------------------------------------
// Headers
// -----------------------------------------------------------------------------

test("a header is recognized through the doc comment above it", () => {
  assert.ok(hasHeader("## Routing.\n# a note\napp [Context, program] {\n}\n"));
  assert.ok(hasHeader("module [x]\n"));
  assert.ok(hasHeader("package [A] {}\n"));
  assert.ok(hasHeader('platform "webserver"\n'));
});

test("a bare handler has no header, and a name starting with app is not one", () => {
  assert.ok(!hasHeader(HANDLER));
  assert.ok(!hasHeader("apple = 1\n"));
  assert.ok(!hasHeader(""));
});

test("only column-zero declarations count as top level", () => {
  const names = topLevelNames(
    "Context : {}\nrespond! = |a| {\n\tinner = 1\n\tinner\n}\nx = 2\n"
  );
  assert.deepEqual([...names].sort(), ["Context", "respond!", "x"]);
});

// -----------------------------------------------------------------------------
// Scaffolding
// -----------------------------------------------------------------------------

test("source with a header of its own is handed to the compiler untouched", () => {
  const app = "app [Context, program] {\n}\n";
  const out = scaffold(app, "basic-webserver", CORE);
  assert.equal(out.source, app);
  assert.equal(out.offset, 0);
  assert.equal(out.scope, null);
});

test("without a scope nothing is wrapped", () => {
  assert.equal(scaffold(HANDLER, undefined, CORE).source, HANDLER);
});

test("the offset lands exactly on the caller's first line", () => {
  const out = scaffold(HANDLER, "basic-webserver", CORE);
  assert.ok(out.offset > 0);
  // The compiler reports line N, and the caller wrote it at N - offset. So line
  // 1 of the submission is at index `offset` of the composed source.
  assert.equal(out.source.split("\n")[out.offset], HANDLER.split("\n")[0]);
});

test("the scaffold supplies every definition the submission omits", () => {
  const out = scaffold(HANDLER, "basic-webserver", CORE);
  assert.deepEqual(out.supplied, ["Context", "program", "init!", "shutdown!"]);
  assert.equal(out.scope, "basic-webserver");
  assert.match(out.source, /^app \[Context, program\] \{/m);
});

test("a definition the submission makes is not supplied twice", () => {
  const out = scaffold(`Context : { greeting : Str }\n\n${HANDLER}`, "basic-webserver", CORE);
  assert.deepEqual(out.supplied, ["program", "init!", "shutdown!"]);
  assert.equal(out.source.match(/^Context :/gm)!.length, 1);
});

// An import in both the prelude and the submission gives a duplicate-definition
// warning, which looks like a defect in correct code.
test("an import the submission already makes is dropped from the prelude", () => {
  const out = scaffold(`import pf.Server\nimport http.Response\n\n${HANDLER}`, "basic-webserver", CORE);
  assert.equal(out.source.match(/^import pf\.Server$/gm)!.length, 1);
  assert.equal(out.source.match(/^import http\.Response$/gm)!.length, 1);
  // The prelude keeps the imports that the submission does not have.
  assert.match(out.source, /^import pf\.Sqlite$/m);
});

// The `##` header of the scaffold file is for its editors. It does not belong in
// the source that the caller's errors refer to.
test("the scaffold file's own doc comment stays out of the composed source", () => {
  const out = scaffold(HANDLER, "basic-webserver", CORE);
  assert.ok(out.source.startsWith("app ["), out.source.slice(0, 60));
  assert.ok(!out.source.includes("@user-code"));
  assert.ok(!out.source.includes("@default"));
});

// -----------------------------------------------------------------------------
// Reading the report
// -----------------------------------------------------------------------------

const CACHE = "/home/u/.cache/roc/packages/Ce3xuHN92F5oGRuzjUTmm65jULAEj8pvvrTBmZJzE1M4";
const REPORT = [
  "── ✗ missing method ─────────────────────────────── /tmp/roc-check-a/main.roc:35:16",
  "",
  "This methodd method is being called on a value.",
  "",
  `── ✗ missing method ─ ${CACHE}/Date.roc:163:31`,
  "",
  "This map method is being called on a value.",
  "",
  `── ● unused variable ─ ${CACHE}/Date.roc:28:28`,
  "",
  "── ✗ file not found ────────────────────────────────────────────────────────────",
  "",
  "── 3 errors and 1 warning ──────────────────────────────────────────── main.roc",
  "",
].join("\n");

test("diagnostics split on the block rule, and the tally is not one of them", () => {
  const r = parseReport(REPORT);
  assert.equal(r.user.length, 2);
  assert.equal(r.dependency.length, 2);
  assert.match(r.summary, /^── 3 errors and 1 warning/);
});

test("a header that names no file is still the caller's problem", () => {
  const r = parseReport(REPORT);
  const orphan = r.user.find((d) => d.text.includes("file not found"))!;
  assert.equal(orphan.file, null);
  assert.equal(orphan.line, null);
});

test("severity comes from the bullet the compiler heads the block with", () => {
  const r = parseReport(REPORT);
  assert.deepEqual(
    r.dependency.map((d) => d.severity),
    ["error", "warning"]
  );
});

// A match from the first run of box-drawing characters, not the last, puts the
// block title into the path. Then the path differs from the checked file, and
// remap changes nothing.
test("a header padded out to terminal width still yields its path", () => {
  const r = parseReport(REPORT);
  assert.equal(r.user[0].file, "/tmp/roc-check-a/main.roc");
  assert.equal(r.user[0].line, 35);
  assert.equal(r.user[0].column, 16);
});

test("remap moves the caller's line back and names a file that still exists", () => {
  const r = parseReport(REPORT);
  const d = remap(r.user[0], "/tmp/roc-check-a/main.roc", 32);
  assert.equal(d.line, 3);
  assert.equal(d.file, "main.roc");
  assert.match(d.text, /main\.roc:3:16/);
  assert.ok(!d.text.includes("/tmp/roc-check-a"), "the temporary path survived");
});

// The compiler prints the path relative to its own working directory, so the
// path in the report and the absolute input path are different strings for the
// same file. A literal comparison remaps nothing. The caller then gets a line
// number in the scaffolded source and a path to a deleted directory.
test("remap matches a path the compiler printed relative to its cwd", () => {
  const cwd = process.cwd();
  const target = path.join(cwd, "sub", "main.roc");
  const report = [
    "── ✗ missing method ─ sub/main.roc:35:16",
    "",
    "This methodd method is being called on a value.",
    "",
  ].join("\n");
  const d = remap(parseReport(report).user[0], target, 32);
  assert.equal(d.line, 3);
  assert.equal(d.file, "main.roc");
  assert.match(d.text, /main\.roc:3:16/);
  assert.ok(!d.text.includes("sub/main.roc"), "the temporary path survived");
});

test("remap leaves a diagnostic in another file alone", () => {
  const r = parseReport(REPORT);
  const before = r.dependency[0];
  assert.deepEqual(remap(before, "/tmp/roc-check-a/main.roc", 32), before);
});

test("a package alias is read off the header that pins it", () => {
  const aliases = packageAliases(`app [Context, program] {
	pf: platform "https://example.com/0.16.0/AAAA.tar.zst",
	gregorian: "https://cdn.example.com/rc.2/Ce3xuHN92F5oGRuzjUTmm65jULAEj8pvvrTBmZJzE1M4.tar.zst",
}`);
  assert.equal(aliases.get("AAAA"), "pf");
  assert.equal(aliases.get("Ce3xuHN92F5oGRuzjUTmm65jULAEj8pvvrTBmZJzE1M4"), "gregorian");
});

// The one real error must come first, not after 14 dependency errors.
test("the caller's errors are shown in full and the package's are counted", () => {
  const r = parseReport(REPORT);
  const text = formatReport(r, {
    source: 'app [Context, program] {\n\tgregorian: "https://x/Ce3xuHN92F5oGRuzjUTmm65jULAEj8pvvrTBmZJzE1M4.tar.zst",\n}',
    supplied: [],
    wrappedIn: null,
    ok: false,
  });
  assert.match(text, /^`roc check` failed: 2 errors\./m);
  assert.match(text, /This methodd method/);
  assert.ok(!text.includes("This map method"), "a package's own error text was reprinted");
  assert.match(text, /gregorian\/Date\.roc: 2/);
  assert.ok(
    text.indexOf("This methodd method") < text.indexOf("gregorian/Date.roc"),
    "the package tally came before the caller's error"
  );
});

test("a clean check says so, and a wrap says what it added", () => {
  const clean = formatReport(parseReport(""), { source: "", supplied: [], wrappedIn: null, ok: true });
  assert.match(clean, /passed/);
  const wrapped = formatReport(parseReport(""), {
    source: "",
    supplied: ["init!"],
    wrappedIn: scaffold(HANDLER, "basic-webserver", CORE).wrappedIn,
    ok: true,
  });
  assert.match(wrapped, /basic-webserver 0\.17\.0 app\. Scaffolded: init!/);
});

// A compiler that cannot run prints nothing and exits non-zero. If no output
// counts as success, the caller learns that unchecked code passed. An
// acceptance run once reported eight false passes this way.
test("a non-zero exit with no diagnostic is not a pass", () => {
  const text = formatReport(parseReport(""), {
    source: "",
    supplied: [],
    wrappedIn: null,
    ok: false,
    raw: "error: unable to spawn",
  });
  assert.ok(!/passed/.test(text), text);
  assert.match(text, /was not checked/);
  assert.match(text, /error: unable to spawn/);
});

// `roc check` deletes every `/tmp/roc-*` directory at startup. A file in such a
// directory is gone before the compiler reads it, and the result is "file not
// found".
test("scratch space is named so the compiler will not delete it", () => {
  const dir = scratchDir("check");
  try {
    assert.ok(!path.basename(dir).startsWith("roc-"), dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------------
// Timeout
// -----------------------------------------------------------------------------

// 30s is enough for any local check, but not for the first check of a new
// platform, which downloads 29MB. Only source that names a package can wait on
// a download, so only that source gets the long timeout.
test("the timeout follows the packages the header pins", () => {
  assert.equal(timeoutFor("module [x]\n\nx = 1\n"), LOCAL_TIMEOUT_MS);
  assert.equal(
    timeoutFor('app [Context, program] {\n\tpf: platform "https://x/y/A.tar.zst",\n}'),
    REMOTE_TIMEOUT_MS
  );
  assert.equal(timeoutFor(scaffold(HANDLER, "basic-webserver", CORE).source), REMOTE_TIMEOUT_MS);
});
