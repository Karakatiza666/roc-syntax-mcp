// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Tests for releases that the server reads from a pre-built index or from the
// package cache of the compiler, and for the fetch that fills the cache.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  cachedReleaseDir,
  fetchReleases,
  fetchStub,
  headerKind,
  packageCacheDirs,
  releaseHash,
  snapshotDir,
} from "./release.ts";
import { CACHE_PROVIDER, ROOT, ScopeRegistry, readIndexFiles } from "./scopes.ts";

/** A hash in the alphabet the compiler writes, which has no 0, O, I or l. */
const HASH = "FakeRe1easeHashForTests1234567891234567891234";
const rand = (version: string, hash = HASH) =>
  `https://github.com/kili-ilo/roc-random/releases/download/${version}/${hash}.tar.zst`;

let tmp: string;
let cache: string;
before(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roc-release-"));
  cache = path.join(tmp, "cache");
  fs.mkdirSync(cache);
  process.env.ROC_PACKAGE_CACHE = cache;
});
after(() => {
  delete process.env.ROC_PACKAGE_CACHE;
  fs.rmSync(tmp, { recursive: true, force: true });
});

function tree(dir: string, files: Record<string, string>): string {
  fs.mkdirSync(dir, { recursive: true });
  for (const [name, content] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), content);
  return dir;
}

const RANDOM_TREE = {
  "main.roc": "package [Random] {}\n",
  "Random.roc": "Random := [].{\n\t## Only in the release the app pins.\n\tbrand_new : U64 -> U64\n}\n",
};

test("a release hash is read off the tarball URL", () => {
  assert.equal(releaseHash(rand("0.9.2")), HASH);
  assert.equal(releaseHash(rand("0.9.2").replace(".zst", ".br")), HASH);
  // A local path and a short name are not releases. The function does not
  // check the alphabet, because the compiler checks the hash and the
  // placeholder from `plugin init` must load.
  assert.equal(releaseHash("../platform/main.roc"), null);
  assert.equal(releaseHash(rand("0.9.2", "AAAA")), null);
  assert.equal(releaseHash(rand("0.9.2", "REPLACE_WITH_THE_TARBALL")), "REPLACE_WITH_THE_TARBALL");
});

