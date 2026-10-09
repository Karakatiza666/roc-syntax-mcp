// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Tests for declared plugins, end to end over a real stdio session.
//
// The unit tests cover where a declaration comes from. The session tests cover
// what the server does with a declaration. They start a server, because
// `SCOPES` is final before the first request and no in-process code can
// rebuild it.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { LATEST_PROTOCOL_VERSION } from "@modelcontextprotocol/server";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  declarations,
  forcedNamespaces,
  resolvePluginDir,
  workspaceRoot,
} from "./plugins.ts";
import { indexText } from "./release.ts";
import { BARE_ENV } from "./testdata/isolate.ts";
import { PLUGIN_TOOL_GROWTH, inspectDeclarations } from "./scopes.ts";

const ROOT = path.join(import.meta.dirname, "..");
const TSX_LOADER = import.meta.resolve("tsx/esm");

let tmp: string;
before(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roc-plugins-"));
});
after(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

function write(root: string, files: Record<string, string>): string {
  for (const [rel, content] of Object.entries(files)) {
    const file = path.join(root, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content);
  }
  return root;
}

/** A release URL with a fake hash. An index uses the hash only as a name. */
const release = (repo: string, version: string, hash: string) =>
  `https://github.com/${repo}/releases/download/${version}/${hash.padEnd(24, "0")}.tar.zst`;

/** The index.json that `plugin index` writes for these releases, from their sources. */
function indexed(releases: Record<string, Record<string, string>>): string {
  return indexText(
    Object.entries(releases).map(([url, files]) => {
      const dir = fs.mkdtempSync(path.join(tmp, "release-"));
      write(dir, files);
      return { url, dir };
    })
  );
}

const RAY_RELEASE = release("lukewilliamboswell/roc-ray", "0.7.0", "RayRelease");

/** A platform plugin with one exposed module, which is enough for the index and for detection. */
function plugin(dir: string, manifest: Record<string, unknown>): string {
  const root = path.join(tmp, dir);
  return write(root, {
    "plugin.json": JSON.stringify(manifest),
    "index.json": indexed({
      [RAY_RELEASE]: {
        "main.roc": 'platform "roc-ray"\n    exposes [Draw]\n    packages {}\n',
        "Draw.roc": "Draw := [].{\n    circle! : F32 => {}\n}\n",
      },
    }),
  });
}

/**
 * A package plugin that serves one package, with a page and topics. Its header
 * declares a package, so it adds no scope. The package is in a space only when
 * an app pins it, never because it is installed.
 */
function packagePlugin(dir: string): string {
  const root = path.join(tmp, dir);
  return write(root, {
    "plugin.json": JSON.stringify({
      schema: 1,
      maintainer: "nobody",
      corpora: [
        {
          release: WEAVE_PIN,
          description: "An argument parser.",
          checks: ["topics"],
          topics: [
            {
              name: "weave_cli",
              file: "topics/weave_cli.roc",
              description: "Parsing arguments.",
              keywords: ["command line", "arguments"],
            },
          ],
        },
      ],
    }),
    "index.json": indexed({
      [WEAVE_PIN]: {
        "main.roc": "package [Opt] {}\n",
        "Opt.roc": "Opt := [].{\n    flag : Str -> Bool\n}\n",
        "Hidden.roc": "Hidden := [].{\n    secret : Str -> Bool\n}\n",
      },
    }),
    "topics/weave_cli.roc": 'app [main!] { pf: platform "x" }\n',
  });
}

const WEAVE_PIN =
  "https://github.com/someone/weave/releases/download/0.8.0/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.tar.zst";
const CLI_PIN =
  "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst";

/** A one-platform manifest. Its name, version and detection come from the release. */
const ray = (corpus: Record<string, unknown> = {}, top: Record<string, unknown> = {}) => ({
  schema: 1,
  ...top,
  corpora: [{ release: RAY_RELEASE, description: "A graphics platform.", ...corpus }],
});

interface Run {
  /** Extra arguments, e.g. `--plugin=`. */
  argv?: string[];
  env?: Record<string, string>;
  cwd?: string;
  /** Defaults to one `list_roc_index(kind: "scopes")`. */
  calls?: { name: string; args?: unknown }[];
}

/** Tool calls against a launched server, with its stderr kept. */
function session(opts: Run): Promise<{ text: string; texts: string[]; stderr: string; code: number | null }> {
  return new Promise((resolve, reject) => {
    const child = spawn(
      process.execPath,
      ["--import", TSX_LOADER, path.join(ROOT, "src", "index.ts"), ...(opts.argv ?? [])],
      {
        cwd: opts.cwd ?? ROOT,
        env: { ...process.env, CLAUDE_PROJECT_DIR: opts.cwd ?? "", ...(opts.env ?? {}) },
        stdio: ["pipe", "pipe", "pipe"],
      }
    );

    const calls = opts.calls ?? [{ name: "list_roc_index", args: { kind: "scopes" } }];
    let stderr = "";
    const texts: string[] = [];
    child.stderr.on("data", (c) => (stderr += c));
    const send = (msg: unknown) => child.stdin.write(JSON.stringify(msg) + "\n");
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error(`session timed out: ${stderr}`));
    }, 30_000);

    send({
      jsonrpc: "2.0",
      id: 0,
      method: "initialize",
      params: {
        protocolVersion: LATEST_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: { name: "plugin-test", version: "1.0.0" },
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
        if (msg.id === 0) {
          send({ jsonrpc: "2.0", method: "notifications/initialized" });
          calls.forEach((c, i) =>
            send({
              jsonrpc: "2.0",
              id: i + 1,
              method: "tools/call",
              params: { name: c.name, arguments: c.args ?? {} },
            })
          );
          continue;
        }
        if (typeof msg.id === "number" && msg.id > 0) {
          if (msg.error) {
            child.kill();
            return reject(new Error(`${calls[msg.id - 1].name}: ${msg.error.message}`));
          }
          texts[msg.id - 1] = msg.result.content.map((c: { text: string }) => c.text).join("\n");
          if (texts.filter((t) => t !== undefined).length === calls.length) {
            clearTimeout(timer);
            child.kill();
          }
        }
      }
    });

    // A server that exits before it answers also gives a result.
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ text: texts[0] ?? "", texts, stderr, code });
    });
    child.on("error", reject);
  });
}

