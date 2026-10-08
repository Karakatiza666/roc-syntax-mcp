#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Agentic evaluation of the MCP tools, as Phase 7 of
// docs/plans/basic-webserver-scope.md describes.
//
// Unit tests show that the server answers correctly. They cannot measure what
// the design depends on:
// - whether the model sets `scope`,
// - whether a footer changes the next action of the model,
// - whether the Roc code that the model writes compiles.
// These need a real model that calls the real tools. So this script runs
// `claude -p` on a fixture basic-webserver project and reads the transcript.
//
// The script reads every metric from the transcript or from `roc check`, never
// from the text of the model. Only task completion is an estimate. The script
// infers it from whether the file changed and compiles.
//
// An arm is one server design under test, and this script does not switch arms.
// To compare two designs, run the script, change the server, and run it again
// with a different `--arm` label. Thus the server has no code path that exists
// only for the eval.
//
// Usage:
//   ROC=/path/to/roc node scripts/eval-agentic.mjs --arm=baseline
//   node scripts/eval-agentic.mjs --arm=no-output-schema --tasks=todos-sqlite
//   node scripts/eval-agentic.mjs --report            # re-render from saved runs

import { spawn, execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const ROOT = path.join(import.meta.dirname, "..");
const OUT_DIR = path.join(ROOT, "docs", "evals");
const RUNS = path.join(OUT_DIR, "runs.jsonl");

// -----------------------------------------------------------------------------
// Tasks
// -----------------------------------------------------------------------------

// Each task edits the fixture app in place, so `roc check` on the result tests
// the whole app and not an isolated snippet.
//
// `wants` names the scope that a careful caller would select. The report shows
// it but does not enforce it. A model that answers a task from the default
// working set is not wrong. That result is evidence that the `scope` parameter
// does not justify its token cost.
const TASKS = [
  {
    name: "todos-sqlite",
    wants: "basic-webserver",
    prompt:
      "In main.roc, add a POST /todos endpoint that inserts the request body as a " +
      "todo row into SQLite, and a GET /todos that returns the rows as JSON. Open " +
      "the database in init! and keep the handle in Context. Use the roc-syntax MCP " +
      "server for anything you are unsure of. Reply with just DONE.",
  },
  {
    name: "sse-stream",
    wants: "basic-webserver",
    prompt:
      "In main.roc, add a GET /events endpoint that streams server-sent events, " +
      "one event per second, ten events then close. Use the roc-syntax MCP server " +
      "for anything you are unsure of. Reply with just DONE.",
  },
  {
    name: "form-post",
    wants: "basic-webserver",
    prompt:
      "In main.roc, add a GET /signup that serves an HTML form and a POST /signup " +
      "that parses the urlencoded body and replies with an HTML page naming the " +
      "submitted user. Use the roc-syntax MCP server for anything you are unsure " +
      "of. Reply with just DONE.",
  },
  {
    name: "builtin-only",
    wants: "builtin",
    // This task needs no platform API. A model that reads the platform corpus
    // here spends tokens that the task does not need. `scope` exists to prevent
    // that cost.
    prompt:
      "In main.roc, add a top-level function `slugify : Str -> Str` that lowercases " +
      "its argument, replaces every run of non-alphanumeric characters with a single " +
      "dash, and trims leading and trailing dashes. Call it from the GET / handler so " +
      "it responds with the slug of the greeting. Use the roc-syntax MCP server for " +
      "anything you are unsure of. Reply with just DONE.",
  },
];

const MCP_TOOLS = [
  "roc_overview", "get_roc_syntax", "list_roc_index", "search_roc_syntax",
  "search_symbols", "get_builtin_module", "roc_check", "roc_fmt",
  "get_roc_langref", "search", "search_project_signatures",
];
const PREFIX = "mcp__roc-syntax__";
const ALLOWED = [...MCP_TOOLS.map((t) => PREFIX + t), "Read", "Write", "Edit"];
// Bash would let the model run `roc check` itself, and the web tools would let
// it read the upstream docs. Either one confounds every metric here.
const DISALLOWED = ["Bash", "WebSearch", "WebFetch", "Task", "Agent"];

const MAX_TURNS = 40;
const RUN_TIMEOUT_MS = 15 * 60 * 1000;

// -----------------------------------------------------------------------------
// Transcript analysis
// -----------------------------------------------------------------------------

/** The scopes a scope footer offers to retry with. */
function footerOffers(text) {
  const m = /Retry with scope=|host-boundary items hidden/.test(text);
  if (!m) return null;
  const named = [...text.matchAll(/\b(language|builtin|basic-webserver|basic-cli)\s*:\s*\d+/g)].map((x) => x[1]);
  return { hostTier: /host-boundary items hidden/.test(text), offers: named };
}

function resultText(content) {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) return content.map((c) => c.text ?? JSON.stringify(c)).join("\n");
  return JSON.stringify(content ?? "");
}

