// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// A server is built from a config value, not from the process that it runs in.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { InMemoryTransport, LATEST_PROTOCOL_VERSION } from "@modelcontextprotocol/server";
import { createServer, serverConfig } from "./server.ts";

const ROOT = path.join(import.meta.dirname, "..");
const TSX_LOADER = import.meta.resolve("tsx/esm");
const RAY = path.join(ROOT, "plugins", "roc-ray");
let tmp: string;

before(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roc-server-"));
});
after(() => fs.rmSync(tmp, { recursive: true, force: true }));

// The plugin CLI, the check scripts and an embedder import these modules. A module that read
// `--plugin=` or opened stdio as it loaded would act on a process it does not own.
test("importing the server reads no configuration and starts nothing", () => {
  const r = spawnSync(
    process.execPath,
    [
      "--import",
      TSX_LOADER,
      "--input-type=module",
      "-e",
      'const S = await import("./src/scopes.ts"); await import("./src/server.ts");' +
        "console.log(JSON.stringify({ ray: S.CORE.scopes.includes('roc-ray'), problems: S.CORE.diagnostics.length }));",
      // This string is `process.argv[1]`, so the flags after it go where a server reads them.
      "ignored",
      `--plugin=${RAY}`,
      "--plugin=/no/such/plugin",
    ],
    // stdin stays open, so a server that started would never exit.
    { cwd: ROOT, encoding: "utf-8", timeout: 30_000, stdio: ["pipe", "pipe", "pipe"] }
  );
  assert.equal(r.signal, null, "the import started something that kept the process alive");
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { ray: false, problems: 0 });
  assert.doesNotMatch(r.stderr, /roc-syntax/);
});

/** A server for `argv`, connected in this process, and a way to call its tools. */
async function inProcess(argv: string[]) {
  const config = serverConfig(argv, { ...process.env, CLAUDE_PROJECT_DIR: tmp });
  const [client, server] = InMemoryTransport.createLinkedPair();
  const waiting = new Map<number, (m: any) => void>();
  client.onmessage = (m: any) => waiting.get(m.id)?.(m);
  await createServer(config).connect(server);
  await client.start();
  let id = 0;
  const send = (method: string, params: unknown) =>
    new Promise<any>((resolve) => {
      const n = ++id;
      waiting.set(n, resolve);
      void client.send({ jsonrpc: "2.0", id: n, method, params } as never);
    });
  await send("initialize", { protocolVersion: LATEST_PROTOCOL_VERSION, capabilities: {}, clientInfo: { name: "t", version: "1" } });
  await client.send({ jsonrpc: "2.0", method: "notifications/initialized" } as never);
  const call = async (name: string, args: unknown) =>
    (await send("tools/call", { name, arguments: args })).result.content[0].text as string;
  return { config, call, close: () => client.close() };
}

// Two servers in one process, each with the plugins that its own config declared.
// If the module read the plugin set at load, the second server would serve the
// plugins of the first.
test("two servers in one process each serve their own plugins", async () => {
  const withRay = await inProcess([`--plugin=${RAY}`]);
  const plain = await inProcess([]);
  try {
    assert.deepEqual(withRay.config.catalog.diagnostics, []);
    assert.match(await withRay.call("list_roc_index", { kind: "scopes" }), /roc-ray/);
    assert.doesNotMatch(await plain.call("list_roc_index", { kind: "scopes" }), /roc-ray/);
    assert.match(await withRay.call("roc_overview", { scope: "roc-ray" }), /roc-ray/);
  } finally {
    await withRay.close();
    await plain.close();
  }
});

// `F32.floor_to_i64` names no builtin. The substring search must drop the
// module from the query, because it compares the query with bare names.
test("a missed qualified name lists close names in that module", async () => {
  const s = await inProcess([]);
  try {
    const text = await s.call("search_symbols", { query: "F32.floor_to_i64" });
    assert.match(text, /^Nothing is named `F32.floor_to_i64`. 1 name contains `floor_to_i64`:/);
    assert.match(text, /Num\.F32\.floor_to_i64_try/);
    assert.doesNotMatch(text, /Num\.F64\./);
  } finally {
    await s.close();
  }
});