// -----------------------------------------------------------------------------
// Where a declaration comes from
// -----------------------------------------------------------------------------

test("the flag and the variable are additive, first mention winning", () => {
  const found = declarations(
    ["--platform=basic-cli", "--plugin=./from-flag", "--plugin=@roc-syntax/a"],
    { ...BARE_ENV, ROC_MCP_PLUGINS: "./from-env,@roc-syntax/a" }
  );
  assert.deepEqual(found, [
    { spec: "./from-flag", source: "--plugin=" },
    { spec: "@roc-syntax/a", source: "--plugin=" },
    { spec: "./from-env", source: "ROC_MCP_PLUGINS" },
  ]);
});

// A force has the same sources as a declaration, because both record what the
// operator asked for. No manifest is read, so a plugin cannot force itself.
test("a forced namespace is read from the flag and the variable, first mention winning", () => {
  const found = forcedNamespaces(
    ["--plugin=./x", "--force=roc-lang/a", "--force=roc-lang/b,roc-lang/c"],
    { ROC_MCP_FORCE: "roc-lang/from-env,roc-lang/a" }
  );
  assert.deepEqual(found, [
    { spec: "roc-lang/a", source: "--force=" },
    { spec: "roc-lang/b", source: "--force=" },
    { spec: "roc-lang/c", source: "--force=" },
    { spec: "roc-lang/from-env", source: "ROC_MCP_FORCE" },
  ]);
});

test("the workspace is --workspace=, then CLAUDE_PROJECT_DIR, then the cwd", () => {
  const dir = fs.mkdtempSync(path.join(tmp, "ws-"));
  assert.equal(workspaceRoot({ CLAUDE_PROJECT_DIR: "/claude" }, [`--workspace=${dir}`]), dir);
  assert.equal(workspaceRoot({ CLAUDE_PROJECT_DIR: "/claude" }, []), "/claude");
  assert.equal(workspaceRoot({}, []), process.cwd());
  // A placeholder that the client did not substitute is not a folder, so the server skips it.
  assert.equal(workspaceRoot({ CLAUDE_PROJECT_DIR: "/claude" }, ["--workspace=${workspaceFolder}"]), "/claude");
});

// A project can commit `--plugin=` in its own client config. A config file of
// this server next to the app would add one more place to look, but no new
// capability.
test("a roc-syntax-mcp.json in the workspace declares nothing", () => {
  const root = write(path.join(tmp, "old-config"), {
    "roc-syntax-mcp.json": JSON.stringify({ plugins: ["./bare"] }),
    "bare/plugin.json": "{}",
  });
  assert.deepEqual(inspectDeclarations([], { ROC_MCP_HOME: path.join(tmp, "no-home") }, root), []);
});

// A client that passes env more easily than args rarely knows which path
// separator its OS uses.
test("the environment variable takes either separator", () => {
  const specs = declarations([], { ...BARE_ENV, ROC_MCP_PLUGINS: " a ; b : c , d " }).map((d) => d.spec);
  assert.deepEqual(specs, ["a", "b", "c", "d"]);
});

test("a declared path with no manifest resolves to nothing", () => {
  const root = write(path.join(tmp, "empty-plugin"), { "README.md": "no manifest here" });
  assert.throws(() => resolvePluginDir(root, tmp), /plugin\.json/);
  assert.equal(resolvePluginDir(plugin("resolvable", ray()), tmp), path.join(tmp, "resolvable"));
});