function analyze(lines) {
  const uses = new Map(); // tool_use_id -> {name, input, order}
  const seq = []; // in call order: {name, input, resultText}
  let result = null;
  let model = null;

  for (const line of lines) {
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }
    if (msg.type === "system" && msg.subtype === "init") model = msg.model ?? model;
    if (msg.type === "result") result = msg;
    for (const c of msg.message?.content ?? []) {
      if (c.type === "tool_use") {
        const entry = { name: c.name, input: c.input ?? {}, result: null };
        uses.set(c.id, entry);
        seq.push(entry);
      }
      if (c.type === "tool_result") {
        const entry = uses.get(c.tool_use_id);
        if (entry) entry.result = resultText(c.content);
      }
    }
  }

  const rocCalls = seq.filter((s) => s.name.startsWith(PREFIX));
  const scoped = rocCalls.filter((s) => typeof s.input.scope === "string");

  // Count a footer as followed only if the next roc-syntax call selects a scope
  // that the footer named. The script does not attribute a later call to it.
  let footersSeen = 0;
  let footerRetries = 0;
  let hostFootersSeen = 0;
  let hostFollowUps = 0;
  for (let i = 0; i < rocCalls.length; i++) {
    const f = rocCalls[i].result ? footerOffers(rocCalls[i].result) : null;
    if (!f) continue;
    const next = rocCalls[i + 1];
    if (f.offers.length > 0) {
      footersSeen++;
      if (next && f.offers.includes(next.input.scope)) footerRetries++;
    }
    if (f.hostTier) {
      hostFootersSeen++;
      const addressed = next && ["get_builtin_module", "search_symbols"].includes(next.name.slice(PREFIX.length));
      if (addressed) hostFollowUps++;
    }
  }

  const usage = result?.usage ?? {};
  return {
    model,
    ok: result ? !result.is_error : false,
    turns: result?.num_turns ?? null,
    durationMs: result?.duration_ms ?? null,
    costUsd: result?.total_cost_usd ?? null,
    tokens: {
      input: usage.input_tokens ?? 0,
      output: usage.output_tokens ?? 0,
      cacheCreate: usage.cache_creation_input_tokens ?? 0,
      cacheRead: usage.cache_read_input_tokens ?? 0,
    },
    calls: seq.map((s) => s.name.startsWith(PREFIX) ? s.name.slice(PREFIX.length) : s.name),
    rocCalls: rocCalls.map((s) => ({
      tool: s.name.slice(PREFIX.length),
      scope: s.input.scope ?? null,
      resultChars: s.result?.length ?? 0,
    })),
    firstRocCall: rocCalls[0] ? rocCalls[0].name.slice(PREFIX.length) : null,
    usedToolSearch: seq.some((s) => s.name === "ToolSearch"),
    rocCallCount: rocCalls.length,
    scopedCount: scoped.length,
    scopeValues: [...new Set(scoped.map((s) => s.input.scope))].sort(),
    rocCheckCalls: rocCalls.filter((s) => s.name.endsWith("roc_check")).length,
    footersSeen,
    footerRetries,
    hostFootersSeen,
    hostFollowUps,
    // The total size of the tool results, the main metric of the server design.
    resultChars: rocCalls.reduce((n, s) => n + (s.result?.length ?? 0), 0),
  };
}

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

