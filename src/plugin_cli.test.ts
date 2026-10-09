// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Tests for the plugin CLI: what `init` writes, what `validate` refuses, what
// `inspect` reports, and what `doctor` says about a configured plugin set.
//
// Every test here runs offline. The `validate` checks that need a compiler are
// `scripts/check-platform-examples.sh` and `scripts/check-roc-check.mjs`. This
// repo already runs both scripts on its own platforms.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  add,
  budgetCheck,
  detectInstall,
  doctor,
  init,
  inspect,
  isPathSpec,
  isRegistrySpec,
  newestOf,
  lastLine,
  list,
  main,
  quoteForCmd,
  remove,
  snippets,
  staticChecks,
  uninstall,
  update,
  upgrade,
  upgradeServer,
} from "./plugin_cli.ts";
import type { GlobalRoot, Install } from "./plugin_cli.ts";
import { declarations, installedPlugins } from "./plugins.ts";
import { indexText } from "./release.ts";
import { BARE_ENV } from "./testdata/isolate.ts";
import { scaffold } from "./roc_check.ts";
import { loadCatalog } from "./scopes.ts";

const ROOT = path.join(import.meta.dirname, "..");
const TSX_LOADER = import.meta.resolve("tsx/esm");

let tmp: string;
before(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roc-plugin-cli-"));
});
after(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

/** A plugin directory that holds only the given files. */
function plugin(name: string, files: Record<string, unknown>): string {
  const dir = path.join(tmp, name);
  for (const [rel, content] of Object.entries(files)) {
    const file = path.join(dir, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, typeof content === "string" ? content : JSON.stringify(content));
  }
  return dir;
}

/** The check with that name, so that no test depends on line order. */
function check(dir: string, name: string) {
  const hit = staticChecks(dir).find((c) => c.name.startsWith(name));
  assert.ok(hit, `no check named ${name} in ${staticChecks(dir).map((c) => c.name).join(", ")}`);
  return hit;
}

const PLATFORM = "platform \"ray\"\n    exposes [Draw]\n    packages {}\n";
const DRAW = "Draw := [].{\n    circle! : F32 => {}\n}\n";

/** A release URL with a fake hash. An index uses the hash only as a name. */
const release = (repo: string, version: string, hash: string) =>
  `https://github.com/${repo}/releases/download/${version}/${hash.padEnd(24, "0")}.tar.zst`;
const RAY = release("x/roc-ray", "0.7.0", "RayRelease");
const HTTP_FORK = release("roc-lang/http", "9.9.9", "HttpFork");

/** The index.json that `plugin index` writes for these releases, from their sources. */
function indexed(releases: Record<string, Record<string, string>>): string {
  return indexText(
    Object.entries(releases).map(([url, files]) => {
      const dir = fs.mkdtempSync(path.join(tmp, "release-"));
      for (const [name, content] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), content);
      return { url, dir };
    })
  );
}

/**
 * The smallest manifest for a platform scope, with the corpus that it names.
 *
 * The directory name comes from the keys of `over` and `files`. Two fixtures
 * that differ only in the contents of a file need `tag` to get different
 * directories.
 */
function ray(over: Record<string, unknown> = {}, files: Record<string, unknown> = {}, tag = "") {
  // The maintainer belongs to the plugin. Every other field belongs to the corpus.
  const { maintainer, ...corpus } = over;
  return plugin(`ray-${Object.keys(over).join("-") || "plain"}-${Object.keys(files).join("-")}${tag}`, {
    "plugin.json": {
      schema: 1,
      ...(maintainer ? { maintainer } : {}),
      corpora: [{ release: RAY, description: "A graphics platform.", ...corpus }],
    },
    "index.json": indexed({ [RAY]: { "main.roc": PLATFORM, "Draw.roc": DRAW } }),
    ...files,
  });
}

// -----------------------------------------------------------------------------
// init
// -----------------------------------------------------------------------------

// The skeleton is the first thing that an author sees, so this host must accept
// it. If a skeleton file fails validation, every author gets the defect.
//
// The only exception is the index. A skeleton has no release to read, so the
// only failure is the `index` check, which names the command that writes it.
test("what init writes fails only for want of the index it cannot write", () => {
  const dir = path.join(tmp, "fresh");
  assert.ok(!init(dir, {}).some((c) => c.status === "fail"));
  const bad = staticChecks(dir).filter((c) => c.status === "fail");
  assert.deepEqual(bad.map((c) => c.name), ["index"], bad.map((c) => `${c.name}: ${c.detail}`).join("\n"));
  assert.match(bad[0].detail!, /Run: roc-syntax-mcp plugin index /);
  // `init` writes no release source, because `plugin index` reads it from the release.
  assert.ok(!fs.existsSync(path.join(dir, "platform")));
});

// The overview of the skeleton shows a snippet. The app that `init` writes must
// contain that snippet, or the snippet check fails on every new plugin.
test("init's overview snippets are in the app init writes to compile them", () => {
  const dir = path.join(tmp, "snippets-of-init");
  init(dir, {});
  const page = fs.readFileSync(path.join(dir, "overview.md"), "utf-8");
  assert.equal(snippets(page).length, 1);
  assert.equal(check(dir, "snippets").status, "ok");
});

// A skeleton with no topic entry tells authors that a `checks` directory is
// enough for a program. Then the check scripts compile the program, but the
// server does not serve it.
test("init declares the topic it writes", () => {
  const dir = path.join(tmp, "topical");
  init(dir, {});
  const { topics } = JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8")).corpora[0];
  assert.equal(topics.length, 1);
  assert.ok(fs.existsSync(path.join(dir, topics[0].file)));
  assert.equal(check(dir, "topics").status, "ok");
  assert.match(check(dir, "topics").detail!, /1 served by name/);
});

