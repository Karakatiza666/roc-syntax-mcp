// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as http from "node:http";
import * as os from "node:os";
import * as path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { LATEST_PROTOCOL_VERSION } from "@modelcontextprotocol/server";
import { findRoc, installRoc, nightlyAsset, useRoc } from "./roc_bin.ts";

const ROOT = path.join(import.meta.dirname, "..");
const TSX_LOADER = import.meta.resolve("tsx/esm");
let tmp: string;

before(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roc-bin-"));
});
after(() => fs.rmSync(tmp, { recursive: true, force: true }));

/** A `roc` that answers `version` and passes every `check`. */
function fakeRoc(dir: string, version = "Roc compiler version nightly-fake"): string {
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, "roc");
  fs.writeFileSync(file, `#!/bin/sh\n[ "$1" = version ] && echo "${version}"\nexit 0\n`, { mode: 0o755 });
  return file;
}

const unix = process.platform !== "win32";

test("an explicit flag or variable wins, then the recorded binary, then PATH", { skip: !unix }, () => {
  const home = path.join(tmp, "order");
  const roc = fakeRoc(path.join(tmp, "order-bin"));
  assert.deepEqual(findRoc([], { ROC_MCP_HOME: home }), { command: "roc", source: "PATH" });
  assert.equal(useRoc(roc, { ROC_MCP_HOME: home }).ok, true);
  assert.deepEqual(findRoc([], { ROC_MCP_HOME: home }), { command: roc, source: "roc use" });
  assert.deepEqual(findRoc([], { ROC_MCP_HOME: home, ROC: "/env/roc" }), { command: "/env/roc", source: "ROC" });
  assert.deepEqual(findRoc(["--roc=/flag/roc"], { ROC_MCP_HOME: home, ROC: "/env/roc" }), {
    command: "/flag/roc",
    source: "--roc=",
  });
  // A recorded binary that was deleted falls back to PATH, not to a path that fails.
  fs.rmSync(roc);
  assert.deepEqual(findRoc([], { ROC_MCP_HOME: home }), { command: "roc", source: "PATH" });
});

test("use refuses a binary that does not run, and records nothing", () => {
  const home = path.join(tmp, "use-bad");
  const result = useRoc(path.join(tmp, "no-such-roc"), { ROC_MCP_HOME: home });
  assert.equal(result.ok, false);
  assert.deepEqual(findRoc([], { ROC_MCP_HOME: home }), { command: "roc", source: "PATH" });
});

test("each machine maps to the asset roc-lang/nightlies publishes for it", () => {
  const tag = "nightly-2026-10-06-c34079d";
  assert.equal(nightlyAsset(tag, "linux", "x64"), "roc_nightly-linux_x86_64-2026-10-06-c34079d.tar.gz");
  assert.equal(nightlyAsset(tag, "linux", "arm64"), "roc_nightly-linux_arm64-2026-10-06-c34079d.tar.gz");
  assert.equal(nightlyAsset(tag, "darwin", "arm64"), "roc_nightly-macos_apple_silicon-2026-10-06-c34079d.tar.gz");
  assert.equal(nightlyAsset(tag, "darwin", "x64"), "roc_nightly-macos_x86_64-2026-10-06-c34079d.tar.gz");
  assert.equal(nightlyAsset(tag, "win32", "x64"), "roc_nightly-windows_x86_64-2026-10-06-c34079d.zip");
  assert.equal(nightlyAsset(tag, "freebsd", "x64"), null);
});