function run(task, opts) {
  const dir = fs.mkdtempSync(path.join(opts.work, `${task.name}-`));
  fs.mkdirSync(path.join(dir, ".git"), { recursive: true });
  const before = fs.readFileSync(path.join(ROOT, "eval", "fixture", "main.roc"), "utf8");
  fs.writeFileSync(path.join(dir, "main.roc"), before);

  const args = [
    "-p", task.prompt,
    "--mcp-config", opts.mcpConfig,
    "--allowedTools", ...ALLOWED,
    "--disallowedTools", ...DISALLOWED,
    "--max-turns", String(MAX_TURNS),
    "--output-format", "stream-json",
    "--verbose",
  ];
  if (opts.model) args.push("--model", opts.model);

  const started = Date.now();
  const proc = spawn("claude", args, {
    cwd: dir,
    env: { ...process.env, PATH: opts.path, CLAUDE_PROJECT_DIR: "" },
    stdio: ["ignore", "pipe", "pipe"],
    timeout: RUN_TIMEOUT_MS,
  });
  let out = "";
  let err = "";
  proc.stdout.on("data", (c) => (out += c));
  proc.stderr.on("data", (c) => (err += c));

  return new Promise((resolve) => {
    proc.on("close", (code) => {
      const metrics = analyze(out.split("\n").filter((l) => l.trim()));
      const after = fs.readFileSync(path.join(dir, "main.roc"), "utf8");
      const check = rocCheck(path.join(dir, "main.roc"), opts.roc);
      resolve({
        arm: opts.arm,
        task: task.name,
        toolListTokens: opts.toolListTokens,
        wants: task.wants,
        exitCode: code,
        wallMs: Date.now() - started,
        edited: after !== before,
        grew: after.length - before.length,
        check,
        ...metrics,
        stderrTail: err.trim().split("\n").slice(-3).join("\n"),
        transcript: opts.keep ? out : undefined,
      });
    });
  });
}

/**
 * The token cost of one `tools/list`. The script records it for each arm, so a
 * saved run keeps the cost of the tools at the time of the run. It uses the
 * estimate of 3.5 characters per token, as the rest of the repo does.
 */
function toolListTokens() {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, ["--import", "tsx/esm", path.join(ROOT, "src", "index.ts")], {
      cwd: ROOT,
      stdio: ["pipe", "pipe", "ignore"],
    });
    let buf = "";
    child.stdout.on("data", (c) => {
      buf += c;
      const lines = buf.split("\n");
      buf = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.trim()) continue;
        const m = JSON.parse(line);
        if (m.id !== 1) continue;
        child.kill();
        resolve(Math.round(JSON.stringify({ tools: m.result.tools }).length / 3.5));
      }
    });
    for (const r of [
      { jsonrpc: "2.0", id: 0, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "eval", version: "1" } } },
      { jsonrpc: "2.0", method: "notifications/initialized" },
      { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} },
    ]) child.stdin.write(JSON.stringify(r) + "\n");
  });
}

/** Checks whether the file that the model wrote compiles. */
function rocCheck(file, roc) {
  // Copy the file first, because `roc check` deletes every /tmp/roc-* directory
  // that it finds. The fixture tree must stay, or the comparison in run() means
  // nothing.
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "mcp-roc-eval-"));
  const target = path.join(scratch, "main.roc");
  fs.copyFileSync(file, target);
  try {
    execFileSync(roc, ["check", "--no-color", target], { stdio: "pipe", timeout: 180_000 });
    return { pass: true, summary: "no errors" };
  } catch (e) {
    const text = `${e.stderr ?? ""}${e.stdout ?? ""}`;
    const tally = text.match(/──\s+(\d+ errors? and \d+ warnings?)/);
    return { pass: false, summary: tally ? tally[1] : (e.code === "ETIMEDOUT" ? "timed out" : "failed to run") };
  } finally {
    fs.rmSync(scratch, { recursive: true, force: true });
  }
}

