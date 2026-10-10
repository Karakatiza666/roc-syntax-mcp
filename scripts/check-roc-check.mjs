#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Tests the roc_check tool end to end, with a real compiler.
//
// src/roc_check.test.ts tests the two transforms without a compiler.
// scripts/check-platform-examples.sh checks that the scaffold compiles. Neither
// tests how the server connects the parts:
// - detection supplies a scope that the caller did not pass,
// - the timeout follows the app header,
// - the reply shows the caller's own line numbers and not the errors of a package.
//
// Usage: ROC=/path/to/roc node scripts/check-roc-check.mjs

import { spawn, execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { nightlyBinary, nightlyFor, releaseNightlies } from "./nightlies.mjs";
import { load, nodeArgs } from "./tree.mjs";

const ROOT = path.join(import.meta.dirname, "..");
const ROC = process.env.ROC ?? "roc";
try {
  execFileSync(ROC, ["version"], { stdio: "ignore" });
} catch {
  console.error("roc not found. Set ROC=/path/to/roc");
  process.exit(2);
}
// The server calls `roc` by name, so the chosen binary has to be on its PATH.
const PATH_WITH_ROC = `${path.dirname(path.resolve(ROC))}${path.delimiter}${process.env.PATH}`;

const PLATFORM =
  "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst";
const HTTP =
  "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst";
const CLI_PLATFORM =
  "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst";
const GREGORIAN =
  "https://cdn.jasperwoudenberg.com/roc-gregorian-v1.0.0-rc.2/Ce3xuHN92F5oGRuzjUTmm65jULAEj8pvvrTBmZJzE1M4.tar.zst";

// The server runs one compiler, so a session that checks code on a platform
// runs the nightly of that platform's release, as check:platforms does. With
// no nightly of its own, the session runs ROC.
const RUNNING = execFileSync(ROC, ["version"], { encoding: "utf-8" });
function rocFor(release, dirs = []) {
  const nightly = nightlyFor(`"${release}"`, releaseNightlies(dirs));
  if (!nightly || RUNNING.includes(nightly)) return [];
  const binary = nightlyBinary(nightly);
  if (!binary) {
    console.error(`${release} needs ${nightly}. Unpack that nightly at the repo root`);
    process.exit(2);
  }
  return [`--roc=${binary}`];
}

// The prefix is not `roc-*`, because each roc run deletes the temporary
// `roc-*` directories, and it would delete this fixture tree too.
const work = fs.mkdtempSync(path.join(os.tmpdir(), "mcp-roc-acceptance-"));
process.on("exit", () => fs.rmSync(work, { recursive: true, force: true }));

function workspace(name, files) {
  const root = path.join(work, name);
  fs.mkdirSync(path.join(root, ".git"), { recursive: true });
  for (const [rel, content] of Object.entries(files)) {
    fs.writeFileSync(path.join(root, rel), content);
  }
  return root;
}

/** One tool call: `roc_check` unless the entry names another tool. */
function toolCall(entry, id) {
  const { tool = "roc_check", ...args } = entry;
  return { jsonrpc: "2.0", id, method: "tools/call", params: { name: tool, arguments: args } };
}

/** Run tool calls against a server launched in `cwd`, in order. */
function session(cwd, calls, serverArgs = []) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      process.execPath,
      [...nodeArgs("index"), ...serverArgs],
      { cwd, env: { ...process.env, PATH: PATH_WITH_ROC, CLAUDE_PROJECT_DIR: "" }, stdio: ["pipe", "pipe", "ignore"] }
    );
    const send = (m) => child.stdin.write(JSON.stringify(m) + "\n");
    const texts = [];
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error("session timed out"));
    }, 180_000);

    send({
      jsonrpc: "2.0", id: 0, method: "initialize",
      params: { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "acceptance", version: "1" } },
    });

    let buf = "";
    child.stdout.on("data", (chunk) => {
      buf += chunk;
      const lines = buf.split("\n");
      buf = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.trim()) continue;
        const msg = JSON.parse(line);
        if (msg.id === 0) {
          send({ jsonrpc: "2.0", method: "notifications/initialized" });
          send(toolCall(calls[0], 1));
          continue;
        }
        if (typeof msg.id === "number" && msg.id > 0) {
          if (msg.error) {
            clearTimeout(timer);
            child.kill();
            return reject(new Error(msg.error.message));
          }
          texts[msg.id - 1] = msg.result.content.map((c) => c.text).join("\n");
          // Send one call at a time. Two concurrent `roc check` runs return
          // each other's results. The problem is in the compiler, not in this
          // script.
          if (texts.length === calls.length) {
            clearTimeout(timer);
            child.kill();
            resolve(texts);
          } else {
            const next = texts.length;
            send(toolCall(calls[next], next + 1));
          }
        }
      }
    });
    child.on("error", reject);
  });
}