// `npm i -g`, `yarn global add` and `bun add -g` put a plugin next to the
// server. The server never resolves a package name in the workspace, because
// a package that a project installs for its build is not a plugin that this
// user chose to serve.
test("a package installed beside the server resolves, and a workspace copy is not read", () => {
  const global = path.join(tmp, "global", "node_modules");
  const server = path.join(global, "roc-syntax-mcp", "src", "plugins.ts");
  write(global, { "@x/ray/plugin.json": "{}" });
  const local = write(path.join(tmp, "ws-with"), { "node_modules/@x/ray/plugin.json": "{}" });
  assert.equal(resolvePluginDir("@x/ray", local, [server]), path.join(global, "@x", "ray"));
  write(local, { "node_modules/@x/absent/plugin.json": "{}" });
  assert.throws(() => resolvePluginDir("@x/absent", local, [server]), /installed neither by plugin add nor beside this server/);
});

// -----------------------------------------------------------------------------
// What the server does with one
// -----------------------------------------------------------------------------

/** One `tools/list`, as a client sees it. */
function toolsList(argv: string[]): Promise<{ name: string; description: string; inputSchema: any }[]> {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["--import", TSX_LOADER, path.join(ROOT, "src", "index.ts"), ...argv], {
      cwd: ROOT,
      env: { ...process.env, CLAUDE_PROJECT_DIR: "" },
      stdio: ["pipe", "pipe", "ignore"],
    });
    const send = (msg: unknown) => child.stdin.write(JSON.stringify(msg) + "\n");
    send({
      jsonrpc: "2.0",
      id: 0,
      method: "initialize",
      params: { protocolVersion: LATEST_PROTOCOL_VERSION, capabilities: {}, clientInfo: { name: "t", version: "1" } },
    });
    let buf = "";
    child.stdout.on("data", (chunk) => {
      buf += chunk;
      const lines = buf.split("\n");
      buf = lines.pop() ?? "";
      for (const line of lines.filter((l) => l.trim())) {
        const msg = JSON.parse(line);
        if (msg.id === 0) {
          send({ jsonrpc: "2.0", method: "notifications/initialized" });
          send({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} });
        } else if (msg.id === 1) {
          child.kill();
          resolve(msg.result.tools);
        }
      }
    });
    child.on("close", (code) => reject(new Error(`the server exited (${code}) before tools/list`)));
  });
}

const cost = (tool: unknown) => Math.round(JSON.stringify(tool).length / 3.5);

// `plugin add` serves every installed plugin in every workspace. Thus the limit
// applies per tool to the whole set of plugins, not to each plugin alone.
test("however many plugins load, no tool grows past its ceiling, and every scope still answers", async () => {
  const argv = Array.from({ length: 10 }, (_, i) => {
    const topics = ["drawing", "input", "audio"].map((t) => ({
      name: `many${i}_${t}_basics`,
      file: `topics/${t}.roc`,
      description: `The ${t} API.`,
      keywords: [t],
    }));
    const dir = plugin(`ray-many-${i}`, ray({ name: `ray-many-${i}`, checks: ["topics"], topics }));
    write(dir, Object.fromEntries(topics.map((t) => [t.file, 'app [main!] { pf: platform "x" }\n'])));
    return `--plugin=${dir}`;
  });
  const [base, loaded] = await Promise.all([toolsList([]), toolsList(argv)]);
  // The 15 extra tokens allow for the pointer that names what did not fit.
  const over = loaded
    .map((t) => ({ name: t.name, growth: cost(t) - cost(base.find((b) => b.name === t.name)) }))
    .filter((t) => t.growth > PLUGIN_TOOL_GROWTH + 15);
  assert.deepEqual(over, []);

  const syntax = loaded.find((t) => t.name === "get_roc_syntax")!;
  assert.match(syntax.description, /many0_drawing_basics/, "the first plugin's topics are not named");
  assert.match(syntax.description, /\d+ more topics: list_roc_index\(kind='topics'\)/);
  assert.equal(syntax.inputSchema.properties.scope.enum, undefined, "ten plugins still fit an enum");

  // With no enum, the server accepts the scope of the last plugin and refuses a wrong scope.
  const { texts } = await session({
    argv,
    calls: [
      { name: "get_roc_syntax", args: { topic: "many9_audio_basics", scope: "ray-many-9" } },
      { name: "get_roc_syntax", args: { topic: "many9_audio_basics", scope: "no-such-scope" } },
    ],
  });
  assert.match(texts[0], /app \[main!\]/, texts[0]);
  assert.match(texts[1], /scope must be one of/);
});

