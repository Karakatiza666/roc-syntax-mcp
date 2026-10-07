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
