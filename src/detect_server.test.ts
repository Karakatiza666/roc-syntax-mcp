// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Detection end to end, over a real stdio session.
//
// The assertions read what the server recorded about its own detection, never a
// model's reply, so the result is deterministic. `list_roc_index(kind: "scopes")`
// reports that record, which is why it is the tool under test here.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { pathToFileURL } from "node:url";
import { LATEST_PROTOCOL_VERSION } from "@modelcontextprotocol/server";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const ROOT = path.join(import.meta.dirname, "..");
// The server is launched outside this project, where a bare `tsx/esm` does not
// resolve, so the loader is passed as an absolute URL.
const TSX_LOADER = import.meta.resolve("tsx/esm");
const url = (v: string) =>
  `https://github.com/roc-lang/basic-webserver/releases/download/${v}/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst`;

const appFile = (v: string) => `app [Context, program] {
\tpf: platform "${url(v)}",
}

import pf.Server

Context : {}
`;

/** An app that pins a package next to its platform, as every example does. */
const appWithPin = (pin: string) => `app [Context, program] {
\tpf: platform "${url("0.17.0")}",
\t${pin}
}

import pf.Server

Context : {}
`;

const cliUrl = (v: string) =>
  `https://github.com/roc-lang/basic-cli/releases/download/${v}/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst`;

const cliAppFile = (v: string) => `app [main!] { pf: platform "${cliUrl(v)}" }

import pf.Stdout
`;

let tmp: string;
before(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roc-detect-server-"));
});
after(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

function workspace(name: string, files: Record<string, string>): string {
  const root = path.join(tmp, name);
  fs.mkdirSync(path.join(root, ".git"), { recursive: true });
  for (const [rel, content] of Object.entries(files)) {
    const file = path.join(root, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content);
  }
  return root;
}

interface SessionOptions {
  /** Working directory the server is launched in. */
  cwd: string;
  /** Directory to answer `roots/list` with. Omitted means no roots capability. */
  roots?: string;
  /** Added to the server's environment. */
  env?: Record<string, string>;
  /** Added to the server's command line. */
  args?: string[];
}

/**
 * Run tool calls against a server launched in `cwd`, answering the server's own
 * `roots/list` request when the session declares the capability. The helper in
 * resources.test.ts does not reply to a request from the server, and that
 * request is the mechanism under test.
 */
function session(
  opts: SessionOptions,
  calls: { name: string; args?: unknown; delayMs?: number; notifyFirst?: string }[]
): Promise<string[]> {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["--import", TSX_LOADER, path.join(ROOT, "src", "index.ts"), ...(opts.args ?? [])], {
      cwd: opts.cwd,
      // Inherited CLAUDE_PROJECT_DIR would override the launch directory.
      env: { ...process.env, CLAUDE_PROJECT_DIR: "", ...opts.env },
      stdio: ["pipe", "pipe", "ignore"],
    });

    const texts: string[] = [];
    const send = (msg: unknown) => child.stdin.write(JSON.stringify(msg) + "\n");
    const fail = (err: Error) => {
      child.kill();
      reject(err);
    };
    const timer = setTimeout(() => fail(new Error("session timed out")), 30_000);

    send({
      jsonrpc: "2.0",
      id: 0,
      method: "initialize",
      params: {
        protocolVersion: LATEST_PROTOCOL_VERSION,
        capabilities: opts.roots ? { roots: { listChanged: true } } : {},
        clientInfo: { name: "detect-test", version: "1.0.0" },
      },
    });

    let buf = "";
    child.stdout.on("data", (chunk) => {
      buf += chunk;
      const lines = buf.split("\n");
      buf = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.trim()) continue;
        const msg = JSON.parse(line);

        // The server asks the client where the workspace is.
        if (msg.method === "roots/list") {
          send({
            jsonrpc: "2.0",
            id: msg.id,
            result: { roots: [{ uri: pathToFileURL(opts.roots!).href, name: "workspace" }] },
          });
          continue;
        }

        if (msg.id === 0) {
          send({ jsonrpc: "2.0", method: "notifications/initialized" });
          calls.forEach((c, i) =>
            setTimeout(() => {
              if (c.notifyFirst) send({ jsonrpc: "2.0", method: c.notifyFirst });
              send({
                jsonrpc: "2.0",
                id: i + 1,
                method: "tools/call",
                params: { name: c.name, arguments: c.args ?? {} },
              });
            }, c.delayMs ?? 0)
          );
          continue;
        }

        if (typeof msg.id === "number" && msg.id > 0) {
          if (msg.error) return fail(new Error(`${calls[msg.id - 1].name}: ${msg.error.message}`));
          texts[msg.id - 1] = msg.result.content.map((c: any) => c.text).join("\n");
          if (texts.filter((t) => t !== undefined).length === calls.length) {
            clearTimeout(timer);
            child.kill();
            resolve(texts);
          }
        }
      }
    });

    child.on("error", fail);
  });
}

