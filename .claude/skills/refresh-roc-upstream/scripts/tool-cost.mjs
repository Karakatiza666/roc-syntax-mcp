#!/usr/bin/env node
// Prints the token cost of one `tools/list` for a client, per tool and in total.
//
// The server must be cheap to keep loaded, so the tool descriptions have a token
// budget. Run this script before and after a refresh. A description that grew
// must justify its extra tokens.
//
// Usage: node .claude/skills/refresh-roc-upstream/scripts/tool-cost.mjs [repo-root]

import { spawn } from "node:child_process";
import * as path from "node:path";

const ROOT = path.resolve(process.argv[2] ?? process.cwd());

// The estimate used throughout this repo's tests: about 3.5 characters per token.
const tokens = (s) => Math.round(s.length / 3.5);

const child = spawn(process.execPath, ["--import", "tsx/esm", path.join(ROOT, "src", "index.ts")], {
  cwd: ROOT,
  stdio: ["pipe", "pipe", "inherit"],
});

let buf = "";
child.stdout.on("data", (chunk) => {
  buf += chunk;
  const lines = buf.split("\n");
  buf = lines.pop() ?? "";
  for (const line of lines) {
    if (!line.trim()) continue;
    const msg = JSON.parse(line);
    if (msg.id !== 1) continue;
    report(msg.result.tools);
    child.kill();
  }
});

function report(tools) {
  const rows = tools
    .map((t) => ({ name: t.name, tok: tokens(JSON.stringify(t)) }))
    .sort((a, b) => b.tok - a.tok);
  const total = tokens(JSON.stringify({ tools }));
  const width = Math.max(...rows.map((r) => r.name.length));
  for (const r of rows) console.log(`${r.name.padEnd(width)}  ${String(r.tok).padStart(5)}`);
  console.log(`${"".padEnd(width, "-")}  -----`);
  console.log(`${String(tools.length + " tools").padEnd(width)}  ${String(total).padStart(5)}`);
}

for (const req of [
  { jsonrpc: "2.0", id: 0, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "tool-cost", version: "1" } } },
  { jsonrpc: "2.0", method: "notifications/initialized" },
  { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} },
]) child.stdin.write(JSON.stringify(req) + "\n");
