// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Tests for what an install of this package costs a consumer, and which files
// the consumer gets.
//
// The package ships in two ways, and no other test covers the second one:
// 1. `npm i roc-syntax-mcp` gets a built tarball.
// 2. `bun i -g git:...` gets the repository itself, and no build runs.
//
// Both installers block the install scripts of a package until the user passes
// a flag. For a git dependency, even that flag does not make a build run.
// `docs/design/packaging.md` has the output of each combination. Thus this
// package must need no step before it starts.
//
// The children under `plugins/` ship separately and are part of neither path.

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { init, staticChecks } from "./plugin_cli.ts";
import { indexText } from "./release.ts";
// @ts-expect-error a script, with no types
import { registryFiles } from "../scripts/registry-files.mjs";

const ROOT = path.join(import.meta.dirname, "..");
const STRIPS_TYPES = Number(process.versions.node.split(".")[0]) >= 23;
const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf-8"));

/** Neither installer runs these scripts unless the user asks, so a package that needs one does not work after an install. */
const INSTALL_HOOKS = ["preinstall", "install", "postinstall", "prepare"];

/**
 * The scripts that make npm build a git dependency before it installs it, from
 * `pacote/lib/git.js`:
 *
 *     if (!mani.workspaces && (!scripts || !(scripts.postinstall ||
 *         scripts.build || scripts.preinstall || scripts.install ||
 *         scripts.prepack || scripts.prepare))) { return }
 *
 * That path runs `npm install` in the clone. With install scripts blocked, it
 * leaves a link to a temp directory, which npm then deletes. If the package
 * declares any of these scripts, or `workspaces`, `npm i -g git:...` breaks for
 * every user.
 */
const PREPARE_TRIGGERS = ["postinstall", "build", "preinstall", "install", "prepack", "prepare"];

/** Everything the server opens at run time, relative to the package root. */
const RUNTIME_READS = [
  "bin/roc-syntax-mcp.js",
  "src/index.ts",
  "src/server.ts",
  "corpus/language/Builtin.roc",
  "corpus/language/examples/all_roc_syntax.roc",
  "corpus/platforms/basic-cli/plugin.json",
  "scripts/check-platform-examples.sh",
  "scripts/check-roc-check.mjs",
  "scripts/tree.mjs",
  "corpus/language/UPSTREAM",
];

/** The paths that `npm pack` would ship from `dir`. A git install copies the same paths. */
function packed(dir = ROOT): string[] {
  const r = spawnSync("npm", ["pack", "--dry-run", "--json", "--ignore-scripts"], { cwd: dir, encoding: "utf-8" });
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout)[0].files.map((f: { path: string }) => f.path);
}

// typescript and @types/node are 25 MB of compiler that a consumer never runs.
test("only what the server imports is a runtime dependency", () => {
  const deps = Object.keys(pkg.dependencies);
  assert.deepEqual(deps.sort(), ["@modelcontextprotocol/server", "zod"]);
});

// The build is part of publishing, not of installing. `prepublishOnly` is the
// only hook that runs on neither an install nor a pack. Thus the build runs
// from that hook, and the script that it calls is not named `build`.
test("nothing about this package sends an installer looking for a build", () => {
  assert.deepEqual(
    PREPARE_TRIGGERS.filter((h) => pkg.scripts[h]),
    []
  );
  assert.equal(pkg.workspaces, undefined);
  assert.equal(pkg.scripts.prepublishOnly, "npm run build:ts && node scripts/registry-files.mjs --check");
});

test("every file the server reads is in the tarball, and no test or child is", () => {
  const files = packed();
  assert.deepEqual(
    RUNTIME_READS.filter((rel) => !files.some((f) => f === rel || f.startsWith(`${rel}/`))),
    []
  );
  assert.deepEqual(files.filter((f) => /\.test\./.test(f)), []);
  assert.deepEqual(files.filter((f) => f.startsWith("plugins/") || f.startsWith("src/testdata/")), []);
});