/** GitHub's release API and its download host, from one archive. */
async function fakeGithub(tag: string, archive: Buffer, digest: string) {
  const asset = nightlyAsset(tag)!;
  const server = http.createServer((req, res) => {
    const port = (server.address() as { port: number }).port;
    if (req.url === `/repos/roc-lang/nightlies/releases/tags/${tag}`) {
      res.setHeader("content-type", "application/json");
      res.end(
        JSON.stringify({
          assets: [{ name: asset, digest: `sha256:${digest}`, browser_download_url: `http://127.0.0.1:${port}/dl/${asset}` }],
        })
      );
    } else if (req.url === `/dl/${asset}`) {
      res.end(archive);
    } else {
      res.statusCode = 404;
      res.end("{}");
    }
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  return { base, close: () => server.close() };
}

/** A nightly archive laid out as upstream's: one folder holding `roc`. */
function nightlyArchive(tag: string): Buffer {
  const src = path.join(tmp, `archive-${crypto.randomUUID()}`);
  fakeRoc(path.join(src, `roc_nightly-${tag}`), `Roc compiler version ${tag}`);
  const out = path.join(tmp, `${crypto.randomUUID()}.tar.gz`);
  assert.equal(spawnSync("tar", ["-czf", out, "-C", src, "."]).status, 0);
  return fs.readFileSync(out);
}

test("install checks the digest, unpacks the nightly and records it", { skip: !unix || !nightlyAsset("nightly-x") }, async () => {
  const tag = "nightly-2026-01-01-abcdef0";
  const archive = nightlyArchive(tag);
  const sha = crypto.createHash("sha256").update(archive).digest("hex");
  const gh = await fakeGithub(tag, archive, sha);
  try {
    const env = { ROC_MCP_HOME: path.join(tmp, "install-ok") };
    const result = await installRoc(tag, env, { api: gh.base, downloads: gh.base });
    assert.equal(result.ok, true, result.message);
    assert.match(result.message, /sha256 checked/);
    const choice = findRoc([], env);
    assert.equal(choice.source, "roc use");
    assert.equal(spawnSync(choice.command, ["version"], { encoding: "utf-8" }).stdout.trim(), `Roc compiler version ${tag}`);
  } finally {
    gh.close();
  }
});

test("install refuses an archive whose digest differs, and records nothing", { skip: !unix || !nightlyAsset("nightly-x") }, async () => {
  const tag = "nightly-2026-01-02-abcdef1";
  const gh = await fakeGithub(tag, nightlyArchive(tag), "0".repeat(64));
  try {
    const env = { ROC_MCP_HOME: path.join(tmp, "install-digest") };
    const result = await installRoc(tag, env, { api: gh.base, downloads: gh.base });
    assert.equal(result.ok, false);
    assert.match(result.message, /the release says 0{64}\. Nothing was installed/);
    assert.equal(findRoc([], env).source, "PATH");
    assert.deepEqual(fs.readdirSync(path.join(env.ROC_MCP_HOME, "roc")), []);
  } finally {
    gh.close();
  }
});

test("install names a nightly that does not exist", { skip: !nightlyAsset("nightly-x") }, async () => {
  const gh = await fakeGithub("nightly-other", Buffer.from(""), "");
  try {
    const result = await installRoc("nightly-2099-01-01-0000000", { ROC_MCP_HOME: path.join(tmp, "install-404") }, {
      api: gh.base,
      downloads: gh.base,
    });
    assert.deepEqual(result, { ok: false, message: "roc-lang/nightlies has no release nightly-2099-01-01-0000000" });
  } finally {
    gh.close();
  }
});

/** One server, and a way to call its tools one at a time. */
function server(env: NodeJS.ProcessEnv) {
  const child = spawn(process.execPath, ["--import", TSX_LOADER, path.join(ROOT, "src", "index.ts")], {
    cwd: tmp,
    env,
    stdio: ["pipe", "pipe", "ignore"],
  });
  let buf = "";
  const waiting = new Map<number, (m: any) => void>();
  child.stdout.on("data", (d) => {
    buf += d;
    for (let i = buf.indexOf("\n"); i >= 0; i = buf.indexOf("\n")) {
      const m = JSON.parse(buf.slice(0, i));
      buf = buf.slice(i + 1);
      waiting.get(m.id)?.(m);
    }
  });
  let id = 0;
  const send = (method: string, params: unknown) =>
    new Promise<any>((resolve) => {
      const n = ++id;
      waiting.set(n, resolve);
      child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: n, method, params }) + "\n");
    });
  return { send, notify: (method: string) => child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method }) + "\n"), kill: () => child.kill() };
}

// The client fixes the server's PATH at startup. The next call finds a compiler
// that the agent installs mid-session through the record.
test("a running server uses a compiler recorded after it started", { skip: !unix }, async () => {
  const home = path.join(tmp, "live-home");
  const env: NodeJS.ProcessEnv = { ...process.env, ROC_MCP_HOME: home, PATH: path.dirname(process.execPath), CLAUDE_PROJECT_DIR: "" };
  delete env.ROC;
  const s = server(env);
  try {
    await s.send("initialize", { protocolVersion: LATEST_PROTOCOL_VERSION, capabilities: {}, clientInfo: { name: "t", version: "1" } });
    s.notify("notifications/initialized");
    const check = { name: "roc_check", arguments: { code: "x = 1\n", scope: "basic-cli" } };
    const before = (await s.send("tools/call", check)).result;
    assert.equal(before.isError, true);
    assert.match(before.content[0].text, /No Roc compiler: `roc` is not on the PATH/);
    assert.match(before.content[0].text, /roc install` in a shell/);

    assert.equal(useRoc(fakeRoc(path.join(tmp, "live-bin")), { ROC_MCP_HOME: home }).ok, true);
    const afterUse = (await s.send("tools/call", check)).result;
    assert.notEqual(afterUse.isError, true, afterUse.content[0].text);
    assert.match(afterUse.content[0].text, /`roc check` passed/);
  } finally {
    s.kill();
  }
});