let pass = 0;
let fail = 0;
function check(name, ok, detail) {
  if (ok) {
    console.log(`ok    ${name}`);
    pass++;
  } else {
    console.log(`FAIL  ${name}`);
    if (detail) console.log(String(detail).replace(/^/gm, "      "));
    fail++;
  }
}

// With --plugin=<dir>, test the platform of a plugin through the real server:
// its sample, its scaffold and its detection. The fixtures below cannot test
// this, because they use the platforms of this repo. `plugin validate` runs
// this mode, and this mode skips the fixtures below.
const pluginArg = process.argv.slice(2).find((a) => a.startsWith("--plugin="));
if (pluginArg) {
  const dir = path.resolve(pluginArg.slice("--plugin=".length));
  // Use the server's loader, not a second manifest reader, because only the
  // loader derives the name and version of a platform from its release.
  const S = await load("scopes");
  const loaded = S.fromManifest(dir, JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8")));
  const platforms = loaded.defs.filter((d) => d.version && d.sample && d.scaffold);
  if (platforms.length === 0) {
    console.log("skip  a plugin with no platform, scaffold and sample has no round trip to make");
    process.exit(0);
  }
  for (const def of platforms) {
    // Detection reads the release URL and does not download it. So for a GitHub
    // release, the tarball name here can be any name, and the scaffold has the
    // real one. Detection identifies a bundle on any other host by its hash, so
    // that pin uses the exact URL.
    const release = def.modules[0].release;
    const pin = S.isHashVersion(release)
      ? release
      : `https://github.com/${S.pinFromUrl(release).id}/releases/download/${def.version}/detected.tar.zst`;
    const root = workspace(`plugin-${def.name}`, { "main.roc": `app [main!] { pf: platform "${pin}" }\n` });
    const sample = fs.readFileSync(def.sample, "utf-8");
    // The second call sends a fragment that declares nothing. The scaffold then
    // supplies every `@default`, and the reply must name the platform that wraps
    // the code. The sample cannot test this. If the sample declares what the
    // scaffold supplies, the server wraps it without a message.
    const roc = rocFor(release, [dir]);
    const [reply, bare] = await session(root, [{ code: sample }, { code: "probe = 1\n" }], [`--plugin=${dir}`, ...roc]);
    const wrapped = new RegExp(`Wrapped in the ${def.name} ${def.version.replace(/\./g, "\\.")} app`);
    check(`the ${def.name} sample round-trips through roc_check`, /`roc check` passed\./.test(reply), reply);
    check(`detection wraps bare code in ${def.name}'s own app`, wrapped.test(bare), bare);

    // An installed platform is available, but the code of the caller is not
    // always for that platform. The wrap decides if the server reports the code
    // as compiling, so only the app header or the caller's `scope` selects the
    // platform.
    const [unasked] = await session(
      workspace(`plugin-${def.name}-no-header`, {}),
      [{ code: "probe = 1\n" }],
      [`--plugin=${dir}`, ...roc]
    );
    check(`an installed ${def.name} does not wrap code nobody scoped`, !wrapped.test(unasked), unasked);
  }

  console.log(`\npass=${pass} fail=${fail}`);
  process.exit(fail === 0 ? 0 : 1);
}

const CLEAN = `respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |_request, _context| Ok(Server.respond(Response.from_status(200)))
`;
const TYPO = `respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, _context|
	match request.methodd() {
		_ => Ok(Server.respond(Response.from_status(405)))
	}
`;
const WITH_GREGORIAN = `app [Context, program] {
	pf: platform "${PLATFORM}",
	http: "${HTTP}",
	gregorian: "${GREGORIAN}",
}

import pf.Server
import http.Response
import gregorian.Time

Context : {}
program = { init!, respond!, shutdown! }
init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || Ok({ config: Server.default_config, context: {} })
shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})
respond! = |request, _context| Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(request.methodd()))))
`;

const app = `app [Context, program] {\n\tpf: platform "${PLATFORM}",\n}\n\nimport pf.Server\n\nContext : {}\n`;

// A workspace that pins the platform. Nothing below passes `scope`.
const detected = workspace("detected", { "main.roc": app });
const [clean, typo, gregorian] = await session(
  detected,
  [{ code: CLEAN }, { code: TYPO }, { code: WITH_GREGORIAN }],
  rocFor(PLATFORM)
);

check("detection scaffolds a bare handler nobody scoped", /Wrapped in the basic-webserver 0\.17\.0 app/.test(clean), clean);
check("a scaffolded handler that is correct passes", /`roc check` passed\./.test(clean), clean);
check("errors report the caller's own line", /main\.roc:3:/.test(typo), typo);
check("the temporary path never reaches the caller", !/roc-check-[A-Za-z0-9]+\/main\.roc/.test(typo), typo);
check("the caller's error is stated first", /`roc check` failed: 1 error\./.test(gregorian), gregorian);
check("a broken package is counted, not quoted", /gregorian\/Date\.roc: 14/.test(gregorian) && !/This map method/.test(gregorian), gregorian);

// With two platforms, detection must select the correct scaffold. Only
// basic-cli has `Utc`, so this code compiles only under the basic-cli app
// header. It declares no `main!`, so the scaffold supplies one, and the reply
// names the platform.
const CLI_CLEAN = `uptime! : () => Try(U128, _)
uptime! = || Ok(Utc.now!())
`;
const cliApp = `app [main!] { pf: platform "${CLI_PLATFORM}" }\n\nimport pf.Stdout\n`;
const cliWorkspace = workspace("detected-cli", { "main.roc": cliApp });
const [cliClean] = await session(cliWorkspace, [{ code: CLI_CLEAN }], rocFor(CLI_PLATFORM));
check("detection scaffolds against the platform the workspace pins", /Wrapped in the basic-cli 0\.25\.0 app/.test(cliClean), cliClean);
check("a scaffolded basic-cli program that is correct passes", /`roc check` passed\./.test(cliClean), cliClean);

// No app header here, so only the argument can name the platform.
const plain = workspace("plain", { "lib.roc": "module [x]\n\nx = 1\n" });
const [scoped] = await session(plain, [{ code: CLEAN, scope: "basic-webserver" }], rocFor(PLATFORM));
const [cliScoped, unscoped] = await session(
  plain,
  [{ code: CLI_CLEAN, scope: "basic-cli" }, { code: CLEAN }],
  rocFor(CLI_PLATFORM)
);
check("an explicit scope scaffolds where detection found nothing", /`roc check` passed\./.test(scoped), scoped);
check("the explicit scope selects between the platforms", /Wrapped in the basic-cli 0\.25\.0 app/.test(cliScoped) && /`roc check` passed\./.test(cliScoped), cliScoped);
check("without a scope or a detection, bare code is not wrapped", /failed/.test(unscoped) && !/Wrapped in the/.test(unscoped), unscoped);

// `roc_fmt` reads a path as `roc_check` does. A unit test cannot run a real
// `roc fmt` on the content of the file and check that the file on disk stays
// as the caller wrote it. These checks do.
const SCRUFFY = "module [x]\n\nx    =    1\n";
const fmtWorkspace = workspace("fmt", { "lib.roc": SCRUFFY });
const fmtPath = path.join(fmtWorkspace, "lib.roc");
const [formatted] = await session(fmtWorkspace, [{ tool: "roc_fmt", path: fmtPath }]);
check("roc_fmt formats the file a path names", /x = 1/.test(formatted), formatted);
check("roc_fmt leaves that file as it found it", fs.readFileSync(fmtPath, "utf-8") === SCRUFFY, fs.readFileSync(fmtPath, "utf-8"));
check("roc_fmt says the file on disk was not written", /unchanged on disk/.test(formatted), formatted);

console.log(`\npass=${pass} fail=${fail}`);
process.exit(fail === 0 ? 0 : 1);