// One `files` list serves both installs, and the registry list comes from it.
// The test packs a copy, so it changes no file in the repository. An empty
// file replaces each build output, because the test checks only the list.
test("the npm tarball ships the build and no source", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roc-registry-"));
  try {
    const built = (rel: string) => rel.replace(/^src\/(.*)\.ts$/, "dist/$1.js");
    const stand = [...RUNTIME_READS.map(built), "src/index.ts", "tsconfig.json", "dist/testdata/isolate.js", "dist/server.test.js"];
    for (const rel of stand) {
      const from = path.join(ROOT, rel);
      const to = path.join(tmp, rel);
      if (fs.existsSync(from) && fs.statSync(from).isDirectory()) fs.cpSync(from, to, { recursive: true });
      else {
        fs.mkdirSync(path.dirname(to), { recursive: true });
        fs.writeFileSync(to, "");
      }
    }
    fs.writeFileSync(path.join(tmp, "package.json"), JSON.stringify({ ...pkg, files: registryFiles(pkg.files) }));
    const files = packed(tmp);
    assert.deepEqual(files.filter((f) => f.startsWith("src/") || f === "tsconfig.json"), []);
    assert.deepEqual(files.filter((f) => f.startsWith("dist/testdata/") || /\.test\./.test(f)), []);
    assert.deepEqual(
      RUNTIME_READS.map(built).filter((rel) => !files.some((f) => f === rel || f.startsWith(`${rel}/`))),
      []
    );
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// `plugin validate` runs two check scripts, which import the server modules.
// An npm install has only dist/, and a git install has only src/ and no tsx.
// The test runs under node_modules/, as an installed package does, because
// Node strips no types there by itself. It runs in a child process, so that
// the type stripper does not load into this process.
test("a gate script loads the build where there is no source, and the source where there is", () => {
  const top = fs.mkdtempSync(path.join(os.tmpdir(), "roc-tree-"));
  const tmp = path.join(top, "node_modules", "roc-syntax-mcp");
  fs.mkdirSync(tmp, { recursive: true });
  const tree = () =>
    spawnSync(
      process.execPath,
      ["--input-type=module", "-e", 'const { load } = await import("./scripts/tree.mjs"); console.log((await load("scopes")).tree);'],
      { cwd: tmp, encoding: "utf-8" }
    );
  try {
    for (const rel of ["scripts/tree.mjs", "bin/strip-types.js"]) {
      fs.mkdirSync(path.dirname(path.join(tmp, rel)), { recursive: true });
      fs.copyFileSync(path.join(ROOT, rel), path.join(tmp, rel));
    }
    fs.writeFileSync(path.join(tmp, "package.json"), '{ "type": "module" }\n');
    fs.mkdirSync(path.join(tmp, "dist"));
    fs.writeFileSync(path.join(tmp, "dist", "scopes.js"), 'export const tree = "dist";\n');
    const npm = tree();
    assert.equal(npm.stdout.trim(), "dist", npm.stderr);

    if (!STRIPS_TYPES) return;
    fs.mkdirSync(path.join(tmp, "src"));
    fs.writeFileSync(path.join(tmp, "src", "index.ts"), "");
    fs.writeFileSync(path.join(tmp, "src", "scopes.ts"), 'export const tree: string = "src";\n');
    const git = tree();
    assert.equal(git.stdout.trim(), "src", git.stderr);
  } finally {
    fs.rmSync(top, { recursive: true, force: true });
  }
});

// The `.ts` specifiers, the one expanded parameter property and
// `bin/strip-types.js` exist for this case. With no dist to import, the bin
// runs the source.
//
// The test copies the package under a node_modules/, because an installed
// package is there and Node does not strip types there by itself. The test
// uses a copy, not the tree, because dist/ exists while this suite runs.
test("the bin runs from source, installed, when no build left a dist", { skip: !STRIPS_TYPES && "needs Node 23+" }, () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roc-nodist-"));
  const dir = path.join(tmp, "node_modules", "roc-syntax-mcp");
  try {
    for (const rel of ["src", "bin"]) {
      fs.cpSync(path.join(ROOT, rel), path.join(dir, rel), {
        recursive: true,
        filter: (from) => !from.includes("testdata"),
      });
    }
    // Symlinks keep the copy small. The server reads these paths whole.
    for (const rel of ["package.json", "node_modules", "corpus"]) {
      fs.symlinkSync(path.join(ROOT, rel), path.join(dir, rel));
    }
    assert.ok(!fs.existsSync(path.join(dir, "dist")));
    const bin = path.join(dir, "bin", "roc-syntax-mcp.js");
    const inspect = spawnSync(process.execPath, [bin, "plugin", "inspect", path.join(ROOT, "corpus", "packages", "http")], {
      encoding: "utf-8",
    });
    assert.equal(inspect.status, 0, inspect.stderr);
    assert.match(inspect.stdout, /manifest\s+v1/);

    // Then the server itself, which is the part that a client starts. stderr
    // has only the line of the server, because an experimental warning would
    // go into the log of a user.
    const server = spawnSync(process.execPath, [bin], {
      encoding: "utf-8",
      input:
        JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "t", version: "1" } },
        }) + "\n",
      timeout: 60_000,
    });
    assert.match(server.stdout, /"serverInfo":\{"name":"roc-syntax"/);
    assert.equal(JSON.parse(server.stdout.split("\n")[0]).result.serverInfo.version, pkg.version);
    assert.equal(server.stderr.trim(), "roc-syntax-mcp: serving MCP over stdio");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

/** The rules that a directory under `plugins/` must satisfy before it can be published. */
function assertPublishable(dir: string, label: string): void {
  const child = JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf-8"));
  assert.ok(child.name && child.version, `${label} needs a name and a version`);
  assert.deepEqual(
    INSTALL_HOOKS.filter((h) => child.scripts?.[h]),
    [],
    `${label} would have to run something on install`
  );
  const failed = staticChecks(dir).filter((c) => c.status === "fail");
  assert.deepEqual(failed.map((c) => `${c.name}: ${c.detail}`), [], label);
}

// The same rules run on a new scaffold, because each child starts as what
// `init` writes.
test("a scaffolded child is publishable as it stands", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "roc-child-"));
  try {
    init(dir, { name: "roc-ray", repo: "you/roc-ray", version: "0.7.0" });
    // Do what `plugin index` does after the author names a real release. The
    // scaffold has no source, and the index is the only file that it lacks.

    const release = JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8")).corpora[0].release;
    const src = fs.mkdtempSync(path.join(os.tmpdir(), "roc-child-release-"));
    fs.writeFileSync(path.join(src, "main.roc"), 'platform "roc-ray"\n    exposes [RocRay]\n    packages {}\n');
    fs.writeFileSync(path.join(src, "RocRay.roc"), "RocRay := [].{\n    greet! : Str => {}\n}\n");
    fs.writeFileSync(path.join(dir, "index.json"), indexText([{ url: release, dir: src }]));
    fs.rmSync(src, { recursive: true, force: true });
    assertPublishable(dir, "the plugin init scaffold");
    const child = JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf-8"));
    assert.equal(child.name, "@you/roc-ray");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("every child under plugins/ is publishable on its own", () => {
  const children = fs
    .readdirSync(path.join(ROOT, "plugins"), { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name);
  for (const name of children) assertPublishable(path.join(ROOT, "plugins", name), `plugins/${name}`);
});