// -----------------------------------------------------------------------------
// Reporting
// -----------------------------------------------------------------------------

const pct = (n, d) => (d === 0 ? "n/a" : `${Math.round((n / d) * 100)}%`);
const sumOf = (rs, key) => rs.reduce((n, r) => n + (r[key] ?? 0), 0);
const k = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n));

function report(runs) {
  const arms = [...new Set(runs.map((r) => r.arm))];
  const out = [];
  out.push("# Agentic evaluation");
  out.push("");
  out.push("Produced by `node scripts/eval-agentic.mjs`. Every number is read from the");
  out.push("transcript or from `roc check`, never from the model's prose.");
  out.push("");

  out.push("## Per arm");
  out.push("");
  out.push("A footer column reading `none shown` means the model never called a tool that");
  out.push("emits one, not that it ignored one. Scope footers appear on `search`,");
  out.push("`search_symbols` type queries, the `list_roc_index` kinds, and a `search_roc_syntax`");
  out.push("miss. The host-tier footer appears on `search` and `get_builtin_module`.");
  out.push("");
  out.push("| Arm | Runs | `tools/list` | Compiles | Set `scope` | Called `roc_check` | Footer retries | Host footers | Tool output | Output tokens | Cost |");
  out.push("|---|---|---|---|---|---|---|---|---|---|---|");
  for (const arm of arms) {
    const rs = runs.filter((r) => r.arm === arm);
    const calls = rs.reduce((n, r) => n + r.rocCallCount, 0);
    const scoped = rs.reduce((n, r) => n + r.scopedCount, 0);
    const footers = rs.reduce((n, r) => n + r.footersSeen, 0);
    const retries = rs.reduce((n, r) => n + r.footerRetries, 0);
    out.push(
      `| ${arm} | ${rs.length} | ${rs[0].toolListTokens ?? "?"} tok | ${rs.filter((r) => r.check.pass).length}/${rs.length}` +
        ` | ${pct(scoped, calls)} (${scoped}/${calls}) | ${rs.filter((r) => r.rocCheckCalls > 0).length}/${rs.length}` +
        ` | ${footers === 0 ? "none shown" : `${pct(retries, footers)} (${retries}/${footers})`}` +
        ` | ${(() => { const h = sumOf(rs, "hostFootersSeen"); return h === 0 ? "none shown" : `${sumOf(rs, "hostFollowUps")}/${h} followed`; })()}` +
        ` | ${k(Math.round(rs.reduce((n, r) => n + r.resultChars, 0) / rs.length))} ch` +
        ` | ${k(Math.round(rs.reduce((n, r) => n + r.tokens.output, 0) / rs.length))}` +
        ` | $${(rs.reduce((n, r) => n + (r.costUsd ?? 0), 0) / rs.length).toFixed(2)} |`
    );
  }
  out.push("");

  out.push("## Per run");
  out.push("");
  out.push("| Arm | Task | Wants | Scopes used | First call | Calls | `roc check` | Tool output | Cost |");
  out.push("|---|---|---|---|---|---|---|---|---|");
  for (const r of runs) {
    out.push(
      `| ${r.arm} | ${r.task} | ${r.wants} | ${r.scopeValues.length ? r.scopeValues.join(", ") : "none"}` +
        ` | ${r.firstRocCall ?? "none"} | ${r.rocCallCount} | ${r.check.pass ? "pass" : r.check.summary}` +
        ` | ${k(r.resultChars)} ch | $${(r.costUsd ?? 0).toFixed(2)} |`
    );
  }
  out.push("");

  out.push("## Tool call order");
  out.push("");
  for (const r of runs) {
    out.push(`- \`${r.arm}/${r.task}\`: ${r.rocCalls.map((c) => c.tool + (c.scope ? `(${c.scope})` : "")).join(" -> ") || "no tool calls"}`);
  }
  out.push("");
  return out.join("\n");
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

const flags = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const m = a.match(/^--([\w-]+)(?:=(.*))?$/);
    return m ? [m[1], m[2] ?? "true"] : [a, "true"];
  })
);