test("a declared plugin becomes a scope the server serves", async () => {
  const dir = plugin("ray-ok", ray());
  const { text, stderr } = await session({ argv: [`--plugin=${dir}`] });
  assert.match(text, /- \*\*roc-ray\*\*: A graphics platform\. Pinned to 0\.7\.0\. 1 indexed items\./);
  assert.equal(stderr.includes("plugin"), false, stderr);
});

// Every path in a manifest is absolute. If a reader joins one to the host
// root, the result points to a file that does not exist. `get_roc_syntax(scope:)` must
// return the page, not "Overview unavailable".
test("a declared plugin's overview page is read from the plugin", async () => {
  const dir = plugin("ray-overview", ray({ name: "ray-overview", overview: "overview.md" }));
  write(dir, { "overview.md": "# roc-ray\n\nDraw a circle and nothing else.\n" });
  const { text } = await session({
    argv: [`--plugin=${dir}`],
    calls: [{ name: "get_roc_syntax", args: { scope: "ray-overview" } }],
  });
  assert.match(text, /Draw a circle and nothing else\./);
});

// A corpus can give wrong facts about Roc, and no check script catches a page
// that compiles but is wrong. This design uses attribution, not review, to
// reduce that risk. Thus the listing shows the maintainer of every scope, not
// only of the scopes that name one.
test("the scope listing says who answers for every scope", async () => {
  const { text } = await session({});
  const scopes = text.split("\n").filter((l) => l.startsWith("- **"));
  assert.ok(scopes.length > 0, text);
  for (const line of scopes) {
    assert.match(line, /Maintained by roc-syntax-mcp\./, line);
  }
});

test("a plugin is listed under the maintainer it names, or as naming nobody", async () => {
  const named = plugin("ray-named", ray({ name: "ray-named" }, { maintainer: "lukewilliamboswell" }));
  const silent = plugin("ray-silent", ray({ name: "ray-silent" }));
  const { text } = await session({ argv: [`--plugin=${named}`, `--plugin=${silent}`] });
  assert.match(text, /- \*\*ray-named\*\*:.*Maintained by lukewilliamboswell\./);
  assert.match(text, /- \*\*ray-silent\*\*:.*Maintainer not named\./);
});

// A host update must never make an installed plugin invalid. Thus the server
// reports a different compiler, and serves the plugin.
test("a plugin built against another nightly is reported, not refused", async () => {
  const dir = plugin("ray-stale", ray({ name: "ray-stale" }, { compiler: "nightly-1999-01-01-abc" }));
  const { text } = await session({ argv: [`--plugin=${dir}`] });
  assert.match(text, /- \*\*ray-stale\*\*:.*Built against nightly-1999-01-01-abc, which this server does not bundle\./);
});

test("a malformed manifest skips that plugin and keeps the rest", async () => {
  const good = plugin("ray-good", ray({ name: "ray-good" }));
  const bad = write(path.join(tmp, "ray-bad"), { "plugin.json": "{ not json" });
  const { text, stderr } = await session({ argv: [`--plugin=${bad}`, `--plugin=${good}`] });
  assert.match(text, /- \*\*ray-good\*\*/);
  assert.doesNotMatch(text, /ray-bad.*A graphics platform/);
  // The two places where an operator looks. The answer itself proves that a
  // broken plugin did not stop the server.
  assert.match(stderr, /plugin .*ray-bad \(--plugin=\)/);
  assert.match(text, /Plugin .*ray-bad \(--plugin=\)/);
});

test("a plugin claiming a name this server owns is rejected", async () => {
  const dir = plugin("ray-reserved", ray({ name: "builtin" }));
  const { text } = await session({ argv: [`--plugin=${dir}`] });
  assert.match(text, /Plugin .*ray-reserved.*builtin is a reserved name/);
  assert.match(text, /- \*\*builtin\*\*: The standard library\./);
});

test("the second plugin to claim a scope name loses it", async () => {
  const first = plugin("ray-first", ray({ description: "The first one." }));
  const second = plugin("ray-second", ray({ description: "The second one." }));
  const { text } = await session({ argv: [`--plugin=${first}`, `--plugin=${second}`] });
  assert.match(text, /- \*\*roc-ray\*\*: The first one\./);
  assert.match(text, /Plugin .*ray-second.*roc-ray is already loaded/);
});

// The name of a package selects its page, as the name of a scope selects its
// corpus. Thus a package plugin cannot replace a page that this server ships.
test("a package plugin claiming a documented package's name loses it", async () => {
  const dir = packagePlugin("random-again");
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8"));
  manifest.corpora[0].name = "roc-random";
  fs.writeFileSync(path.join(dir, "plugin.json"), JSON.stringify(manifest));
  const { text } = await session({ argv: [`--plugin=${dir}`] });
  assert.match(text, /Plugin .*random-again.*roc-random is already loaded/);
  assert.match(text, /roc-random\*\*: The roc-random package/);
});

// -----------------------------------------------------------------------------
// What a declared platform is evidence of
// -----------------------------------------------------------------------------