const scopes = { name: "list_roc_index", args: { kind: "scopes" } };

// -----------------------------------------------------------------------------

test("roots/list names the workspace, and the pin in it is detected", async () => {
  const root = workspace("via-roots", { "main.roc": appFile("0.15.0") });
  // Launched somewhere unrelated, so only the roots answer can find this app.
  const [text] = await session({ cwd: ROOT, roots: root }, [scopes]);
  assert.match(text, /Detected basic-webserver 0\.15\.0 from main\.roc, bundled 0\.17\.0\./);
  assert.match(text, /Omitting `scope` reads language \+ builtin \+ basic-webserver\./);
});

// The Claude Code desktop app sends no roots capability, and cwd is the launch
// directory. Detection must work from the environment only.
test("without a roots capability, detection falls back to the launch directory", async () => {
  const root = workspace("via-cwd", { "server.roc": appFile("0.17.0") });
  const [text] = await session({ cwd: root }, [scopes]);
  assert.match(text, /Detected basic-webserver 0\.17\.0 from server\.roc/);
});

// For a client with neither roots nor CLAUDE_PROJECT_DIR, whose config can say
// `--workspace=${workspaceFolder}`. The operator's flag has priority over the client's roots.
test("--workspace= names the workspace over roots and the launch directory", async () => {
  const root = workspace("via-flag", { "main.roc": appFile("0.15.0") });
  const other = workspace("via-flag-roots", { "main.roc": appFile("0.17.0") });
  const [text] = await session({ cwd: ROOT, roots: other, args: [`--workspace=${root}`] }, [scopes]);
  assert.match(text, /Detected basic-webserver 0\.15\.0 from main\.roc/);
});

test("a --workspace= that is not a folder falls back to the launch directory", async () => {
  const root = workspace("via-flag-missing", { "main.roc": appFile("0.17.0") });
  const [text] = await session({ cwd: root, args: ["--workspace=${workspaceFolder}"] }, [scopes]);
  assert.match(text, /Detected basic-webserver 0\.17\.0 from main\.roc/);
});

// Launching from `src/` reports `src/` as both cwd and root.
test("an app at the repo root is found when the server starts in a subdirectory", async () => {
  const root = workspace("via-walkup", {
    "main.roc": appFile("0.17.0"),
    "src/helper.roc": "module [x]\n\nx = 1\n",
  });
  const [text] = await session({ cwd: path.join(root, "src") }, [scopes]);
  assert.match(text, /Detected basic-webserver 0\.17\.0/);
});

test("a workspace with no app header keeps the default working set", async () => {
  const root = workspace("no-app", { "lib.roc": "module [x]\n\nx = 1\n" });
  const [text] = await session({ cwd: root }, [scopes]);
  assert.match(text, /No platform detected/);
  assert.match(text, /Omitting `scope` reads language \+ builtin\./);
});

test("get_roc_syntax points at the platform page without folding it in", async () => {
  const root = workspace("overview", { "main.roc": appFile("0.15.0") });
  const [text] = await session({ cwd: root }, [{ name: "get_roc_syntax" }]);
  assert.match(text, /Platform detected: basic-webserver 0\.17\.0 \(from main\.roc, pins 0\.15\.0\)/);
  // The platform page must not be in the default answer. The scope parameter
  // exists to prevent that copy.
  assert.ok(!text.includes("basic-webserver in one page"), "the platform page was folded in");
});

// The note is worth its tokens only once. A repeat on every scoped call would add
// cost to each call on the corpus that the workspace uses.
test("the mismatch note fires on the first scoped response and not the second", async () => {
  const root = workspace("warn-once", { "main.roc": appFile("0.15.0") });
  const call = { name: "get_roc_syntax", args: { topic: "webserver_handler", scope: "basic-webserver" } };
  const [first, second] = await session({ cwd: root }, [call, call]);
  assert.match(first, /pins basic-webserver 0\.15\.0, this server bundles 0\.17\.0/);
  assert.ok(!/this server bundles/.test(second), "the note repeated");
});