const loadRuns = () =>
  fs.existsSync(RUNS)
    ? fs.readFileSync(RUNS, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l))
    : [];

if (flags.report) {
  fs.writeFileSync(path.join(OUT_DIR, "agentic.md"), report(loadRuns()));
  console.log(`wrote ${path.relative(ROOT, path.join(OUT_DIR, "agentic.md"))} from ${loadRuns().length} runs`);
  process.exit(0);
}

if (!flags.arm) {
  console.error("--arm=<label> is required. It names the server design under test.");
  process.exit(2);
}

const roc = process.env.ROC ?? "roc";
try {
  execFileSync(roc, ["version"], { stdio: "ignore" });
} catch {
  console.error("roc not found. Set ROC=/path/to/roc");
  process.exit(2);
}
try {
  execFileSync("claude", ["--version"], { stdio: "ignore" });
} catch {
  console.error("claude CLI not found. Skipping");
  process.exit(0);
}

const work = fs.mkdtempSync(path.join(os.tmpdir(), "mcp-roc-eval-work-"));
process.on("exit", () => fs.rmSync(work, { recursive: true, force: true }));

const loader = execFileSync(process.execPath, ["-e", "process.stdout.write(import.meta.resolve('tsx/esm'))"], {
  cwd: ROOT,
  encoding: "utf8",
});
const mcpConfig = path.join(work, "mcp.json");
fs.writeFileSync(
  mcpConfig,
  JSON.stringify({
    mcpServers: {
      "roc-syntax": { command: process.execPath, args: ["--import", loader, path.join(ROOT, "src", "index.ts")] },
    },
  })
);

const opts = {
  arm: flags.arm,
  toolListTokens: await toolListTokens(),
  work,
  mcpConfig,
  roc,
  model: flags.model,
  keep: flags.keep === "true",
  // The server runs `roc` by name, and so does the check in this script.
  path: `${path.dirname(path.resolve(roc))}${path.delimiter}${process.env.PATH}`,
};

const wanted = flags.tasks ? flags.tasks.split(",") : TASKS.map((t) => t.name);
const repeat = Number(flags.repeat ?? 1);
const queue = [];
for (let i = 0; i < repeat; i++) {
  for (const t of TASKS.filter((t) => wanted.includes(t.name))) queue.push(t);
}
if (queue.length === 0) {
  console.error(`no task matched --tasks=${flags.tasks}`);
  process.exit(2);
}

fs.mkdirSync(OUT_DIR, { recursive: true });
console.log(`arm=${opts.arm} tasks=${queue.length} tools/list=${opts.toolListTokens} tokens`);
// Run the tasks one at a time. Concurrent runs share one Anthropic rate limit
// and one roc package cache, so the cost and the timing would mean nothing.
for (const task of queue) {
  const r = await run(task, opts);
  fs.appendFileSync(RUNS, JSON.stringify(r) + "\n");
  console.log(
    `  ${r.task.padEnd(14)} calls=${String(r.rocCallCount).padStart(2)} ` +
      `scoped=${r.scopedCount} scopes=${r.scopeValues.join("+") || "-"} ` +
      `check=${r.check.pass ? "pass" : r.check.summary} ` +
      `out=${k(r.resultChars)}ch cost=$${(r.costUsd ?? 0).toFixed(2)}`
  );
}

fs.writeFileSync(path.join(OUT_DIR, "agentic.md"), report(loadRuns()));
console.log(`wrote ${path.relative(ROOT, path.join(OUT_DIR, "agentic.md"))}`);