// `Text.Builder.size` has the module path `Text.Builder`. A page with only
// the items of `Text` shows the `Builder` type and none of its methods.
test("a module page lists the methods of its nested types, up to a cap", async () => {
  const ray = await inProcess([`--plugin=${RAY}`]);
  const plain = await inProcess([]);
  try {
    const text = await ray.call("get_builtin_module", { module: "Text", scope: "roc-ray" });
    assert.match(text, /^## Text\.Builder\n\n5 methods\.\n\n```roc\n[^`]*prepare! : Builder => /m);
    const num = await plain.call("get_builtin_module", { module: "Num" });
    assert.match(num, /Nested modules, with the item count of each: [^\n]*`Num\.U64` \(\d+\)/);
    assert.doesNotMatch(num, /^## Num\./m);
  } finally {
    await ray.close();
    await plain.close();
  }
});

// A name and a type: the name filters, and the type ranks. `-> F32` matches
// `ceiling_to_i32_try : F32 -> Try(I32, ..)` as a substring only, and that
// match must not read as an answer.
test("a name and a type search the names, ranked by type", async () => {
  const s = await inProcess([]);
  try {
    const dec = await s.call("search_symbols", { query: "ceil : -> Dec" });
    assert.match(dec, /^\*\*Num\.Dec\.ceiling\*\* \(return_type, score 90\)/);
    assert.doesNotMatch(dec, /Num\.Dec\.round/);
    // Both score 90. The whole name `floor` breaks the tie, before the order by name.
    const floor = await s.call("search_symbols", { query: "floor : -> Dec" });
    assert.ok(floor.indexOf("**Num.Dec.floor**") < floor.indexOf("**Num.Dec.div_floor_by**"), floor);
    const f32 = await s.call("search_symbols", { query: "ceil : -> F32" });
    assert.match(f32, /^No symbol similar to `ceil` matches `-> F32`\. \d+ symbols have a different type\. Closest matches:/);
    assert.doesNotMatch(f32, /substring/);
    // A type that names `F32` is closer than `Num.Dec.ceiling : Dec -> Dec`.
    assert.match(f32, /Closest matches:\n\n\*\*Num\.F32\.ceiling_/);
  } finally {
    await s.close();
  }
});

// A list of partial names shows a prefix match before a match inside the name,
// and one line of docs for each, not the whole docstring.
test("a partial name lists compact entries, prefixes first", async () => {
  const s = await inProcess([]);
  try {
    const text = await s.call("search_symbols", { query: "ceil", limit: 100 });
    assert.ok(text.indexOf("**Num.Dec.ceiling**") >= 0, text);
    assert.ok(text.indexOf("**Num.Dec.ceiling**") < text.indexOf("div_ceil_by**"), "a prefix ranks first");
    // The default order puts the shallower `Num.F32.infinity` first.
    const fini = await s.call("search_symbols", { query: "fini" });
    assert.ok(fini.indexOf(".finish**") >= 0 && fini.indexOf(".finish**") < fini.indexOf(".infinity**"), fini);
    assert.doesNotMatch(text, /expect /);
    assert.match(await s.call("search_symbols", { query: "ceil", limit: 3 }), /Showing 3 of \d+\./);
  } finally {
    await s.close();
  }
});

// One word is a name, and `Try` is a type with its docs. `: Str` is a type query.
test("a one-word query is a name, and a colon makes it a type", async () => {
  const s = await inProcess([]);
  try {
    assert.match(await s.call("search_symbols", { query: "Try" }), /`Try` is also a module/);
    assert.match(await s.call("search_symbols", { query: ": Str" }), /\(return_type, score 80\)/);
  } finally {
    await s.close();
  }
});