// A call that does not read the platform corpus must not pay for a note about it.
test("a builtin-only call carries no platform mismatch note", async () => {
  const root = workspace("builtin-only", { "main.roc": appFile("0.15.0") });
  const [text] = await session({ cwd: root }, [
    { name: "search_symbols", args: { query: ["concat"], scope: "builtin" } },
  ]);
  assert.ok(!/this server bundles/.test(text), "the note fired on a builtin-only call");
});

// -----------------------------------------------------------------------------
// Platform content reaches the client
// -----------------------------------------------------------------------------

// Every platform topic is a complete app that `npm run check:platforms` compiles.
// Without this test, a topic that fails to load here would pass every other check.
test("each platform topic loads from beside its platform, not corpus/language/topics", async () => {
  const names = ["webserver_handler", "webserver_sqlite", "webserver_sse",
                 "webserver_html", "webserver_forms", "webserver_static"];
  const texts = await session(
    { cwd: ROOT },
    names.map((n) => ({ name: "get_roc_syntax", args: { topic: n, scope: "basic-webserver" } }))
  );
  names.forEach((n, i) => {
    assert.match(texts[i], new RegExp(`^## ${n}\\n`), `${n} did not resolve`);
    assert.match(texts[i], /app \[Context, program\]/, `${n} returned no program`);
  });
});

test("each basic-cli topic loads from beside its platform", async () => {
  const names = ["cli_app", "cli_files", "cli_command", "cli_http", "cli_sqlite",
                 "cli_terminal", "cli_net"];
  const texts = await session(
    { cwd: ROOT },
    names.map((n) => ({ name: "get_roc_syntax", args: { topic: n, scope: "basic-cli" } }))
  );
  names.forEach((n, i) => {
    assert.match(texts[i], new RegExp(`^## ${n}\\n`), `${n} did not resolve`);
    assert.match(texts[i], /app \[main!\]/, `${n} returned no program`);
  });
});

// -----------------------------------------------------------------------------
// One platform at a time
// -----------------------------------------------------------------------------

// basic-webserver and basic-cli declare 197 of the same full names and disagree
// about the type of roughly half of them. An app pins one platform, so the
// server resolves over one platform, and the two never compete for a name.
test("a pinned workspace answers from its own platform and not the other", async () => {
  const root = workspace("cli-pinned", { "main.roc": cliAppFile("0.25.0") });
  const [scoped, shared, module] = await session({ cwd: root }, [
    scopes,
    { name: "search_symbols", args: { query: ["Cmd.exec!"] } },
    { name: "get_roc_module", args: { module: "Path" } },
  ]);
  assert.match(scoped, /Detected basic-cli 0\.25\.0 from main\.roc, bundled 0\.25\.0\./);

  assert.match(shared, /basic-cli 0\.25\.0/);
  assert.ok(!shared.includes("basic-webserver"), "the unpinned platform answered too");
  assert.ok(!shared.includes("declared by 2 bundled platforms"), "there was a collision to state");

  // `replace_utf8!` is only in basic-cli and `parser_for` is only in
  // basic-webserver. A page with both would mix the two modules.
  assert.match(module, /replace_utf8!/);
  assert.ok(!module.includes("parser_for"), "the two Path modules were merged");
  assert.ok(!module.includes("basic-webserver"), "the unpinned platform was advertised");
});

// `Random` in basic-cli and `Random` in roc-random are two modules that an app
// imports through two aliases. One flat list would look like one module with
// both APIs.
test("a module name two namespaces share is listed per origin", async () => {
  const rand =
    "https://github.com/kili-ilo/roc-random/releases/download/0.9.2/2ZXLX8WRqrosGu1V3VL5aXqgtfTRvJmjFPx8a26ecVmc.tar.zst";
  const root = workspace("cli-rand", {
    "main.roc": `app [main!] {\n\tpf: platform "${cliUrl("0.25.0")}",\n\trand: "${rand}",\n}\n\nmain! = |_args| Ok({})\n`,
  });
  const [shared, alone] = await session({ cwd: root }, [
    { name: "get_roc_module", args: { module: "Random" } },
    { name: "get_roc_module", args: { module: "Stdout" } },
  ]);
  assert.match(shared, /2 modules share this name/);
  const cli = shared.indexOf("## basic-cli 0.25.0");
  const pkg = shared.indexOf("## roc-random 0.9.2");
  assert.ok(cli > 0 && pkg > 0, "a section per origin");
  assert.ok(shared.indexOf("seed_u64!") > cli && shared.indexOf("seed_u64!") < pkg, "basic-cli's method under basic-cli");
  assert.ok(shared.indexOf("bounded_u8") > pkg, "roc-random's method under roc-random");

  // Without a collision there are no sections. The common case stays one list.
  assert.match(alone, /From basic-cli 0\.25\.0\./);
  assert.ok(!alone.includes("## "), "a module with one origin was split");
});

