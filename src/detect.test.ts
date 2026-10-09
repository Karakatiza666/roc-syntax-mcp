// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  DetectionCache,
  appPins,
  compareVersions,
  detectAt,
  matchPlatformRef,
  mismatchNote,
  platformRef,
  searchPath,
} from "./detect.ts";
import { CORE } from "./scopes.ts";

const BUNDLED = "0.17.0";
const url = (v: string) =>
  `https://github.com/roc-lang/basic-webserver/releases/download/${v}/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst`;

const appFile = (v: string) => `app [Context, program] {
\tpf: platform "${url(v)}",
\thttp: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server

Context : {}
`;

let tmp: string;
before(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roc-detect-"));
});
after(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

/** A workspace with a `.git` marker, so the walk up has somewhere to stop. */
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

// -----------------------------------------------------------------------------
// Reading the header
// -----------------------------------------------------------------------------

test("the platform reference is read out of a multi-line app header", () => {
  assert.equal(platformRef(appFile("0.17.0")), url("0.17.0"));
  assert.equal(platformRef('app [main!] { pf: platform "../platform/main.roc" }'), "../platform/main.roc");
});

test("a module or package file is not an app", () => {
  assert.equal(platformRef("module [Foo]\n\nFoo : U64\n"), null);
  assert.equal(platformRef('package [Http] { }\n'), null);
  // The word `app` inside a doc comment is not a header.
  assert.equal(platformRef("## An app [like this] needs a platform\nmodule []\n"), null);
});

test("a recognized platform URL yields its scope and pin", () => {
  assert.deepEqual(matchPlatformRef(url("0.15.0"), CORE), { scope: "basic-webserver", version: "0.15.0" });
  assert.deepEqual(
    matchPlatformRef("https://github.com/roc-lang/basic-cli/releases/download/0.21.0/x.tar.zst", CORE),
    { scope: "basic-cli", version: "0.21.0" }
  );
  assert.equal(matchPlatformRef("../platform/main.roc", CORE), null);
  // The version is the whole tag, with its prerelease tail. A plugin pinned to
  // `0.10.0-rc3` compares against the exact tag in the header.
  assert.deepEqual(
    matchPlatformRef("https://github.com/roc-lang/basic-cli/releases/download/0.21.0-rc2/x.tar.zst", CORE),
    { scope: "basic-cli", version: "0.21.0-rc2" }
  );
  // A platform that this server does not bundle is unrecognized, whoever publishes it.
  assert.equal(matchPlatformRef("https://github.com/roc-lang/basic-ssg/releases/download/0.1.0/x.tar.zst", CORE), null);
});

// The header binds the app's packages next to its platform, and only the header
// says what the app compiles against. If detection read only `pf:`, the server
// would not see a package that the platform does not declare.
test("the app header's package pins are read beside the platform", () => {
  assert.deepEqual(appPins(appFile("0.17.0")), [
    {
      alias: "http",
      id: "roc-lang/http",
      version: "1.0.0",
      url: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
      requiredBy: "app",
    },
  ]);
});

test("a pin that is not a release URL is not a namespace", () => {
  const local = `app [main!] {
\tpf: platform "../platform/main.roc",
\tlocal: "../vendor/thing/main.roc",
}
`;
  assert.deepEqual(appPins(local), []);
  // A file with no app header pins nothing, and the parse does not throw.
  assert.deepEqual(appPins("module [x]\n\nx = 1\n"), []);
});

test("versions order numerically, not lexically", () => {
  assert.equal(compareVersions("0.9.0", "0.16.0"), -1);
  assert.equal(compareVersions("0.16.0", "0.16.0"), 0);
  assert.equal(compareVersions("0.18.0", "0.16.0"), 1);
  assert.equal(compareVersions("1.0", "1.0.0"), 0);
});

// roc-ray's current release is `0.10.0-rc3`, so real pins carry prerelease
// tails. The first case is the most important. An app that pins exactly the
// release a corpus documents must compare equal. A parse of `0-rc3` as a number
// makes the tag `newer` than itself.
test("a prerelease tag orders below the release it leads to", () => {
  assert.equal(compareVersions("0.10.0-rc3", "0.10.0-rc3"), 0);
  assert.equal(compareVersions("0.10.0-rc3", "0.10.0"), -1);
  assert.equal(compareVersions("0.10.0", "0.10.0-rc3"), 1);
  assert.equal(compareVersions("0.10.0-rc2", "0.10.0-rc3"), -1);
  assert.equal(compareVersions("0.9.0", "0.10.0-rc1"), -1);
  // Dotted identifiers. Numeric identifiers order as numbers, not as text.
  assert.equal(compareVersions("1.0.0-rc.2", "1.0.0-rc.10"), -1);
  assert.equal(compareVersions("1.0.0-alpha", "1.0.0-beta"), -1);
});

// -----------------------------------------------------------------------------
// Walking
// -----------------------------------------------------------------------------

test("the search path stops at the git root", () => {
  const root = workspace("stops", { "src/nested/keep.txt": "" });
  const dirs = searchPath(path.join(root, "src", "nested"));
  assert.deepEqual(dirs, [path.join(root, "src", "nested"), path.join(root, "src"), root]);
});

// A CLI launched from `src/` reports `src/` as both cwd and root. Without the
// walk up, detection misses an app file at the repo root.
test("an app at the repo root is found from a subdirectory", () => {
  const root = workspace("walkup", { "main.roc": appFile(BUNDLED), "src/helper.roc": "module [x]\n" });
  const d = detectAt(path.join(root, "src"), 1000, CORE);
  assert.equal(d.scope, "basic-webserver");
  assert.equal(d.detectedVersion, BUNDLED);
  assert.equal(d.relation, "match");
  assert.equal(path.basename(d.sourceFile!), "main.roc");
});

// The pins must come from the same header as the platform. A second pass over
// the directory could pair the platform of one app with the packages of another.
test("a detection carries the pins of the header it read", () => {
  const root = workspace("pins", {
    "aaa-other.roc": 'app [main!] { pf: platform "../platform/main.roc" }\n',
    "zzz-real.roc": appFile(BUNDLED),
  });
  const d = detectAt(root, 1000, CORE);
  assert.equal(path.basename(d.sourceFile!), "zzz-real.roc");
  assert.deepEqual(d.packages, [
    {
      alias: "http",
      id: "roc-lang/http",
      version: "1.0.0",
      url: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
      requiredBy: "app",
    },
  ]);
});

test("a workspace with no app header detects nothing", () => {
  const root = workspace("bare", { "lib.roc": "module [x]\n\nx = 1\n" });
  const d = detectAt(root, 1000, CORE);
  assert.equal(d.scope, null);
  assert.equal(d.relation, null);
  assert.deepEqual(d.packages, []);
  assert.equal(mismatchNote(d, CORE), null);
});

test("a local platform is reported, not silently ignored", () => {
  const root = workspace("author", { "app.roc": 'app [main!] { pf: platform "../platform/main.roc" }\n' });
  const d = detectAt(root, 1000, CORE);
  assert.equal(d.scope, null);
  assert.equal(d.relation, "unrecognized");
  assert.match(mismatchNote(d, CORE)!, /search_project_symbols/);
});

// A platform author's checkout holds both a real app and a stub. Detection must
// index against the real app.
test("a recognized platform wins over a local one in the same directory", () => {
  const root = workspace("mixed", {
    "aaa-stub.roc": 'app [main!] { pf: platform "../platform/main.roc" }\n',
    "zzz-real.roc": appFile(BUNDLED),
  });
  const d = detectAt(root, 1000, CORE);
  assert.equal(d.scope, "basic-webserver");
});

// -----------------------------------------------------------------------------
// Mismatch
// -----------------------------------------------------------------------------

test("a matching pin says nothing", () => {
  const root = workspace("same", { "main.roc": appFile(BUNDLED) });
  assert.equal(mismatchNote(detectAt(root, 1000, CORE), CORE), null);
});

// A real case: every example in the upstream 0.17.0 tag pins 0.16.0.
test("an older pin warns that new APIs will not compile", () => {
  const root = workspace("older", { "main.roc": appFile("0.15.0") });
  const d = detectAt(root, 1000, CORE);
  assert.equal(d.relation, "older");
  const note = mismatchNote(d, CORE)!;
  assert.match(note, /pins basic-webserver 0\.15\.0/);
  assert.match(note, /bundles 0\.17\.0/);
  assert.match(note, /will not compile/);
});

test("a newer pin warns that the index is a lower bound", () => {
  const root = workspace("newer", { "main.roc": appFile("0.18.0") });
  const d = detectAt(root, 1000, CORE);
  assert.equal(d.relation, "newer");
  assert.match(mismatchNote(d, CORE)!, /lower bound/);
});

// -----------------------------------------------------------------------------
// Cache
// -----------------------------------------------------------------------------

test("a result is reused until the TTL expires, then rewalked", () => {
  const root = workspace("ttl", { "main.roc": appFile("0.15.0") });
  const cache = new DetectionCache(CORE, 1000);

  const first = cache.get(root, 0);
  assert.equal(first.detectedVersion, "0.15.0");

  fs.writeFileSync(path.join(root, "main.roc"), appFile(BUNDLED));
  assert.equal(cache.get(root, 999).detectedVersion, "0.15.0", "rewalked inside the TTL");
  assert.equal(cache.get(root, 1001).detectedVersion, BUNDLED, "did not rewalk after the TTL");
});

// An agent that prototypes with `scope` writes the header next, so a result
// with no header must not stay cached for a day as a found header does.
test("no app header is rechecked within seconds, a found one is kept", () => {
  const root = workspace("header-later", { "lib.roc": "module [x]\n\nx = 1\n" });
  const cache = new DetectionCache(CORE);
  assert.equal(cache.get(root, 0).scope, null);

  fs.writeFileSync(path.join(root, "main.roc"), appFile(BUNDLED));
  assert.equal(cache.get(root, 4_000).scope, null, "rewalked an empty result too soon");
  assert.equal(cache.get(root, 5_001).scope, "basic-webserver", "the new header was not seen");

  fs.rmSync(path.join(root, "main.roc"));
  assert.equal(cache.get(root, 60_000).scope, "basic-webserver", "a found header expired early");
});

// The server emits the mismatch note once per root per TTL. The `warned` flag
// is on the cached object, so a second call inside the TTL must see the flag
// that the first call set.
test("the warned flag survives a cache hit", () => {
  const root = workspace("warned", { "main.roc": appFile("0.15.0") });
  const cache = new DetectionCache(CORE, 1000);
  cache.get(root, 0).warned = true;
  assert.equal(cache.get(root, 500).warned, true);
});

test("roots/list_changed drops every cached root", () => {
  const root = workspace("invalidate", { "main.roc": appFile("0.15.0") });
  const cache = new DetectionCache(CORE);
  cache.get(root, 0).warned = true;
  cache.invalidate();
  assert.equal(cache.size, 0);
  assert.equal(cache.get(root, 1).warned, false);
});

// -----------------------------------------------------------------------------
// Detection of the bundled corpus
// -----------------------------------------------------------------------------

test("the bundled examples detect as basic-webserver", () => {
  const examples = path.join(import.meta.dirname, "..", "corpus", "platforms", "basic-webserver", "examples");
  const d = detectAt(examples, 1000, CORE);
  assert.equal(d.scope, "basic-webserver");
  assert.equal(d.detectedVersion, BUNDLED, "the examples were repinned to the bundled version");
  assert.equal(d.relation, "match");
});