/** An app that pins a platform that this server bundles, so that detection finds a platform. */
const CLI_APP = `app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst" }

import pf.Stdout
`;

const RAY_DIR = path.join(ROOT, "plugins", "roc-ray");

// The first call that a model makes, in a new project. The server does not
// choose for the caller. The list lets the caller choose, so it must show the
// platform of each plugin next to the bundled platforms.
test("the overview lists every platform to choose from where none is chosen", async () => {
  const root = write(path.join(tmp, "no-header-overview"), { "README.md": "No app header here.\n" });
  const { text } = await session({
    argv: [`--plugin=${RAY_DIR}`],
    cwd: root,
    calls: [{ name: "get_roc_syntax" }],
  });
  assert.match(text, /No Roc code here imports a platform, so none is chosen yet\./);
  assert.match(text, /- roc-ray: games, graphics and sound/);
  assert.match(text, /- basic-cli: command-line programs and scripts/);
  assert.match(text, /Pass the one you are writing for as `scope`/);
});

// An installed corpus tells what is available, never what somebody writes. The
// working set comes only from the app header and the `scope` of the caller.
test("an installed platform is not read until it is chosen", async () => {
  const root = write(path.join(tmp, "no-header"), { "README.md": "No app header here.\n" });
  const { texts } = await session({
    argv: [`--plugin=${RAY_DIR}`],
    cwd: root,
    calls: [
      { name: "list_roc_index", args: { kind: "scopes" } },
      { name: "get_roc_syntax", args: { topic: "how do I structure a game" } },
      { name: "get_roc_syntax", args: { topic: "how do I structure a game", scope: "roc-ray" } },
    ],
  });
  assert.match(texts[0], /Omitting `scope` reads language \+ builtin\./);
  assert.match(texts[1], /No topic matched/);
  assert.match(texts[2], /^## ray_game/m);
});

// `tools/list` names the topics of an installed platform. If the server refused
// the name, it would advertise a call and then answer "no topic matched".
test("a topic answers to its own name from any corpus", async () => {
  const root = write(path.join(tmp, "no-header-named"), { "README.md": "No app header here.\n" });
  const { texts } = await session({
    argv: [`--plugin=${RAY_DIR}`],
    cwd: root,
    calls: [
      { name: "get_roc_syntax", args: { topic: "ray_project" } },
      { name: "get_roc_syntax", args: { topic: "ray_project", scope: "language" } },
    ],
  });
  assert.match(texts[0], /^## ray_project/m);
  assert.match(texts[0], /A roc-ray topic, which this workspace has not chosen\./);
  // If the caller sets a scope, the search stays in that scope.
  assert.match(texts[1], /No topic matched "ray_project" in scope=language/);
});

// The app header decides the working set. An installed plugin does not change it.
test("a detected platform is the one in the working set", async () => {
  const root = write(path.join(tmp, "header-cli"), { "main.roc": CLI_APP });
  const { text } = await session({ argv: [`--plugin=${RAY_DIR}`], cwd: root });
  assert.match(text, /Omitting `scope` reads language \+ builtin \+ basic-cli\./);
});

// A path outside the plugin reads a file that the operator did not install.
test("a manifest reaching outside its own directory is rejected", async () => {
  const dir = plugin("ray-escape", ray({ name: "ray-escape", overview: "../../../etc/passwd" }));
  const { text } = await session({ argv: [`--plugin=${dir}`] });
  assert.match(text, /Plugin .*ray-escape.*is outside the plugin/);
  assert.doesNotMatch(text, /- \*\*ray-escape\*\*/);
});

// The installed plugins apply to every workspace. If the server exited here,
// one stale entry would stop it in every workspace. Thus the server serves the
// other plugins, and reports the missing plugin where an operator and a model
// look.
test("a declaration that resolves to nothing is reported, and the rest is served", async () => {
  const dir = plugin("ray-beside-missing", ray({ name: "ray-beside" }));
  const { texts, stderr, code } = await session({
    argv: ["--plugin=@roc-syntax/not-installed", `--plugin=${dir}`],
    calls: [
      { name: "get_roc_syntax", args: {} },
      { name: "get_roc_syntax", args: {} },
      { name: "list_roc_index", args: { kind: "scopes" } },
    ],
  });
  assert.notEqual(code, 1);
  assert.match(stderr, /plugin @roc-syntax\/not-installed \(--plugin=\): does not resolve/);
  assert.match(texts[0], /@roc-syntax\/not-installed \(--plugin=\): does not resolve/);
  assert.doesNotMatch(texts[1], /not-installed/);
  assert.match(texts[2], /- \*\*ray-beside\*\*: A graphics platform\./);
  assert.match(texts[2], /Plugin @roc-syntax\/not-installed \(--plugin=\): does not resolve/);
});

// -----------------------------------------------------------------------------
// A namespace no provider serves
// -----------------------------------------------------------------------------

/**
 * A platform that pins a release of roc-lang/http that nothing on this host
 * serves. The API of the platform uses types from that package.
 *
 * No corpus in this repo pins a package that it cannot get. Without a plugin,
 * only a direct call to `formatPackageNote` as a pure function reaches this
 * state.
 */
const UNSERVED_RELEASE = release("lukewilliamboswell/roc-ray", "0.7.0", "RayUnserved");

function unservedPlugin(): string {
  const root = path.join(tmp, "ray-unserved");
  write(root, {
    "plugin.json": JSON.stringify({
      schema: 1,
      corpora: [{ name: "ray-unserved", release: UNSERVED_RELEASE, description: "A graphics platform." }],
    }),
    "index.json": indexed({
      [UNSERVED_RELEASE]: {
        "main.roc": `platform "ray"
    exposes [Draw]
    packages {
        http: "https://github.com/roc-lang/http/releases/download/9.9.9/AAAA.tar.br",
    }
`,
        "Draw.roc": "import http.Request\n\nDraw := [].{\n    circle! : F32 => {}\n}\n",
      },
    }),
  });
  return root;
}

// Each tool that adds trailing notes to its answer shows the note. A lookup
// miss and an empty search are different tools and different code paths, and
// both must show it.
test("a namespace nothing serves is reported by every tool that comes up empty", async () => {
  const dir = unservedPlugin();
  const { texts } = await session({
    argv: [`--plugin=${dir}`, "--platform=ray-unserved"],
    calls: [
      { name: "search_symbols", args: { query: ["Request.from_method"] } },
      { name: "search_symbols", args: { query: ["Zzz -> Qqq"] } },
      { name: "search", args: { query: "qqqzzzxyw" } },
      { name: "get_roc_module", args: { module: "Zzz" } },
    ],
  });
  for (const text of texts) {
    assert.match(text, /No provider serves roc-lang\/http\./, text);
    assert.match(text, /ray-unserved 0\.7\.0 requires 9\.9\.9; roc-syntax-mcp serves 1\.0\.0\./);
    assert.match(text, /Install a package plugin at 9\.9\.9, or run this server with --force=roc-lang\/http to read 1\.0\.0 anyway\./);
  }
});

// The other half of the note above. The boundary test uses the corpus and can
// report a crossing that is not real. An operator who checked can force the
// namespace. Then every signature that they read must show the force.
test("a forced namespace is served, and every item says what it was forced over", async () => {
  const dir = unservedPlugin();
  const { texts } = await session({
    argv: [`--plugin=${dir}`, "--platform=ray-unserved", "--force=roc-lang/http"],
    calls: [
      { name: "search_symbols", args: { query: ["Request.with_body"] } },
      { name: "search", args: { query: "with_body" } },
    ],
  });
  for (const text of texts) {
    assert.doesNotMatch(text, /No provider serves/, text);
    assert.match(text, /\(http 1\.0\.0, forced over 9\.9\.9\)/, text);
  }
});

// An id that names no namespace changes no resolution, with no sign of the
// cause. But the operator wrote the id to change a resolution.
test("a forced id that is not a repo path is reported where an operator looks", async () => {
  const { text, stderr } = await session({
    argv: ["--force=not-a-repo-path"],
    calls: [{ name: "list_roc_index", args: { kind: "scopes" } }],
  });
  assert.match(text, /Forced not-a-repo-path \(--force=\): not a repo path/);
  assert.match(stderr, /roc-syntax: force not-a-repo-path \(--force=\)/);
});

// -----------------------------------------------------------------------------
// A package only the app pins
// -----------------------------------------------------------------------------

// A package plugin ships a namespace, an app header pins it, and no platform
// pins it. The server must read the app header, because the platform header
// does not name this package.
test("a package plugin serves a namespace only the app's own header pins", async () => {
  const dir = path.join(tmp, "json-plugin");
  write(dir, {
    "plugin.json": JSON.stringify({
      schema: 1,
      corpora: [{ release: release("example/json", "2.1.0", "JsonPlugin") }],
    }),
    "index.json": indexed({
      [release("example/json", "2.1.0", "JsonPlugin")]: {
        "main.roc": "package [Json] {}\n",
        "Json.roc": "Json := [].{\n    decode! : Str => Str\n}\n",
      },
    }),
  });

  const workspace = path.join(tmp, "json-app");
  write(workspace, {
    "main.roc": `app [Context, program] {
\tpf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.16.0/AAAA.tar.zst",
\tjson: "https://github.com/example/json/releases/download/2.1.0/BBBB.tar.br",
}

import pf.Server
`,
  });

  const { texts, stderr } = await session({
    argv: [`--plugin=${dir}`],
    cwd: workspace,
    calls: [
      { name: "list_roc_index", args: { kind: "scopes" } },
      { name: "search_symbols", args: { query: ["Json.decode!"] } },
    ],
  });
  assert.match(stderr, /Also pinned: example\/json 2\.1\.0 \(served by json\)/);
  assert.match(texts[0], /Also pinned: example\/json 2\.1\.0 \(served by json\)/);
  assert.match(texts[1], /decode!/, texts[1]);
  assert.match(texts[1], /json 2\.1\.0/, "the item did not name the release it is");
});

// The other half of the same rule. An answer that finds items is not a miss,
// so it does not show the note.
test("an answer that found something does not carry the unserved note", async () => {
  const dir = unservedPlugin();
  const { texts } = await session({
    argv: [`--plugin=${dir}`, "--platform=ray-unserved"],
    calls: [
      { name: "search_symbols", args: { query: ["Str.trim"] } },
      { name: "search", args: { query: "trim" } },
    ],
  });
  for (const text of texts) assert.doesNotMatch(text, /No provider serves/);
});

// -----------------------------------------------------------------------------
// A package plugin
// -----------------------------------------------------------------------------

// A documented package is one tree, which the server reads one time as the
// package that the app pins. If the package were also a scope, a pinned lookup
// would return each item twice.
test("a documented package answers a pinned lookup once", async () => {
  const dir = packagePlugin("weave-once");
  const root = write(path.join(tmp, "weave-app"), {
    "main.roc": `app [main!] {\n\tpf: platform "${CLI_PIN}",\n\tweave: "${WEAVE_PIN}",\n}\n`,
  });
  const { texts, stderr } = await session({
    argv: [`--plugin=${dir}`],
    cwd: root,
    calls: [{ name: "search_symbols", args: { query: ["Opt.flag"] } }],
  });
  assert.equal(texts[0].match(/^## Opt\.flag/gm)?.length, 1, texts[0]);
  assert.match(stderr, /someone\/weave 0\.8\.0 \(served by weave\)/);
});

// A pin in the app header shows that the app uses the package, as a platform
// pin does. An installed plugin alone adds nothing to the space. The topics of
// the package answer in both cases, because a caller finds the package by them.
test("a pinned package is read with the builtins, an unpinned one is named on a miss", async () => {
  const dir = packagePlugin("weave-set");
  const pinned = write(path.join(tmp, "weave-pinned"), {
    "main.roc": `app [main!] {\n\tpf: platform "${CLI_PIN}",\n\tweave: "${WEAVE_PIN}",\n}\n`,
  });
  const bare = write(path.join(tmp, "weave-bare"), {
    "main.roc": `app [main!] { pf: platform "${CLI_PIN}" }\n`,
  });
  const calls = [
    { name: "list_roc_index", args: { kind: "scopes" } },
    { name: "get_roc_syntax", args: { topic: "how do I read command line arguments" } },
    { name: "search_symbols", args: { query: ["Opt.flag"] } },
    { name: "get_roc_module", args: { module: "Hidden" } },
  ];
  const on = await session({ argv: [`--plugin=${dir}`], cwd: pinned, calls });
  assert.match(on.texts[0], /Omitting `scope` reads language \+ builtin \+ basic-cli\./);
  assert.match(on.texts[0], /weave\*\*: An argument parser\. Release 0\.8\.0\. Pinned by this app\./);
  assert.match(on.texts[1], /^## weave_cli/m);
  assert.match(on.texts[2], /^## Opt\.flag \(weave 0\.8\.0\)/m);
  // No app can import a module that the header of the package does not expose.
  assert.match(on.texts[3], /From weave 0\.8\.0\. This module is the host ABI boundary; an application must not call it\./);

  const off = await session({ argv: [`--plugin=${dir}`], cwd: bare, calls });
  assert.match(off.texts[0], /Omitting `scope` reads language \+ builtin \+ basic-cli\./);
  assert.match(off.texts[0], /weave\*\*: An argument parser\. Release 0\.8\.0\. Not pinned by this app\./);
  assert.match(off.texts[1], /^## weave_cli/m);
  assert.match(off.texts[1], /From weave 0\.8\.0, a package this app does not pin\./);
  assert.match(off.texts[2], /`Opt\.flag` is in weave 0\.8\.0, a package this app does not pin:\n {4}Opt\.flag : Str -> Bool\n/);
});

// The `Random` of basic-cli and the `Random` of a package are two modules that
// an app imports through two aliases. A name that both declare gives two
// answers, each with its origin.
test("a name two namespaces declare is answered with both, and says so", async () => {
  const dir = write(path.join(tmp, "rand-fork"), {
    "plugin.json": JSON.stringify({
      schema: 1,
      corpora: [{ name: "rand-fork", release: release("kili-ilo/roc-random", "0.9.2", "RandFork") }],
    }),
    "index.json": indexed({
      [release("kili-ilo/roc-random", "0.9.2", "RandFork")]: {
        "main.roc": "package [Random] {}\n",
        "Random.roc": "Random := [].{\n    seed_u64! : () => U64\n    only_here : U8\n}\n",
      },
    }),
  });
  const rand =
    "https://github.com/kili-ilo/roc-random/releases/download/0.9.2/2ZXLX8WRqrosGu1V3VL5aXqgtfTRvJmjFPx8a26ecVmc.tar.zst";
  const root = write(path.join(tmp, "rand-fork-app"), {
    "main.roc": `app [main!] {\n    pf: platform "${CLI_PIN}",\n    rand: "${rand}",\n}\n\nmain! = |_args| Ok({})\n`,
  });
  const { texts } = await session({
    argv: [`--plugin=${dir}`],
    cwd: root,
    calls: [
      { name: "search_symbols", args: { query: ["Random.seed_u64!"] } },
      { name: "search_symbols", args: { query: ["seed_u64!"] } },
      { name: "search_symbols", args: { query: ["Random.only_here"] } },
    ],
  });
  for (const text of texts.slice(0, 2)) {
    assert.match(text, /`Random\.seed_u64!` is declared by 2 modules/);
    assert.match(text, /^## Random\.seed_u64! \(basic-cli 0\.24\.0\)/m);
    assert.match(text, /^## Random\.seed_u64! \(roc-random 0\.9\.2\)/m);
  }
  // One declaration, no note.
  assert.doesNotMatch(texts[2], /declared by/);
});

// A package is not a scope. Its name selects its page, and no tool offers it
// as a `scope` value.
test("a package plugin's page answers to its name, and it adds no scope", async () => {
  const dir = packagePlugin("weave-page");
  const root = write(path.join(tmp, "weave-page-app"), { "README.md": "No app header.\n" });
  const { texts } = await session({
    argv: [`--plugin=${dir}`],
    cwd: root,
    calls: [
      { name: "get_roc_syntax", args: { topic: "weave" } },
      { name: "get_roc_syntax", args: { topic: "someone/weave" } },
      { name: "get_roc_syntax", args: {} },
    ],
  });
  // The package has no overview page, so the server shows the description.
  assert.match(texts[0], /^# weave 0\.8\.0\n\nAn argument parser\./);
  assert.match(texts[0], /^Topics: weave_cli\.$/m);
  assert.equal(texts[1], texts[0]);
  assert.match(texts[2], /Packages documented here: .*weave \(An argument parser\.\)/);
});

// -----------------------------------------------------------------------------
// A platform hosted somewhere other than a GitHub release
// -----------------------------------------------------------------------------

/** Two bundles under one directory. `.invalid` never resolves, so nothing is fetched. */
const PAINT = "https://roc.bundles.invalid/paint/PaintBundLeNumberFirst123456789abcde.tar.br";
const PAINT_NEXT = "https://roc.bundles.invalid/paint/SecondPaintBundLe123456789abcdefgh.tar.br";

// A header can pin any URL that `roc deps` fetches, so detection must
// recognize such a URL. Its version is a hash, which has no order. Thus the
// note tells only whether the pin is the documented bundle.
test("a self-hosted platform is detected by its URL, and another bundle is named as different", async () => {
  const dir = path.join(tmp, "paint-plugin");
  write(dir, {
    "plugin.json": JSON.stringify({ schema: 1, corpora: [{ release: PAINT, description: "A paint platform." }] }),
    "index.json": indexed({
      [PAINT]: { "main.roc": 'platform ""\n    exposes [Brush]\n    packages {}\n', "Brush.roc": "Brush := [].{\n    dab! : U8 => {}\n}\n" },
    }),
  });
  // The first call that reads the corpus of the platform shows the mismatch note.

  const call = (cwd: string) =>
    session({
      argv: [`--plugin=${dir}`],
      cwd,
      calls: [
        { name: "get_roc_syntax" },
        { name: "search_symbols", args: { query: ["Brush.dab!"] } },
        { name: "search", args: { query: "dab", scope: "paint" } },
      ],
    });
  const same = await call(write(path.join(tmp, "paint-same"), { "main.roc": `app [main!] { pf: platform "${PAINT}" }\n` }));
  assert.match(same.texts[0], /Platform detected: paint PaintBundLeN/);
  assert.match(same.texts[1], /^## Brush\.dab!/m);
  assert.doesNotMatch(same.texts.join("\n"), /other than the one this server documents/);

  const next = await call(write(path.join(tmp, "paint-next"), { "main.roc": `app [main!] { pf: platform "${PAINT_NEXT}" }\n` }));
  assert.match(next.texts[0], /Platform detected: paint PaintBundLeN \(from main\.roc, pins SecondPaintB\)/);
  assert.match(next.texts.join("\n"), /pins a paint bundle \(SecondPaintB\) other than the one this server documents \(PaintBundLeN\)/);
});