// Out of scope and unknown are different answers that call for different next
// steps. "No such builtin" for a name that exists is false. The note ends at a
// concrete scope value, so the caller can act on it or ignore it.
test("a name from the platform not pinned is reported as out of scope", async () => {
  const root = workspace("cli-pinned-2", { "main.roc": cliAppFile("0.25.0") });
  const [name, module] = await session({ cwd: root }, [
    { name: "search_symbols", args: { query: ["Server.Outcome"] } },
    { name: "get_roc_module", args: { module: "Sse" } },
  ]);
  for (const text of [name, module]) {
    assert.match(
      text,
      /is not in the builtins or basic-cli 0\.25\.0, the platform this app's header imports, so it will not compile here\./
    );
    // One line per platform, each with its count. The shape is the same for any
    // number of platforms. A sentence joined by "and" does not have that property.
    assert.match(text, /\nFound in:\nbasic-webserver 0\.17\.0: \d+\n/);
    assert.match(text, /Try again with `scope: basic-webserver` to see it\.$/);
  }
  assert.match(name, /^`Server\.Outcome`/);
  assert.match(module, /^`Sse`/);
});

// An explicit argument reaches any corpus. Thus the message above gives the
// caller a next step that works.
test("scope reaches the platform the workspace does not pin", async () => {
  const root = workspace("cli-pinned-3", { "main.roc": cliAppFile("0.25.0") });
  const [name, module] = await session({ cwd: root }, [
    { name: "search_symbols", args: { query: ["Server.Outcome"], scope: "basic-webserver" } },
    { name: "get_roc_module", args: { module: "Path", scope: "basic-webserver" } },
  ]);
  assert.match(name, /basic-webserver 0\.17\.0/);
  assert.match(module, /parser_for/);
  assert.ok(!module.includes("replace_utf8!"), "the two Path modules were merged");
});

// With no app header, the address space holds no platform. A guess would be
// worse than a statement of that fact, and an answer from both platforms would
// invite use of the wrong one.
test("with nothing pinned, no platform answers and the note says where to look", async () => {
  const root = workspace("unpinned", { "lib.roc": "module [x]\n\nx = 1\n" });
  const [shared, module] = await session({ cwd: root }, [
    { name: "search_symbols", args: { query: ["Cmd.exec!"] } },
    { name: "get_roc_module", args: { module: "Path" } },
  ]);
  for (const text of [shared, module]) {
    assert.match(text, /is not in the builtins, and no platform is in scope\./);
    assert.match(
      text,
      /\nFound in:\nbasic-webserver 0\.17\.0: \d+\nbasic-cli 0\.25\.0: \d+\n/
    );
    // A retry line that names every candidate again does not scale. Thus, with
    // more than one candidate, the line points back to the list.
    assert.match(text, /Try again with `scope:` set to one of these to see it\.$/);
    // No signature and no method list, because no item here is an answer to act on.
    assert.ok(!text.includes("```"), "an unpinned lookup returned a platform item");
  }
});

// A retry into a platform that the app cannot use is the only hint to withhold,
// because the result is code that does not compile.
test("a footer never offers the platform the workspace does not pin", async () => {
  const pinned = workspace("cli-pinned-4", { "main.roc": cliAppFile("0.25.0") });
  const [scoped] = await session({ cwd: pinned }, [
    { name: "get_roc_syntax", args: { topic: "sqlite", scope: "language" } },
  ]);
  assert.ok(!scoped.includes("basic-webserver:"), "the unpinned platform was offered");

  const unpinned = workspace("unpinned-2", { "lib.roc": "module [x]\n\nx = 1\n" });
  const [open] = await session({ cwd: unpinned }, [
    { name: "get_roc_syntax", args: { topic: "sqlite", scope: "language" } },
  ]);
  assert.match(open, /basic-webserver: \d+/);
});

// -----------------------------------------------------------------------------
// The app header's package pins
// -----------------------------------------------------------------------------