// The repo that an app header pins and the npm name that a curator publishes
// under are different. If `init` used the repo owner as the npm scope, the
// author could not publish to that name.
test("the npm name is the author's, and the repo stays the platform's", () => {
  const dir = path.join(tmp, "named");
  init(dir, { name: "roc-ray", repo: "lukewilliamboswell/roc-ray", package: "@you/roc-ray" });
  const pkg = JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf-8"));
  assert.equal(pkg.name, "@you/roc-ray");
  const [corpus] = JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8")).corpora;
  // Detection matches the repo in the release URL, and the corpus name is the repo name.
  assert.match(corpus.release, /^https:\/\/github\.com\/lukewilliamboswell\/roc-ray\/releases\//);
  assert.equal(corpus.name, undefined);

  // Without `--package`, the npm scope falls back to the repo owner. An author
  // who documents their own platform gives `--repo` one time for both.
  const own = path.join(tmp, "unnamed");
  init(own, { name: "roc-ray", repo: "lukewilliamboswell/roc-ray" });
  assert.equal(
    JSON.parse(fs.readFileSync(path.join(own, "package.json"), "utf-8")).name,
    "@lukewilliamboswell/roc-ray"
  );
});

// A plugin can document a package as well as a platform. A package skeleton
// has no scaffold and no sample, so the author does not have to delete them.
test("a package skeleton serves its namespace, documents it, and validates", () => {
  const dir = path.join(tmp, "packaged");
  assert.ok(
    !init(dir, { kind: "package", repo: "someone/thing", version: "1.2.0" }).some(
      (c) => c.status === "fail"
    )
  );
  const [corpus] = JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8")).corpora;
  // No scaffold or sample: `roc_check` wraps code in a platform.
  assert.equal(corpus.scaffold, undefined);
  assert.equal(corpus.sample, undefined);
  assert.match(corpus.release, /someone\/thing\/releases\/download\/1\.2\.0\//);

  const failed = staticChecks(dir).filter((c) => c.status === "fail");
  assert.deepEqual(failed.map((c) => c.name), ["index"], failed.map((c) => `${c.name}: ${c.detail}`).join("\n"));

  // After the index exists, the header of the release tells that it is a
  // package. The manifest line must say "documented package", because this
  // host serves the prose and topics of the corpus.
  fs.writeFileSync(
    path.join(dir, "index.json"),
    indexed({ [corpus.release]: { "main.roc": "package [Thing] {}\n", "Thing.roc": "Thing := [].{\n    greet : Str -> Str\n}\n" } })
  );
  // `init` names the corpus after its directory, which differs from the repo name.
  assert.equal(corpus.name, "packaged");
  assert.match(check(dir, "manifest").detail!, /^packaged 1\.2\.0, documented package$/m);
  assert.equal(check(dir, "name").detail, "packaged");
});

test("init refuses a kind it does not write", () => {
  const failed = init(path.join(tmp, "wrong-kind"), { kind: "library" });
  assert.equal(failed[0].status, "fail");
  assert.match(failed[0].detail!, /--kind must be platform or package/);
});

test("init refuses a directory that already holds a plugin", () => {
  const dir = path.join(tmp, "twice");
  init(dir, {});
  const second = init(dir, {});
  assert.equal(second[0].status, "fail");
  assert.match(second[0].detail!, /already holds a plugin\.json/);
});

// -----------------------------------------------------------------------------
// validate
// -----------------------------------------------------------------------------

test("a manifest that is not readable is the only thing reported", () => {
  const dir = plugin("broken", { "plugin.json": "{ not json" });
  const checks = staticChecks(dir);
  assert.equal(checks.length, 1);
  assert.equal(checks[0].name, "manifest");
  assert.equal(checks[0].status, "fail");
});

test("a name this server already ships is refused", () => {
  const dir = ray({ name: "basic-cli" });
  assert.equal(check(dir, "name").status, "fail");
  assert.match(check(dir, "name").detail!, /already a name this server ships/);
});

test("a reserved scope name is refused for what it would displace", () => {
  const dir = ray({ name: "builtin" });
  assert.equal(check(dir, "name").status, "fail");
  assert.match(check(dir, "name").detail!, /reserved/);
});

// A missing maintainer fails, but a missing value in every other optional field
// is only reported. The loader serves a corpus with no maintainer, and the
// manifests of this repo name no maintainer because the loader fills it in. But
// a published corpus makes claims that this server cannot check, and those
// claims must carry the name of a person.
test("a manifest naming no maintainer is refused, and one naming somebody passes", () => {
  assert.equal(check(ray(), "maintainer").status, "fail");
  const named = ray({ maintainer: "lukewilliamboswell" });
  assert.equal(check(named, "maintainer").status, "ok");
  assert.equal(check(named, "maintainer").detail, "lukewilliamboswell");
  // Each output that shows the identity of a plugin also shows its maintainer.
  assert.match(inspect(named), /maintainer lukewilliamboswell/);
  assert.match(inspect(ray()), /maintainer not named/);
});

// Each of these checks passes for a plugin with no package.json. Nobody packs a
// plugin that is declared by path, and the checks are about the tarball.
test("a plugin that would run something on install is refused", () => {
  const none = ray();
  assert.equal(check(none, "package").status, "ok");
  assert.match(check(none, "package").detail!, /declared by path/);

  const hooked = ray({}, { "package.json": { name: "@you/roc-ray", version: "0.1.0", scripts: { prepare: "make" } } }, "-hooked");
  assert.equal(check(hooked, "install").status, "fail");
  assert.match(check(hooked, "install").detail!, /prepare/);

  const quiet = ray({}, { "package.json": { name: "@you/roc-ray", version: "0.1.0", scripts: { test: "make" } } }, "-quiet");
  assert.equal(check(quiet, "install").status, "ok");
  assert.equal(check(quiet, "package").detail, "@you/roc-ray 0.1.0");
});

// This failure shows only after publishing. The corpus and the manifest are
// correct, but the tarball does not contain the corpus.
test("a corpus path the tarball would leave out is named before it is published", () => {
  const short = ray({}, { "package.json": { name: "@you/roc-ray", version: "0.1.0", files: ["plugin.json"] } }, "-short");
  assert.equal(check(short, "tarball").status, "fail");
  assert.match(check(short, "tarball").detail!, /not packed: index\.json/);

  const whole = ray({}, { "package.json": { name: "@you/roc-ray", version: "0.1.0", files: ["plugin.json", "index.json"] } }, "-whole");
  assert.equal(check(whole, "tarball").status, "ok");

  // With no `files` list, npm packs everything. The check accepts this choice.
  const listless = ray({}, { "package.json": { name: "@you/roc-ray", version: "0.1.0" } }, "-listless");
  assert.equal(check(listless, "tarball").status, "ok");
  assert.match(check(listless, "tarball").detail!, /everything not ignored/);
});

// The loader skips a path outside the plugin and tells the author nothing.
// `validate` must report the path before the author publishes.
test("a path leaving the plugin is named, not just the fact that it is missing", () => {
  const dir = ray({ overview: "../../etc/passwd" });
  assert.equal(check(dir, "paths").status, "fail");
  assert.match(check(dir, "paths").detail!, /outside the plugin/);
});

test("a declared path that is not there is named", () => {
  const dir = ray({ examples: "examples" });
  assert.equal(check(dir, "paths").status, "fail");
  assert.match(check(dir, "paths").detail!, /declared and not there: examples/);
});

// The check for paths outside the plugin must cover every path field of a
// manifest. Otherwise a new field can escape the check.
test("a sample outside the plugin is refused like any other declared path", () => {
  const dir = ray({ sample: "../sample.roc" });
  assert.equal(check(dir, "paths").status, "fail");
  assert.match(check(dir, "paths").detail!, /outside the plugin/);
});

test("a release that parsed to nothing is a failure, not an empty scope", () => {
  const url = release("x/hollow", "1.0.0", "Hollow");
  const dir = plugin("hollow", {
    "plugin.json": { schema: 1, corpora: [{ release: url, description: "Nothing in it." }] },
    "index.json": indexed({ [url]: { "main.roc": 'platform "hollow"\n    exposes []\n' } }),
  });
  assert.equal(check(dir, "corpus").status, "fail");
});

// `get_roc_syntax(scope:)` returns the page whole. Each caller pays its size on each
// call, and the author does not see that cost.
test("an overview page over the ceiling is refused with what it costs", () => {
  const dir = ray({ overview: "overview.md" }, { "overview.md": "# big\n\n" + "word ".repeat(5000) });
  assert.equal(check(dir, "overview").status, "fail");
  assert.match(check(dir, "overview").detail!, /ceiling is 4000/);
});

// The server serves a topic by name, and the check scripts compile it. These
// are two separate declarations. A topic with only the first one can stop
// compiling, and no check finds out.
test("a topic under no checks directory is named", () => {
  const topic = {
    name: "ray_game",
    file: "topics/ray_game.roc",
    description: "How a game is put together.",
    keywords: ["game"],
  };
  const loose = ray(
    { topics: [topic], checks: ["verify"] },
    { "topics/ray_game.roc": "# a\n", "verify/snippets.roc": "# b\n" },
    "-loose"
  );
  assert.equal(check(loose, "topics").status, "fail");
  assert.match(check(loose, "topics").detail!, /ray_game/);

  const gated = ray(
    { topics: [topic], checks: ["topics", "verify"] },
    { "topics/ray_game.roc": "# a\n", "verify/snippets.roc": "# b\n" },
    "-gated"
  );
  assert.equal(check(gated, "topics").status, "ok");
  // Two programs compile, and the server serves one of them by name.
  assert.match(check(gated, "topics").detail!, /1 served by name, 1 more compiled/);
});

// If no check script compiles the snippets of a page, the page can go out of
// date with the compiler. This server exists to prevent that failure.
test("a snippet in no app the gate compiles is named", () => {
  const dir = ray(
    { overview: "overview.md", checks: ["verify"] },
    {
      "overview.md": "# ray\n\n```roc\nDraw.circle!(1.0)\n```\n",
      "verify/app.roc": "app [main!] {}\n\nmain! = |_args| Ok({})\n",
    }
  );
  assert.equal(check(dir, "snippets").status, "fail");
  assert.match(check(dir, "snippets").detail!, /Draw\.circle!/);
});

test("a snippet the verify app carries passes", () => {
  const dir = ray(
    { overview: "overview.md", checks: ["verify"] },
    {
      "overview.md": "# ray\n\n```roc\nDraw.circle!(1.0)\n```\n",
      "verify/app.roc": "app [main!] {}\n\nmain! = |_args| Ok(Draw.circle!(1.0))\n",
    }
  );
  assert.equal(check(dir, "snippets").status, "ok");
});

test("fenced Roc blocks are read off a page and nothing else is", () => {
  const page = "# t\n\n```roc\nа = 1\n```\n\n```bash\nnot roc\n```\n\n```roc\nb = 2\n```\n";
  assert.deepEqual(snippets(page), ["а = 1", "b = 2"]);
});

// The compiler diagnostic names both types `Request` and does not name their
// packages. An author who publishes a release that the API of a bundled
// platform refuses must get a clear message from `validate`.
test("a package release a bundled platform's boundary refuses is named with why", () => {
  const dir = plugin("http-fork", {
    "plugin.json": { schema: 1, corpora: [{ name: "http-docs", release: HTTP_FORK }] },
    "index.json": indexed({
      [HTTP_FORK]: {
        "main.roc": "package [Response] {}\n",
        "Response.roc": "Response := [].{\n    from_status : U16 -> Response\n}\n",
      },
    }),
  });
  const hit = check(dir, "packages");
  assert.match(hit.name, /refused here/);
  assert.match(hit.detail!, /basic-webserver requires 1\.0\.0/);
  assert.match(hit.detail!, /carry it across the API/);
});

test("a package no bundled platform declares is reported as unrefused, not as a problem", () => {
  const dir = plugin("json-pkg", {
    "plugin.json": { schema: 1, corpora: [{ name: "json-docs", release: release("example/json", "2.1.0", "Json") }] },
    "index.json": indexed({
      [release("example/json", "2.1.0", "Json")]: {
        "main.roc": "package [Json] {}\n",
        "Json.roc": "Json := [].{\n    parse : Str -> Str\n}\n",
      },
    }),
  });
  assert.equal(check(dir, "packages").status, "ok");
  assert.match(check(dir, "packages").detail!, /no bundled platform declares it/);
});

// -----------------------------------------------------------------------------
// inspect
// -----------------------------------------------------------------------------

test("inspect reports the namespace and the tier that would fill it", () => {
  const dir = plugin("inspectable", {
    "plugin.json": {
      schema: 1,
      corpora: [
        { release: RAY, description: "A graphics platform." },
        { release: release("roc-lang/http", "1.0.0", "HttpOwn") },
      ],
    },
    "index.json": indexed({
      [RAY]: { "main.roc": PLATFORM, "Draw.roc": DRAW },
      [release("roc-lang/http", "1.0.0", "HttpOwn")]: {
        "main.roc": "package [Response] {}\n",
        "Response.roc": "Response := [].{\n    from_status : U16 -> Response\n}\n",
      },
    }),
  });
  const out = inspect(dir);
  assert.match(out, /platform:roc-ray\s+\d+ items/);
  // The plugin serves its package at tier 1, under the name of the package.
  assert.match(out, /roc-lang\/http 1\.0\.0 \(tier 1, from http\)/);
});

// One install with two corpora: a platform, and the package that its API uses.
// `validate` checks each corpus as if it were alone, and tells the kind of each.
test("a plugin documenting a platform and a package validates each of them", () => {
  const BRUSH = release("x/brush", "1.0.0", "Brush");
  const dir = plugin("paired", {
    "plugin.json": {
      schema: 1,
      maintainer: "x",
      corpora: [
        { release: RAY, description: "A graphics platform.", purpose: "pictures" },
        { release: BRUSH, description: "Strokes." },
      ],
    },
    "index.json": indexed({
      [RAY]: {
        "main.roc": `platform "ray"\n    exposes [Draw]\n    packages {\n        brush: "${BRUSH}",\n    }\n`,
        "Draw.roc": "import brush.Stroke\n\n" + DRAW,
      },
      [BRUSH]: { "main.roc": "package [Stroke] {}\n", "Stroke.roc": "Stroke := [].{\n    width : U8\n}\n" },
    }),
  });
  const checks = staticChecks(dir);
  assert.deepEqual(checks.filter((c) => c.status === "fail"), []);
  assert.match(check(dir, "manifest").detail!, /^roc-ray 0\.7\.0, platform\nbrush 1\.0\.0, documented package$/m);
  assert.deepEqual(checks.filter((c) => c.name === "name").map((c) => c.detail), ["roc-ray", "brush"]);
  assert.deepEqual(
    checks.filter((c) => c.name === "corpus").map((c) => c.detail!.split(":")[0]),
    ["roc-ray", "brush"]
  );
  // The package in the same plugin serves the pin of the platform.
  assert.match(inspect(dir), /x\/brush\s+1\.0\.0, crosses Draw, served by brush 1\.0\.0/);
});

test("inspect says what is wrong rather than throwing", () => {
  const dir = plugin("unreadable", { "plugin.json": "{" });
  assert.match(inspect(dir), /unreadable/);
});

// -----------------------------------------------------------------------------
// doctor
// -----------------------------------------------------------------------------

test("doctor reports a declaration that resolves to nothing, and fails over it", () => {
  const checks = doctor(["--plugin=./nowhere"], BARE_ENV, ROOT);
  const hit = checks.find((c) => c.name.startsWith("./nowhere"));
  assert.equal(hit?.status, "fail");
  assert.match(hit!.detail!, /resolves to nothing/);
  assert.match(hit!.detail!, /serves everything else/);
});

test("doctor names the source of every declaration, so the fix is findable", () => {
  const dir = ray();
  const checks = doctor([`--plugin=${dir}`], { ...BARE_ENV, ROC_MCP_PLUGINS: path.join(tmp, "elsewhere") }, ROOT);
  assert.ok(checks.some((c) => c.name === `${dir} (--plugin=)`));
  assert.ok(checks.some((c) => c.name.endsWith("(ROC_MCP_PLUGINS)")));
});

// The resolution table is the main output of `doctor`. It shows the one
// provider for each namespace, which the registry chooses one time.
test("doctor prints one row per namespace with who ends up serving it", () => {
  const table = doctor([], BARE_ENV, ROOT).find((c) => c.name === "resolution");
  assert.equal(table?.status, "ok");
  assert.match(table!.detail!, /basic-webserver\s+pkg:roc-lang\/http\s+1\.0\.0\s+roc-syntax-mcp 1\.0\.0 \(tier 3\)/);
});

// An operator runs `doctor` to find this conflict: a namespace with no
// provider. Every lookup into that namespace returns no items, only a note.
test("doctor fails over a namespace no provider serves", () => {
  const dir = plugin("empty-namespace", {
    "plugin.json": {
      schema: 1,
      corpora: [
        { release: release("x/needs-http", "1.0.0", "NeedsHttp"), description: "A platform pinning a release nothing here serves." },
      ],
    },
    "index.json": indexed({
      [release("x/needs-http", "1.0.0", "NeedsHttp")]: {
        "main.roc":
          'platform "needs-http"\n    exposes [Serve]\n    packages {\n' +
          '        http: "https://github.com/roc-lang/http/releases/download/7.7.7/x.tar.br",\n    }\n',
        "Serve.roc": "import http.Request\n\nServe := [].{\n    go! : Request.Request => {}\n}\n",
      },
    }),
  });
  const table = doctor([`--plugin=${dir}`], BARE_ENV, ROOT).find((c) => c.name === "resolution");
  assert.equal(table?.status, "fail");
  assert.match(table!.detail!, /needs-http\s+pkg:roc-lang\/http\s+7\.7\.7\s+NOTHING/);
  assert.match(table!.detail!, /no compatible provider/);

  // The same set, with a force from the operator. The table must mark the row
  // that the force changed. Otherwise the row looks like a normal resolution.
  const forced = doctor([`--plugin=${dir}`, "--force=roc-lang/http"], BARE_ENV, ROOT).find(
    (c) => c.name === "resolution"
  );
  assert.equal(forced?.status, "ok");
  assert.match(forced!.detail!, /needs-http\s+pkg:roc-lang\/http\s+7\.7\.7\s+roc-syntax-mcp 1\.0\.0 \(tier 3\) FORCED/);
});

// Only the configuration sets a force. `doctor` is the only place where an
// operator can see the overrides without a start of a server that uses them.
test("doctor names every forced namespace, and fails over one that names none", () => {
  const good = doctor(["--force=roc-lang/http"], BARE_ENV, tmp);
  const forced = good.find((c) => c.name === "forced")!;
  assert.equal(forced.status, "ok");
  assert.match(forced.detail!, /roc-lang\/http \(--force=\)/);

  const bad = doctor(["--force=not-a-repo-path"], BARE_ENV, tmp);
  const broken = bad.find((c) => c.name === "forced")!;
  assert.equal(broken.status, "fail");
  assert.match(broken.detail!, /names no namespace/);
});

// If nobody sets a force, `doctor` shows no "forced" line.
test("doctor says nothing about forcing when nothing is forced", () => {
  assert.equal(doctor([], BARE_ENV, tmp).some((c) => c.name === "forced"), false);
});

test("doctor says so when nothing is declared", () => {
  const checks = doctor([], BARE_ENV, path.join(tmp, "empty-workspace"));
  assert.match(checks.find((c) => c.name === "declared")!.detail!, /serves only what it ships/);
});

// `doctor` exists to explain a declaration that resolves to nothing. Thus it
// must run with that declaration and print the table.
test("doctor runs where a declaration resolves to nothing", () => {
  const run = spawnSync(
    process.execPath,
    ["--import", TSX_LOADER, path.join(ROOT, "src", "plugin_cli.ts"), "doctor"],
    { cwd: ROOT, encoding: "utf-8", env: { ...process.env, ROC_MCP_PLUGINS: path.join(tmp, "nowhere") } }
  );
  assert.equal(run.status, 1, run.stderr);
  assert.match(run.stdout, /resolves to nothing/);
  // The output continues past the failure to the table. An exit at module load
  // would not print the table.
  assert.match(run.stdout, /resolution/);
  assert.doesNotMatch(run.stderr, /roc-syntax: plugin/);
});

// -----------------------------------------------------------------------------
// What a plugin's own paths point at
// -----------------------------------------------------------------------------

// The manifest paths of a declared plugin are absolute. If code joins one to
// the host root, the path points to a file that does not exist. Then
// `roc_check` does not find the scaffold, and silently does not wrap the code.
test("a declared plugin's scaffold is read from the plugin, not from under the host", () => {
  const dir = plugin("scaffolded", {
    "plugin.json": {
      schema: 1,
      corpora: [{ release: RAY, description: "A graphics platform.", scaffold: "scaffold.roc" }],
    },
    "index.json": indexed({ [RAY]: { "main.roc": PLATFORM, "Draw.roc": DRAW } }),
    "scaffold.roc":
      'app [main!] { pf: platform "https://github.com/x/roc-ray/releases/download/0.7.0/a.tar.br" }\n\n' +
      "import pf.Draw\n\n# @user-code\n\n# @default main!\nmain! = |_args| Ok({})\n",
  });
  const catalog = loadCatalog([`--plugin=${dir}`], process.env, ROOT);
  assert.deepEqual(catalog.diagnostics, []);
  const { source } = scaffold("x = 1\n", "roc-ray", catalog);
  assert.match(source, /import pf\.Draw/);
  assert.match(source, /^x = 1$/m);
});

// -----------------------------------------------------------------------------
// index
// -----------------------------------------------------------------------------

// The author gives a release URL and gets an index. The fake `roc` unpacks a
// fixed tree into the place where `roc deps` would, so nothing is downloaded.
test("plugin index writes the snapshot, and --check holds it to its release", async () => {
  const cache = fs.mkdtempSync(path.join(tmp, "cache-"));
  const bin = fs.mkdtempSync(path.join(tmp, "bin-"));
  const roc = path.join(bin, "roc");
  fs.writeFileSync(
    roc,
    `#!/bin/sh
[ "$1" = version ] && exit 0
url=$(grep -o 'https://[^"]*' "$2")
hash=$(basename "$url" | sed 's/[.]tar[.].*//')
mkdir -p "${cache}/$hash"
printf 'platform "ray"\\n    exposes [Draw]\\n    packages {}\\n' > "${cache}/$hash/main.roc"
printf 'Draw := [].{\\n    circle! : F32 => {}\\n}\\n' > "${cache}/$hash/Draw.roc"
`,
    { mode: 0o755 }
  );
  const dir = plugin("to-index", {
    "plugin.json": { schema: 1, corpora: [{ release: RAY, description: "A graphics platform." }] },
  });
  const saved = { ROC: process.env.ROC, ROC_PACKAGE_CACHE: process.env.ROC_PACKAGE_CACHE };
  process.env.ROC = roc;
  process.env.ROC_PACKAGE_CACHE = cache;
  try {
    assert.equal(check(dir, "index").status, "fail");
    assert.equal(await main(["index", dir]), 0);
    assert.equal(check(dir, "index").status, "ok");
    assert.match(check(dir, "corpus").detail!, /^roc-ray: 1 items in 1 modules/);
    assert.equal(await main(["index", dir, "--check"]), 0);

    // `--check` must find a hand edit.
    const file = path.join(dir, "index.json");
    fs.writeFileSync(file, fs.readFileSync(file, "utf-8").replace("circle!", "square!"));
    assert.equal(await main(["index", dir, "--check"]), 1);
    assert.equal(await main(["index", dir]), 0);
    assert.equal(await main(["index", dir, "--check"]), 0);
  } finally {
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  }
});

// -----------------------------------------------------------------------------
// plugin add, remove, list
// -----------------------------------------------------------------------------

// The installed plugins are a separate declaration source. Thus the server
// serves a plugin that `add` installed in a workspace that declares no plugin.
test("add installs a plugin for every workspace, and remove takes it away", () => {
  const env = { ...process.env, ROC_MCP_HOME: path.join(tmp, "home-add") };
  const ray = path.join(ROOT, "plugins", "roc-ray");
  const added = add([ray], env);
  assert.deepEqual(added.filter((c) => c.status === "fail"), [], JSON.stringify(added));
  assert.match(added[0].detail!, /scope roc-ray/);
  assert.deepEqual(installedPlugins(env), ["@roc-syntax/roc-ray"]);
  assert.ok(list(env).some((c) => c.name.startsWith("@roc-syntax/roc-ray ")));

  // A plugin holding two corpora names both releases, read from its manifest.
  const joy = path.join(ROOT, "plugins", "joy");
  assert.deepEqual(add([joy], env).filter((c) => c.status === "fail"), []);
  const tags = JSON.parse(fs.readFileSync(path.join(joy, "plugin.json"), "utf-8")).corpora.map(
    (c: { release: string }) => c.release.match(/\/([^/]+)\/releases\/download\/([^/]+)\//)!.slice(1).join(" ")
  );
  assert.equal(tags.length, 2);
  const joyRow = list(env).find((c) => c.name.startsWith("@roc-syntax/joy "));
  assert.match(joyRow?.name ?? "", new RegExp(`^@roc-syntax/joy \\S+ \\(${tags.join(", ").replace(/\./g, "\\.")}\\)$`));
  assert.deepEqual(remove(["@roc-syntax/joy"], env).filter((c) => c.status === "fail"), []);

  const nowhere = fs.mkdtempSync(path.join(tmp, "ws-"));
  assert.deepEqual(declarations([], env), [{ spec: "@roc-syntax/roc-ray", source: "plugin add" }]);
  const served = doctor([], env, nowhere).find((c) => c.name === "@roc-syntax/roc-ray (plugin add)");
  assert.equal(served?.status, "ok", JSON.stringify(served));

  assert.equal(remove(["@roc-syntax/roc-ray"], env).every((c) => c.status === "ok"), true);
  assert.deepEqual(installedPlugins(env), []);
  assert.equal(remove(["@roc-syntax/roc-ray"], env)[0].status, "fail");
});

// A package with no plugin.json would make each later start of the server exit.
test("add refuses a package that is not a plugin, and leaves the folder as it was", () => {
  const env = { ...process.env, ROC_MCP_HOME: path.join(tmp, "home-refuse") };
  const notPlugin = plugin("not-a-plugin", { "package.json": { name: "not-a-plugin", version: "1.0.0" } });
  const refused = add([notPlugin], env);
  assert.equal(refused[0].status, "fail", JSON.stringify(refused));
  assert.match(refused[0].detail!, /has no plugin\.json, so it is not a plugin\nNothing was installed/);
  assert.deepEqual(installedPlugins(env), []);
  assert.ok(!fs.existsSync(path.join(env.ROC_MCP_HOME, "plugins", "node_modules", "not-a-plugin")));
});

/** A copy of the shipped weaver plugin under another package name. */
function weaverAs(name: string): string {
  const dir = path.join(tmp, `weaver-as-${name}`);
  fs.cpSync(path.join(ROOT, "plugins", "weaver"), dir, { recursive: true });
  const pkg = JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf-8"));
  fs.writeFileSync(path.join(dir, "package.json"), JSON.stringify({ ...pkg, name }));
  return dir;
}

// The server loads the installed plugins in name order. Thus "aa" would take
// the name of "zz" in every workspace, and the next start would report nothing.
test("add refuses a plugin that would take a name from one already installed", () => {
  const env = { ...process.env, ROC_MCP_HOME: path.join(tmp, "home-displace") };
  assert.deepEqual(add([weaverAs("zz-weaver")], env).filter((c) => c.status === "fail"), []);
  const refused = add([weaverAs("aa-weaver")], env);
  assert.equal(refused.length, 1, JSON.stringify(refused));
  assert.equal(refused[0].name, "zz-weaver");
  assert.match(refused[0].detail!, /would no longer be served next to aa-weaver/);
  assert.deepEqual(installedPlugins(env), ["zz-weaver"]);
  assert.ok(!fs.existsSync(path.join(env.ROC_MCP_HOME, "plugins", "node_modules", "aa-weaver")));
});

// A path plugin is a link to the user's folder, which they can delete.
test("list and the server name the command that fixes an installed plugin that is gone", () => {
  const env = { ...process.env, ROC_MCP_HOME: path.join(tmp, "home-gone") };
  const gone = weaverAs("gone-weaver");
  assert.deepEqual(add([gone], env).filter((c) => c.status === "fail"), []);
  assert.ok(list(env).some((c) => c.status === "ok" && /^gone-weaver \d/.test(c.name)));
  fs.rmSync(gone, { recursive: true });

  const missing = list(env).find((c) => c.name === "gone-weaver");
  assert.equal(missing?.status, "fail");
  assert.match(missing!.detail!, /`plugin remove` it/);
  // A new process, because the module resolver of this process caches the folder.
  const r = spawnSync(process.execPath, ["--import", TSX_LOADER, path.join(ROOT, "src", "index.ts")], {
    encoding: "utf-8",
    input: "",
    env: { ...env, CLAUDE_PROJECT_DIR: fs.mkdtempSync(path.join(tmp, "ws-")) },
  });
  // The server skips the missing plugin and does not exit, because the
  // installed plugins apply to every workspace.
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stderr, /Run `roc-syntax-mcp plugin remove gone-weaver`/);
});

// `plugin remove ./weaver` after `plugin add ./weaver` is what a user types.
test("remove takes the path a plugin was added from", async () => {
  const home = path.join(tmp, "home-remove-path");
  const dir = weaverAs("path-weaver");
  const saved = process.env.ROC_MCP_HOME;
  process.env.ROC_MCP_HOME = home;
  try {
    assert.equal(await main(["add", dir]), 0);
    assert.equal(await main(["remove", dir]), 0);
    assert.deepEqual(installedPlugins(process.env), []);
  } finally {
    process.env.ROC_MCP_HOME = saved;
  }
});

/** A local registry serving every tarball in `dir`, stopped when the test ends. */
async function registry(t: { after: (fn: () => void) => void }, dir: string): Promise<string> {
  const child = spawn(process.execPath, [path.join(ROOT, "src", "testdata", "registry.mjs"), dir]);
  t.after(() => child.kill());
  const port = await new Promise<string>((resolve) => child.stdout.once("data", (d) => resolve(String(d).trim())));
  return `http://127.0.0.1:${port}/`;
}

/** Publish `name@version` to the registry folder, as one of the shipped plugins, weaver unless named. */
function publish(
  dir: string,
  name: string,
  version: string,
  over: (pkg: Record<string, unknown>) => void = () => {},
  from = "weaver"
) {
  const src = fs.mkdtempSync(path.join(tmp, "pub-"));
  fs.cpSync(path.join(ROOT, "plugins", from), src, { recursive: true });
  const pkg = { ...JSON.parse(fs.readFileSync(path.join(src, "package.json"), "utf-8")), name, version };
  over(pkg);
  fs.writeFileSync(path.join(src, "package.json"), JSON.stringify(pkg));
  const r = spawnSync("npm", ["pack", src, "--pack-destination", dir, "--silent"], { encoding: "utf-8" });
  assert.equal(r.status, 0, r.stderr);
}

/** Every env var the installers read the registry and cache from. */
const registryEnv = (home: string, url: string) => ({
  ...process.env,
  ROC_MCP_HOME: home,
  npm_config_registry: url,
  NPM_CONFIG_REGISTRY: url,
  npm_config_cache: path.join(home, "npm-cache"),
  BUN_INSTALL_CACHE_DIR: path.join(home, "bun-cache"),
});

// A user upgrades with a second `add`. Thus `add` must fetch the new release.
// If the server would refuse the new release, the old release must stay.
test("add again upgrades to a newer release, and keeps the old one when the new one is refused", async (t) => {
  const pub = fs.mkdtempSync(path.join(tmp, "registry-"));
  const env = registryEnv(path.join(tmp, "home-upgrade"), await registry(t, pub));
  publish(pub, "up-weaver", "1.0.0");
  const first = add(["up-weaver"], env);
  assert.match(first[0].name, /^up-weaver 1\.0\.0$/, JSON.stringify(first));

  publish(pub, "up-weaver", "1.1.0");
  const upgraded = add(["up-weaver"], env);
  assert.equal(upgraded[0].name, "up-weaver 1.1.0", JSON.stringify(upgraded));
  assert.match(upgraded[0].detail!, /^upgraded from 1\.0\.0$/m);

  publish(pub, "up-weaver", "1.2.0", (pkg) => (pkg.files = (pkg.files as string[]).filter((f) => f !== "plugin.json")));
  assert.equal(add(["up-weaver"], env)[0].status, "fail");
  assert.ok(list(env).some((c) => c.name.startsWith("up-weaver 1.1.0 (weaver ")));
});

// Bun keeps a cached version list. Without `--no-cache`, `add` does not find a
// release after the first.
test("add again upgrades under Bun too", { skip: spawnSync("bun", ["--version"]).status !== 0 && "no bun" }, async (t) => {
  const pub = fs.mkdtempSync(path.join(tmp, "registry-"));
  const env = registryEnv(path.join(tmp, "home-upgrade-bun"), await registry(t, pub));
  const cli = (...args: string[]) =>
    spawnSync("bun", [path.join(ROOT, "src", "plugin_cli.ts"), ...args], { encoding: "utf-8", env });
  publish(pub, "bun-weaver", "1.0.0");
  assert.equal(cli("add", "bun-weaver").status, 0);
  publish(pub, "bun-weaver", "1.1.0");
  const r = cli("add", "bun-weaver");
  assert.match(r.stdout, /bun-weaver 1\.1\.0\n\s+upgraded from 1\.0\.0/, r.stdout + r.stderr);
});

// `update` updates each plugin separately, so one refused release does not stop the others.
test("update installs the newest release of every plugin, and keeps a refused one where it was", async (t) => {
  const pub = fs.mkdtempSync(path.join(tmp, "registry-"));
  const env = registryEnv(path.join(tmp, "home-update"), await registry(t, pub));
  publish(pub, "up-a", "1.0.0");
  publish(pub, "up-b", "1.0.0", undefined, "roc-ray");
  assert.deepEqual(add(["up-a", "up-b"], env).filter((c) => c.status === "fail"), []);

  publish(pub, "up-a", "1.1.0", (pkg) => (pkg.files = (pkg.files as string[]).filter((f) => f !== "plugin.json")));
  publish(pub, "up-b", "1.1.0", undefined, "roc-ray");
  const updated = update([], env);
  assert.equal(updated.find((c) => c.name === "up-a")?.status, "fail", JSON.stringify(updated));
  assert.match(updated.find((c) => c.name.startsWith("up-b"))!.detail!, /^upgraded from 1\.0\.0$/m);
  assert.equal(updated.at(-1)?.name, "served");
  assert.ok(list(env).some((c) => c.name.startsWith("up-a 1.0.0 (weaver ")));
  assert.ok(list(env).some((c) => c.name.startsWith("up-b 1.1.0 (roc-ray ")));

  const again = update(["up-b"], env);
  assert.deepEqual(again, [{ name: "up-b 1.1.0", status: "ok", detail: "already the newest release" }]);
  assert.equal(update(["up-c"], env)[0].status, "fail");
});

// npm keeps the range a first install saved, and `^0.0.1` matches 0.0.1 alone.
test("update and add again move past the range the first install saved", async (t) => {
  const pub = fs.mkdtempSync(path.join(tmp, "registry-"));
  const env = registryEnv(path.join(tmp, "home-range"), await registry(t, pub));
  publish(pub, "range-weaver", "0.0.1");
  assert.equal(add(["range-weaver"], env)[0].name, "range-weaver 0.0.1");
  publish(pub, "range-weaver", "0.0.2");
  const updated = update([], env);
  assert.match(updated.find((c) => c.name.startsWith("range-weaver"))!.detail!, /^upgraded from 0\.0\.1$/m, JSON.stringify(updated));
  publish(pub, "range-weaver", "1.0.0");
  assert.equal(add(["range-weaver"], env)[0].name, "range-weaver 1.0.0");
});

test("only a bare package name asks for the newest release", () => {
  assert.equal(newestOf("weaver"), "weaver@latest");
  assert.equal(newestOf("@roc-syntax/roc-ray"), "@roc-syntax/roc-ray@latest");
  for (const s of ["weaver@0.0.1", "@roc-syntax/roc-ray@next", "./weaver", "../weaver", "/abs/weaver", "a.tgz", "github:o/r", "C:\\weaver"]) {
    assert.equal(newestOf(s), s, s);
  }
});

// A folder, a tarball or a git source has no newer release for npm to find.
test("only a range or a tag is a spec a registry serves", () => {
  for (const s of ["^1.0.0", "1.0.0", "latest", "*", ">=1 <2"]) assert.equal(isRegistrySpec(s), true, s);
  for (const s of ["file:../weaver", "link:../weaver", "github:o/r", "o/r", "npm:other@1", "https://x/y.tgz", "a.tgz"]) {
    assert.equal(isRegistrySpec(s), false, s);
  }
});

/** A server package folder, as a registry release when `built`, otherwise as an install from git. */
function fakeServer(name: string, built: boolean, version = "1.0.0"): string {
  const dir = path.join(tmp, name);
  fs.mkdirSync(path.join(dir, "bin"), { recursive: true });
  const pkg = { name: "roc-syntax-mcp", version, bin: { "roc-syntax-mcp": "bin/entry.js" }, repository: { url: "git+https://github.com/o/roc-syntax-mcp.git" } };
  fs.writeFileSync(path.join(dir, "package.json"), JSON.stringify(pkg));
  if (built) fs.mkdirSync(path.join(dir, "dist")), fs.writeFileSync(path.join(dir, "dist", "index.js"), "");
  return dir;
}

/** A global folder holding `pkg` under the server's name, as a link the way pnpm makes one. */
function globalRoot(by: string, pkg: string | null, over: Partial<GlobalRoot> = {}): GlobalRoot {
  const root = fs.mkdtempSync(path.join(tmp, "global-"));
  if (pkg) fs.symlinkSync(pkg, path.join(root, "roc-syntax-mcp"));
  return { by, hint: /$^/, root: () => root, install: (s) => [by, "install", s], uninstall: (n) => [by, "uninstall", n], ...over };
}

test("upgrade finds the installer that holds this server, and what it fetches", () => {
  const released = fakeServer("srv-released", true);
  const none: GlobalRoot = { by: "npm", hint: /$^/, root: () => null, install: () => [], uninstall: () => [] };
  const found = detectInstall(released, [none, globalRoot("bun", null), globalRoot("pnpm", released)]);
  assert.equal(found.by, "pnpm");
  assert.deepEqual(found.update, ["pnpm", "install", "roc-syntax-mcp@latest"]);
  assert.equal(fs.realpathSync(found.locate!()!), fs.realpathSync(released));

  const fromGit = fakeServer("srv-git", false);
  assert.deepEqual(detectInstall(fromGit, [globalRoot("npm", fromGit)]).update, ["npm", "install", "github:o/roc-syntax-mcp"]);

  assert.match(detectInstall(released, [globalRoot("npm", null)]).fix!, /the way you installed it/);
  const npx = fakeServer(path.join("_npx", "abc", "node_modules", "roc-syntax-mcp"), true);
  assert.match(detectInstall(npx, []).fix!, /`npx roc-syntax-mcp@latest plugin update`/);
  const checkout = fakeServer("srv-checkout", false);
  fs.mkdirSync(path.join(checkout, ".git"));
  assert.match(detectInstall(checkout, [globalRoot("npm", checkout)]).fix!, /`git pull`/);
});

// Yarn under Corepack can download Yarn just to say where its global folder is.
test("upgrade asks a manager that needs a hint only when the path gives one", () => {
  const released = fakeServer("srv-plain", true);
  const yarn: GlobalRoot = { by: "Yarn 1", hint: /yarn/i, onlyHinted: true, root: () => assert.fail("yarn was asked"), install: () => [], uninstall: () => [] };
  assert.equal(detectInstall(released, [yarn, globalRoot("npm", released)]).by, "npm");
  const inYarn = fakeServer(path.join("yarn", "global", "node_modules", "roc-syntax-mcp"), true);
  assert.equal(detectInstall(inYarn, [globalRoot("npm", null), globalRoot("Yarn 1", inYarn, { hint: /yarn/i, onlyHinted: true })]).by, "Yarn 1");
});

// Captured from `yarn global dir` 1.22.22 writing into a pipe.
test("a global folder is read from the last line a manager printed, without its terminal codes", () => {
  assert.equal(lastLine("\x1b[2K\x1b[1G/home/u/.config/yarn/global\n"), "/home/u/.config/yarn/global");
  assert.equal(lastLine("warning: something\r\n/usr/lib/node_modules\r\n"), "/usr/lib/node_modules");
});

/** A server whose entry records each command it is given, in `calls`. */
function recordingServer(name: string, calls: string, version = "1.0.0"): string {
  const dir = fakeServer(name, true, version);
  fs.writeFileSync(path.join(dir, "bin", "entry.js"), `require("fs").appendFileSync(${JSON.stringify(calls)}, process.argv.slice(2).join(" ") + "\\n");`);
  return dir;
}

const quietly = <T>(fn: () => T): T => {
  const log = console.log;
  console.log = () => {};
  try {
    return fn();
  } finally {
    console.log = log;
  }
};

// The server that will serve the plugins must check them, so the new server runs `plugin update`.
test("upgrade updates the server, then runs plugin update in the new one", () => {
  const calls = path.join(tmp, "upgrade-calls");
  const dir = recordingServer("srv-upgrade", calls);
  const bump = `const f = require("path").join(${JSON.stringify(dir)}, "package.json"); require("fs").writeFileSync(f, JSON.stringify({ ...require(f), version: "1.1.0" }))`;
  const install: Install = { by: "npm", update: [process.execPath, "-e", bump], spec: "roc-syntax-mcp@latest", locate: () => dir };
  assert.equal(quietly(() => upgrade(process.env, install)), 0);
  assert.equal(fs.readFileSync(calls, "utf-8"), "plugin update\n");
  assert.deepEqual(upgradeServer(install, process.env).checks, [{ name: "roc-syntax-mcp 1.1.0", status: "ok", detail: "already the newest release, by npm" }]);
  const fromGit = upgradeServer({ ...install, spec: "github:o/roc-syntax-mcp" }, process.env).checks[0];
  assert.equal(fromGit.detail, "installed again from github:o/roc-syntax-mcp, by npm");

  assert.equal(quietly(() => upgrade(process.env, { ...install, update: [process.execPath, "-e", "process.exit(3)"] })), 1);
  assert.equal(quietly(() => upgrade(process.env, { by: "npx", fix: "run something" })), 1);
  assert.equal(fs.readFileSync(calls, "utf-8"), "plugin update\n");
});

// pnpm 11 installs each global package in a folder of its own, named by a hash
// that changes on every install, so the new server is not where the old one was.
test("upgrade finds the new server where pnpm 11 moved it", () => {
  const calls = path.join(tmp, "upgrade-calls-pnpm");
  const root = fs.mkdtempSync(path.join(tmp, "pnpm-global-"));
  const old = recordingServer("srv-pnpm-old", path.join(tmp, "old-calls"));
  fs.mkdirSync(path.join(root, "aaa", "node_modules"), { recursive: true });
  fs.symlinkSync(old, path.join(root, "aaa", "node_modules", "roc-syntax-mcp"));
  const fresh = recordingServer("srv-pnpm-new", calls, "1.1.0");
  const move = `const fs = require("fs"); fs.rmSync(${JSON.stringify(path.join(root, "aaa"))}, { recursive: true, force: true }); fs.mkdirSync(${JSON.stringify(path.join(root, "bbb", "node_modules"))}, { recursive: true }); fs.rmSync(${JSON.stringify(path.join(root, "bbb", "node_modules", "roc-syntax-mcp"))}, { force: true }); fs.symlinkSync(${JSON.stringify(fresh)}, ${JSON.stringify(path.join(root, "bbb", "node_modules", "roc-syntax-mcp"))})`;
  const pnpm: GlobalRoot = { by: "pnpm", hint: /pnpm/, root: () => root, install: () => [process.execPath, "-e", move], uninstall: () => [] };
  const install = detectInstall(old, [pnpm]);
  assert.equal(install.by, "pnpm");
  assert.equal(quietly(() => upgrade(process.env, install)), 0);
  assert.equal(fs.readFileSync(calls, "utf-8"), "plugin update\n");
  assert.equal(upgradeServer(install, process.env).checks[0].name, "roc-syntax-mcp 1.1.0");
});

// -----------------------------------------------------------------------------
// uninstall
// -----------------------------------------------------------------------------

test("uninstall removes the server with the manager that holds it, and says what to do for any other install", () => {
  const released = fakeServer("srv-uninstall", true);
  assert.deepEqual(detectInstall(released, [globalRoot("pnpm", released)]).uninstall, ["pnpm", "uninstall", "roc-syntax-mcp"]);
  assert.equal(detectInstall(released, [globalRoot("npm", null)]).uninstall, undefined);
  assert.match(detectInstall(released, [globalRoot("npm", null)]).removeFix!, /the way you installed it/);
  const npx = fakeServer(path.join("_npx", "def", "node_modules", "roc-syntax-mcp"), true);
  assert.match(detectInstall(npx, []).removeFix!, /npx keeps its copy in its own cache/);
  const checkout = fakeServer("srv-uninstall-checkout", false);
  fs.mkdirSync(path.join(checkout, ".git"));
  assert.match(detectInstall(checkout, [globalRoot("npm", checkout)]).removeFix!, /Delete the checkout/);
});

/** A data folder with one plugin, one downloaded nightly, and the record of the compiler. */
function dataFolder(name: string, recorded?: string): { env: NodeJS.ProcessEnv; home: string } {
  const home = path.join(tmp, name);
  fs.mkdirSync(path.join(home, "plugins"), { recursive: true });
  fs.writeFileSync(path.join(home, "plugins", "package.json"), JSON.stringify({ dependencies: { "@roc-syntax/joy": "^0.34.0" } }));
  const nightly = path.join(home, "roc", "nightly-2026-10-06-c34079d");
  fs.mkdirSync(nightly, { recursive: true });
  fs.writeFileSync(path.join(nightly, "roc"), "");
  fs.writeFileSync(path.join(home, "roc", "use"), recorded ?? path.join(nightly, "roc"));
  return { env: { ...BARE_ENV, ROC_MCP_HOME: home }, home };
}

/** Runs `fn` with console output silenced, and returns its result and what it printed. */
async function captured<T>(fn: () => Promise<T>): Promise<{ result: T; out: string }> {
  const log = console.log;
  const error = console.error;
  let out = "";
  console.log = console.error = (...a: unknown[]) => void (out += `${a.join(" ")}\n`);
  try {
    return { result: await fn(), out };
  } finally {
    console.log = log;
    console.error = error;
  }
}

test("uninstall deletes the plugins and the compiler, then removes the server", async () => {
  const { env, home } = dataFolder("home-uninstall");
  fs.writeFileSync(path.join(home, "notes.txt"), "the user's");
  const calls = path.join(tmp, "uninstall-calls");
  const record = `require("fs").writeFileSync(${JSON.stringify(calls)}, "removed")`;
  const install: Install = { by: "npm", uninstall: [process.execPath, "-e", record] };
  const { result, out } = await captured(() => uninstall(["--yes"], env, install, null));
  assert.equal(result, 0, out);
  assert.match(out, /plugin @roc-syntax\/joy/);
  assert.match(out, /compiler nightly-2026-10-06-c34079d, 0 MB/);
  assert.match(out, /roc-syntax-mcp\n\s+removed by npm/);
  assert.equal(fs.readFileSync(calls, "utf-8"), "removed");
  assert.deepEqual(fs.readdirSync(home), ["notes.txt"]);
});

test("uninstall keeps a compiler that roc use recorded, and deletes an empty data folder", async () => {
  const own = path.join(tmp, "own-roc");
  fs.writeFileSync(own, "");
  const { env, home } = dataFolder("home-uninstall-own", own);
  const { result, out } = await captured(() => uninstall(["--yes"], env, { by: "npx", removeFix: "npx keeps its copy" }, null));
  assert.equal(result, 0, out);
  assert.match(out, new RegExp(`${own.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&")} stays`));
  assert.match(out, /skip {2}roc-syntax-mcp\n\s+npx keeps its copy/);
  assert.equal(fs.existsSync(own), true);
  assert.equal(fs.existsSync(home), false);
});

test("uninstall removes nothing until someone confirms", async () => {
  const { env, home } = dataFolder("home-uninstall-ask");
  const install: Install = { by: "npm", uninstall: [process.execPath, "-e", "process.exit(9)"] };
  assert.equal((await captured(() => uninstall([], env, install, null))).result, 2);
  assert.equal((await captured(() => uninstall([], env, install, async () => false))).result, 1);
  assert.deepEqual(fs.readdirSync(home).sort(), ["plugins", "roc"]);

  const { result, out } = await captured(() => uninstall([], env, install, async () => true));
  assert.equal(result, 1);
  assert.match(out, /FAIL {2}roc-syntax-mcp[\s\S]*Run it yourself/);
  assert.equal(fs.existsSync(home), false);
});

test("doctor names the data folder and the command that removes it", () => {
  const home = path.join(tmp, "home-doctor-data");
  const row = doctor([], { ROC_MCP_HOME: home }, tmp).find((c) => c.name === "data folder");
  assert.match(row!.detail!, new RegExp(`^${home.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&")}\n.*roc-syntax-mcp uninstall`));
});

// npm reads `weaver` as a package name even when a folder of that name is here.
test("only what npm reads as a path is resolved as one", () => {
  for (const p of ["./weaver", "../weaver", ".", "~/weaver", "/abs/weaver", "weaver-1.0.0.tgz"]) {
    assert.equal(isPathSpec(p), true, p);
  }
  for (const p of ["weaver", "@roc-syntax/weaver", "owner/repo", "weaver@1.0.0", ".weaver"]) {
    assert.equal(isPathSpec(p), false, p);
  }
});

// The plugin folder is under the user's profile, and cmd.exe splits on spaces.
test("an argument for cmd.exe keeps its spaces", () => {
  assert.equal(quoteForCmd("install"), "install");
  assert.equal(quoteForCmd("C:\\Users\\Jo Doe\\plugins"), '"C:\\Users\\Jo Doe\\plugins"');
  assert.equal(quoteForCmd('a"b c'), '"a""b c"');
});

// -----------------------------------------------------------------------------
// budget
// -----------------------------------------------------------------------------

// The server cuts a tool at its ceiling. A plugin that alone is too big would be
// cut in every workspace, even with no other plugin installed.

test("budget passes a plugin that fits every tool, and fails one that alone does not", async () => {
  const topic = (name: string) => ({ name, file: "topics/t.roc", description: "A topic.", keywords: [name] });
  const small = ray({ name: "ray-small", checks: ["topics"], topics: [topic("small_drawing")] }, { "topics/t.roc": "x\n" });
  const fits = await budgetCheck(small);
  assert.equal(fits.status, "ok", fits.detail);
  assert.match(fits.detail!, /^search\s+\+\d+$/m);

  const many = Array.from({ length: 30 }, (_, i) => topic(`a_rather_long_topic_name_number_${i}`));
  const big = ray({ name: "ray-big", checks: ["topics"], topics: many }, { "topics/t.roc": "x\n" });
  const over = await budgetCheck(big);
  assert.equal(over.status, "fail", over.detail);
  assert.match(over.detail!, /get_roc_syntax\s+\+\d+, over the ceiling/);
});