// If the stub pins basic-cli 0.24.0 as a package, the 10 MB package limit of
// the compiler applies and `roc deps` refuses it. If the stub pins a package
// as a platform, `roc deps` unpacks it into the cache before it reports
// "invalid platform". Measured on nightly 130536d. Thus no fetch has to know
// the kind of a release.
test("the fetch stub pins every release as a platform", () => {
  assert.match(fetchStub(rand("1.0.0")), /pf: platform "https:/);
});

test("a header says whether its release is a platform or a package", () => {
  assert.equal(headerKind('platform ""\n    exposes []\n'), "platform");
  assert.equal(headerKind("## A doc line first.\n\npackage [Random] {}\n"), "package");
  assert.equal(headerKind("app [main!] {}\n"), null);
});

test("the package cache follows the compiler's own lookup, with an override", () => {
  assert.deepEqual(packageCacheDirs({ ROC_PACKAGE_CACHE: "/x" }), ["/x"]);
  const dirs = packageCacheDirs({ XDG_CACHE_HOME: "/xdg" });
  assert.equal(dirs[0], path.join("/xdg", "roc", "packages"));
  assert.equal(dirs[1], path.join(os.homedir(), ".cache", "roc", "packages"));
});

test("a snapshot carries the header's exposes and pins, and each module's imports", () => {
  const dir = tree(path.join(tmp, "snap"), {
    "main.roc":
      'platform ""\n\texposes [Draw]\n\tpackages {\n\t\thttp: "https://github.com/roc-lang/http/releases/download/1.0.0/X.tar.zst",\n\t}\n',
    "Draw.roc": "import http.Request\nimport Host\n\nDraw := [].{\n\tcircle! : F32 => {}\n}\n",
    "Host.roc": "Host := [].{\n\tgo! : {} => {}\n}\n",
  });
  const snap = snapshotDir(dir, "main.roc")!;
  assert.equal(snap.kind, "platform");
  assert.deepEqual(snap.exposes, ["Draw"]);
  assert.deepEqual(snap.deps, [
    { alias: "http", url: "https://github.com/roc-lang/http/releases/download/1.0.0/X.tar.zst" },
  ]);
  assert.deepEqual(
    snap.modules.map((m) => [m.name, m.imports]),
    [["Draw", ["http"]], ["Host", []], ["main", []]]
  );
  assert.equal(snapshotDir(path.join(tmp, "absent")), null);
});

// The exact bytes that an app compiles against win over a corpus that
// documents a different release. Without the cache, the bundled 0.9.2 answers,
// and the conflict note tells that the two releases differ.
test("a package pinned at a release no corpus serves is read from the cache", () => {
  const pin = { alias: "rand", id: "kili-ilo/roc-random", version: "9.9.9", url: rand("9.9.9"), requiredBy: "app" as const };
  const registry = new ScopeRegistry(ROOT);
  registry.setWorkspacePins([pin]);

  const before = registry.spacePackages(null)[0];
  assert.equal(before.provider?.version, "0.9.2", "the bundled release answers until the cache has it");
  assert.deepEqual(registry.wantedReleases(null), [rand("9.9.9")]);

  tree(path.join(cache, HASH), RANDOM_TREE);
  registry.refresh();
  const after = registry.spacePackages(null)[0];
  assert.equal(after.provider?.from, CACHE_PROVIDER);
  assert.equal(after.provider?.tier, 0);
  assert.deepEqual(registry.wantedReleases(null), []);
  const item = registry.addressSpace(null).byFullName.get("Random.brand_new");
  assert.equal(item?.origin, "roc-random 9.9.9");
  fs.rmSync(path.join(cache, HASH), { recursive: true });
});

// No corpus documents this package, so only the pin in the app indexes it.
test("a package no corpus documents is read from the cache the app pin names", () => {
  const url = `https://github.com/someone/roc-dice/releases/download/1.0.0/${HASH}.tar.zst`;
  const registry = new ScopeRegistry(ROOT);
  registry.setWorkspacePins([{ alias: "dice", id: "someone/roc-dice", version: "1.0.0", url, requiredBy: "app" }]);
  assert.equal(registry.spacePackages(null)[0].provider, null, "nothing serves it until the cache has it");
  assert.deepEqual(registry.wantedReleases(null), [url]);

  tree(path.join(cache, HASH), RANDOM_TREE);
  registry.refresh();
  assert.equal(registry.spacePackages(null)[0].provider?.from, CACHE_PROVIDER);
  assert.equal(registry.addressSpace(null).byFullName.get("Random.brand_new")?.origin, "roc-dice 1.0.0");
  fs.rmSync(path.join(cache, HASH), { recursive: true });
});

// The server never fetches a release that a corpus documents, whatever the
// cache holds, because the check scripts measured the pre-built index.
test("a pinned release a corpus serves is read from its index, never fetched", () => {
  const registry = new ScopeRegistry(ROOT);
  registry.setWorkspacePins([
    {
      alias: "rand",
      id: "kili-ilo/roc-random",
      version: "0.9.2",
      url: rand("0.9.2", "2ZXLX8WRqrosGu1V3VL5aXqgtfTRvJmjFPx8a26ecVmc"),
      requiredBy: "app",
    },
  ]);
  assert.deepEqual(registry.wantedReleases(null), []);
  assert.equal(registry.spacePackages(null)[0].provider?.tier, 3);
});

test("fetching runs `roc deps` once per missing release and reports what is still missing", async () => {
  const bin = tree(path.join(tmp, "bin"), {});
  const log = path.join(tmp, "calls.log");
  const roc = path.join(bin, "roc");
  // Unpacks a fixed tree under the hash that the stub pins, as the compiler
  // does. A URL with the tag 6.6.6 fails.
  fs.writeFileSync(
    roc,
    `#!/bin/sh
echo "$@" >> "${log}"
url=$(grep -o 'https://[^"]*' "$2")
case "$url" in */6.6.6/*) exit 1 ;; esac
hash=$(basename "$url" | sed 's/[.]tar[.].*//')
mkdir -p "${cache}/$hash"
printf 'package [Random] {}\\n' > "${cache}/$hash/main.roc"
`,
    { mode: 0o755 }
  );
  const good = rand("9.9.9");
  const bad = rand("6.6.6", "Bad" + HASH.slice(3));
  const missing = await fetchReleases([good, good, bad], { roc });
  assert.deepEqual(missing, [bad]);
  assert.ok(cachedReleaseDir(good));
  assert.equal(fs.readFileSync(log, "utf-8").trim().split("\n").length, 2, "one run per distinct release");
  // The release is in the cache, so a second fetch runs nothing.
  assert.deepEqual(await fetchReleases([good], { roc }), []);
  assert.equal(fs.readFileSync(log, "utf-8").trim().split("\n").length, 2);
  fs.rmSync(path.join(cache, HASH), { recursive: true });
});

// One hash identifies one set of bytes, so a second snapshot of that hash is
// either the same or wrong. The server reads its own index files first. A
// plugin must never replace what this server serves for a release that it
// documents.

test("the first index file to hold a release is the one read", () => {
  const ours = path.join(tmp, "ours.json");
  const theirs = path.join(tmp, "theirs.json");
  const snap = (name: string) => ({ kind: "package", exposes: [name], deps: [], modules: [] });
  fs.writeFileSync(ours, JSON.stringify({ format: 1, releases: { [HASH]: { url: rand("1.0.0"), snapshot: snap("Ours") } } }));
  fs.writeFileSync(theirs, JSON.stringify({ format: 1, releases: { [HASH]: { url: rand("1.0.0"), snapshot: snap("Theirs") } } }));
  assert.deepEqual(readIndexFiles([ours, theirs]).get(HASH)?.exposes, ["Ours"]);
});