// The platform's header says what the platform needs. The app's header says
// what the app imports. If the server read only the platform's header, a package
// with no provider would be invisible until a lookup failed with no reason.
test("a package the app pins that no platform declares is named and its miss explained", async () => {
  const root = workspace("app-pin", {
    "main.roc": appWithPin(
      'json: "https://github.com/example/json/releases/download/2.1.0/AAAA.tar.br",'
    ),
  });
  const [listed, missed] = await session({ cwd: root }, [
    scopes,
    { name: "search_symbols", args: { query: ["qqqzzzxyw"] } },
  ]);
  assert.match(listed, /Also pinned: example\/json 2\.1\.0 \(no provider\)\./);
  assert.match(missed, /No provider serves example\/json\.\nYour app header pins 2\.1\.0\./);
});

// The compiler's own diagnostic for this case names `Request` on both sides with
// no package attribution. The server can state the cause because it has both pins.
test("an app pinning a release the platform's API refuses is told before the compiler is", async () => {
  const root = workspace("app-pin-clash", {
    "main.roc": appWithPin(
      'http: "https://github.com/roc-lang/http/releases/download/9.9.9/AAAA.tar.br",'
    ),
  });
  const [text] = await session({ cwd: root }, [
    { name: "get_roc_syntax", args: { topic: "webserver_handler", scope: "basic-webserver" } },
  ]);
  assert.match(text, /Your app pins roc-lang\/http 9\.9\.9, and this server serves 1\.0\.0\./);
  assert.match(text, /this app will not compile\. Move the app's pin to 1\.0\.0/);
});

// The shipped case: every bundled example pins the release that its platform
// requires. Thus the app header must add nothing to those answers.
test("an app pinning what its platform requires is told nothing new", async () => {
  const root = workspace("app-pin-agrees", {
    "main.roc": appWithPin(
      'http: "https://github.com/roc-lang/http/releases/download/1.0.0/AAAA.tar.br",'
    ),
  });
  const [listed, text] = await session({ cwd: root }, [
    scopes,
    { name: "get_roc_syntax", args: { topic: "webserver_handler", scope: "basic-webserver" } },
  ]);
  assert.ok(!listed.includes("Also pinned:"), "a pin the platform declares was reported as extra");
  assert.ok(!text.includes("Your app pins"), "an agreeing pin was reported as a conflict");
});

test("an example is listed, found from a question, and read through a tool", async () => {
  const [listed, pointed] = await session({ cwd: ROOT }, [
    { name: "list_roc_index", args: { kind: "examples", scope: "basic-webserver" } },
    { name: "get_roc_syntax", args: { topic: "sleep", scope: "basic-webserver" } },
  ]);
  // A client without resources cannot follow a pointer to a URI.
  for (const text of [listed, pointed]) assert.ok(!text.includes("roc-syntax://"), text);
  assert.match(listed, /^- basic-webserver\/sse$/m);
  // A real address, not a template, so the format needs no explanation.
  assert.match(listed, /^Read one with get_roc_syntax\(topic: "basic-webserver\/[a-z.-]+"\)\.$/m);
  // No topic covers "sleep", so the reply points to the program by its address.
  assert.match(pointed, /^No topic is a sure match for "sleep"/);
  assert.match(pointed, /^- get_roc_syntax\(topic: "basic-webserver\/sleep"\): /m);
});

test("get_roc_syntax reads an example by its address or its URI", async () => {
  const [cli, web, uri, pkg, page, missing, keyword] = await session({ cwd: ROOT }, [
    { name: "get_roc_syntax", args: { topic: "basic-cli/command" } },
    { name: "get_roc_syntax", args: { topic: "basic-webserver/command", scope: "basic-cli" } },
    { name: "get_roc_syntax", args: { topic: "roc-syntax://platform/basic-webserver/example/sse" } },
    { name: "get_roc_syntax", args: { topic: "roc-parser/csv-movies" } },
    { name: "get_roc_syntax", args: { topic: "roc-parser" } },
    { name: "get_roc_syntax", args: { topic: "basic-cli/nope" } },
    { name: "get_roc_syntax", args: { topic: "sqlite", scope: "basic-cli" } },
  ]);
  const file = (p: string) => fs.readFileSync(path.join(ROOT, p), "utf-8").trimEnd();
  // Two platforms ship a `command` example. The address picks one, for any scope.
  assert.ok(cli.startsWith("## basic-cli/command\n") && cli.includes(file("corpus/platforms/basic-cli/examples/command.roc")), cli);
  assert.ok(web.includes(file("corpus/platforms/basic-webserver/examples/command.roc")), web);
  assert.ok(uri.includes(file("corpus/platforms/basic-webserver/examples/sse.roc")), uri);
  assert.ok(pkg.includes(file("corpus/packages/roc-parser/examples/csv-movies.roc")), pkg);
  assert.match(page, /^Examples: roc-parser\/csv-movies, .*\. Read one with get_roc_syntax\(topic: "roc-parser\/csv-movies"\)\.$/m);
  assert.match(missing, /^No example "nope" in basic-cli\. Its examples: .*\bhello-world\b/);
  // A bare word is a topic search, never the name of an example.
  assert.match(keyword, /^## cli_sqlite\n/);
});

// -----------------------------------------------------------------------------
// Releases the app pins that no corpus serves
// -----------------------------------------------------------------------------

/**
 * A `roc` that does what `roc deps` does to the cache, from canned trees: the
 * release tagged `<tag>` unpacks `trees/<tag>/`, and a tag with no tree fails
 * the way a download does. Every run is logged, so a test can count them.
 */
function fakeRoc(name: string, trees: Record<string, Record<string, string>>, opts: { sleep?: number } = {}) {
  const dir = path.join(tmp, name);
  const cache = path.join(dir, "cache");
  const log = path.join(dir, "roc.log");
  fs.mkdirSync(path.join(dir, "bin"), { recursive: true });
  fs.mkdirSync(cache);
  for (const [tag, files] of Object.entries(trees)) {
    fs.mkdirSync(path.join(dir, "trees", tag), { recursive: true });
    for (const [file, content] of Object.entries(files)) {
      fs.writeFileSync(path.join(dir, "trees", tag, file), content);
    }
  }
  fs.writeFileSync(
    path.join(dir, "bin", "roc"),
    `#!/bin/sh
echo "$@" >> "${log}"
sleep ${opts.sleep ?? 0}
url=$(grep -o 'https://[^"]*' "$2")
tag=$(echo "$url" | awk -F/ '{ print $(NF-1) }')
hash=$(basename "$url" | sed 's/[.]tar[.].*//')
[ -d "${dir}/trees/$tag" ] || exit 1
mkdir -p "${cache}/$hash" && cp -r "${dir}/trees/$tag/." "${cache}/$hash/"
`,
    { mode: 0o755 }
  );
  return {
    // Set ROC too, because it has priority over PATH, and the developer's shell may set it.
    env: {
      PATH: `${path.join(dir, "bin")}${path.delimiter}${process.env.PATH}`,
      ROC: path.join(dir, "bin", "roc"),
      ROC_PACKAGE_CACHE: cache,
    },
    runs: () => (fs.existsSync(log) ? fs.readFileSync(log, "utf-8").trim().split("\n").length : 0),
  };
}

const FAKE_HASH = "FakeRe1easeHashForTests1234567891234567891234";
const randUrl = (v: string) => `https://github.com/kili-ilo/roc-random/releases/download/${v}/${FAKE_HASH}.tar.zst`;
const cliPinning = (pin: string) =>
  `app [main!] {\n\tpf: platform "${cliUrl("0.25.0")}",\n\t${pin}\n}\n\nmain! = |_args| Ok({})\n`;

// The fetch delays the first answer. A "not fetched yet" answer would cost the
// model one turn to fill the cache and one more turn to ask again.
test("a package release nothing serves is fetched before the first answer", async () => {
  const roc = fakeRoc("fetch-pkg", {
    "9.9.9": {
      "main.roc": "package [Random] {}\n",
      "Random.roc": "Random := [].{\n\t## Only in 9.9.9.\n\tbrand_new : U64 -> U64\n}\n",
    },
  });
  const root = workspace("fetch-pkg-app", { "main.roc": cliPinning(`rand: "${randUrl("9.9.9")}",`) });
  const [found, listing, again, page, topic] = await session({ cwd: root, env: roc.env }, [
    { name: "search_symbols", args: { query: ["Random.brand_new"] } },
    scopes,
    { name: "search_symbols", args: { query: ["brand_new"] } },
    { name: "get_roc_syntax", args: { topic: "roc-random" } },
    { name: "get_roc_syntax", args: { topic: "random_generators" } },
  ]);
  // The prose was written for 0.9.2, and the server serves it for any release.
  // Most of what it teaches is correct, and the signatures above come from the
  // pinned release.
  assert.match(page, /^This page documents roc-random \d+\.\d+\.\d+\.$/m);
  assert.match(page, /This app pins it/);
  assert.match(topic, /import rand\.Random/);
  assert.match(found, /Random\.brand_new \(roc-random 9\.9\.9\)/);
  assert.match(found, /Only in 9\.9\.9\./);
  assert.match(listing, /kili-ilo\/roc-random 9\.9\.9 \(served by the Roc package cache\)/);
  assert.match(again, /Random\.brand_new/);
  assert.equal(roc.runs(), 1, "fetched once, for the whole session");
});

// A failed download leaves the server answering from what it has, and saying so.
test("a release that cannot be fetched falls back to the bundled one", async () => {
  const roc = fakeRoc("fetch-fail", {});
  const root = workspace("fetch-fail-app", { "main.roc": cliPinning(`rand: "${randUrl("9.9.9")}",`) });
  const [found, searched] = await session({ cwd: root, env: roc.env }, [
    { name: "search_symbols", args: { query: ["Random.bounded_u8"] } },
    { name: "search_symbols", args: { query: ["bounded_u8 : U8"] } },
  ]);
  assert.match(found, /\(roc-random 0\.9\.2\)/);
  assert.match(searched, /Your app pins kili-ilo\/roc-random 9\.9\.9, and this server serves 0\.9\.2\./);
  assert.equal(roc.runs(), 1);
});

// Many clients cancel a call after about a minute, and a cancelled call returns
// no answer. After the wait, the answer comes from the bundled release and says
// so once. The download continues, and a later call reads the pinned release.
test("a slow fetch stops holding up answers, and lands for a later one", async () => {
  const roc = fakeRoc(
    "fetch-slow",
    {
      "9.9.9": {
        "main.roc": "package [Random] {}\n",
        "Random.roc": "Random := [].{\n\t## Only in 9.9.9.\n\tbrand_new : U64 -> U64\n}\n",
      },
    },
    { sleep: 2 }
  );
  const root = workspace("fetch-slow-app", { "main.roc": cliPinning(`rand: "${randUrl("9.9.9")}",`) });
  const started = Date.now();
  const [early, again, late] = await session({ cwd: root, env: { ...roc.env, ROC_MCP_FETCH_WAIT_MS: "300" } }, [
    { name: "search_symbols", args: { query: ["Random.bounded_u8"] } },
    // Detection runs again on a workspace change, and finds the download running.
    { name: "search_symbols", args: { query: ["Random.bounded_u8"] }, delayMs: 800, notifyFirst: "notifications/roots/list_changed" },
    { name: "search_symbols", args: { query: ["Random.brand_new"] }, delayMs: 4000 },
  ]);
  assert.match(early, /\(roc-random 0\.9\.2\)/);
  assert.match(early, /`roc deps` is still downloading .*roc-random.*This answer is from the release this server bundles/s);
  assert.doesNotMatch(again, /still downloading/);
  assert.match(late, /Random\.brand_new \(roc-random 9\.9\.9\)/);
  assert.equal(roc.runs(), 1, "one download, never a second while it runs");
  assert.ok(Date.now() - started < 15_000);
});

// A platform pinned at a different release is read from that release: its own
// modules and its own header. The prose comes from the bundled release, and the
// note says which part comes from which release.
test("a platform pinned at another release is read from that release", async () => {
  const roc = fakeRoc("fetch-platform", {
    "0.26.0": {
      "main.roc": 'platform ""\n\texposes [Stdout]\n\tpackages {}\n',
      "Stdout.roc": "Stdout := [].{\n\t## New in 0.26.0.\n\tline_new! : Str => {}\n}\n",
    },
  });
  const pinned = `https://github.com/roc-lang/basic-cli/releases/download/0.26.0/${FAKE_HASH}.tar.zst`;
  const root = workspace("fetch-platform-app", {
    "main.roc": `app [main!] { pf: platform "${pinned}" }\n\nmain! = |_args| Ok({})\n`,
  });
  const [found, old, listing, searched, overview] = await session({ cwd: root, env: roc.env }, [
    { name: "search_symbols", args: { query: ["Stdout.line_new!"] } },
    { name: "search_symbols", args: { query: ["Stdout.line!"] } },
    scopes,
    { name: "search_symbols", args: { query: ["-> Str"] } },
    { name: "get_roc_syntax", args: { scope: "basic-cli" } },
  ]);
  assert.match(overview, /basic-cli/);
  assert.ok(overview.length > 2000, "the 0.25.0 overview was withheld from a 0.26.0 app");
  // The page states no release, so the server says which one it documents: the bundled one, not the pin.
  assert.match(overview, /^This page documents basic-cli (?!0\.26\.0)\d+\.\d+\.\d+\.$/m);
  assert.match(found, /Stdout\.line_new! \(basic-cli 0\.26\.0\)/);
  assert.match(searched, /Signatures here are read from that release\. The overview, topics and examples were written for 0\.25\.0/);
  assert.doesNotMatch(old, /Stdout\.line! \(basic-cli/, "0.25.0's API is not served for a 0.26.0 app");
  assert.match(listing, /Detected basic-cli 0\.26\.0 from main\.roc, bundled 0\.25\.0, signatures read from 0\.26\.0\./);
});

// -----------------------------------------------------------------------------
// The packages this server documents
// -----------------------------------------------------------------------------

// Without this rule, `Random` from roc-random would appear next to `Random` from
// basic-cli in every app, and split every answer about it in two. A bundled
// package is not a package that the app chose.
test("a bundled package is in the space only when the app pins it", async () => {
  const bare = workspace("cli-no-rand", { "main.roc": cliAppFile("0.25.0") });
  const [module, missed] = await session({ cwd: bare }, [
    { name: "get_roc_module", args: { module: "Random" } },
    { name: "search_symbols", args: { query: ["Random.bounded_u8"] } },
  ]);
  assert.match(module, /From basic-cli 0\.25\.0\./);
  assert.doesNotMatch(module, /roc-random/);
  // The miss carries the answer, the package, and the line that adds it, because
  // no `scope` retry reaches a package.
  assert.match(missed, /`Random\.bounded_u8` is in roc-random 0\.9\.2, a package this app does not pin:/);
  assert.match(missed, /^ {4}Random\.bounded_u8 : U8, U8 -> Generator\(U8\)$/m);
  assert.match(missed, /<alias>: "https:\/\/github\.com\/kili-ilo\/roc-random\/releases\/download\/0\.9\.2\/2ZXLX8WR/);
  assert.match(missed, /get_roc_syntax\(topic: "roc-random"\)/);

  const pinned = workspace("cli-with-rand", {
    "main.roc": cliPinning(
      `rand: "https://github.com/kili-ilo/roc-random/releases/download/0.9.2/2ZXLX8WRqrosGu1V3VL5aXqgtfTRvJmjFPx8a26ecVmc.tar.zst",`
    ),
  });
  const [found, searched, narrowed, tour] = await session({ cwd: pinned }, [
    { name: "search_symbols", args: { query: ["Random.bounded_u8"] } },
    { name: "search_symbols", args: { query: ["U8, U8 -> Generator(U8)"] } },
    { name: "search_symbols", args: { query: ["U8, U8 -> Generator(U8)"], scope: "builtin" } },
    { name: "get_roc_syntax", args: {} },
  ]);
  assert.match(found, /Random\.bounded_u8 \(roc-random 0\.9\.2\)/);
  // A pinned package is read with the builtins, so both an unscoped search and
  // one narrowed to the builtins reach it.
  assert.match(searched, /Random\.bounded_u8/);
  assert.match(narrowed, /\*\*Random\.bounded_u8\*\* \(roc-random 0\.9\.2\)/);
  assert.match(tour, /roc-random \(pseudorandom values, on any platform, pinned by this app\)/);
});

test("a bundled package has an overview and a topic", async () => {
  const root = workspace("pkg-docs", { "main.roc": cliAppFile("0.25.0") });
  const [random, parser, topic, scopesList, tour] = await session({ cwd: root }, [
    { name: "get_roc_syntax", args: { topic: "roc-random" } },
    { name: "get_roc_syntax", args: { topic: "lukewilliamboswell/roc-parser", scope: "basic-cli" } },
    { name: "get_roc_syntax", args: { topic: "parser_combinators" } },
    scopes,
    { name: "get_roc_syntax", args: {} },
  ]);
  // A model learns that these packages exist from its first call.
  assert.match(
    tour,
    /Packages documented here: roc-parser \(parsing text formats, on any platform\); roc-random \(pseudorandom values, on any platform\)\. get_roc_syntax\(topic: "roc-parser"\) for one's page\./
  );
  // A package page answers to its name or its repo path, for any scope.
  assert.match(random, /^# roc-random\n/);
  assert.match(random, /import pf\.Random as Entropy/);
  assert.match(random, /^Topics: random_generators\.$/m);
  assert.match(random, /This app does not pin it\. Add it to the app header/);
  assert.match(parser, /^# roc-parser\n/);
  assert.match(topic, /Parser\.lazy/);
  assert.match(topic, /From roc-parser 2\.0\.0, a package this app does not pin\./);
  // Listed for attribution, and never as a scope.
  assert.match(scopesList, /^# Documented packages$/m);
  assert.match(scopesList, /roc-random\*\*: The roc-random package: pseudorandom integers.* Not pinned by this app\./);
  assert.doesNotMatch(scopesList.split("# Documented packages")[0], /roc-random/);
});
