// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  type PackageProvider,
  type PluginManifest,
  CORE,
  HOST_PACKAGES,
  SCHEMA_VERSION,
  detectPattern,
  fromManifest,
  PURPOSE_MAX,
  ScopeRegistry,
  formatPackageNote,
  formatPinConflict,
  manifestPaths,
  parseExposes,
  parsePackageDeps,
  pinFromUrl,
  readIndexFiles,
  resolvePackage,
} from "./scopes.ts";
import { indexText, releaseHash, type TreeSnapshot } from "./release.ts";
import { snippets } from "./plugin_cli.ts";

const { scopes: SCOPES, scopeDefs: SCOPE_DEFS, platformScopes: PLATFORM_SCOPES, packageDocs: PACKAGE_DOCS } = CORE;

const ROOT = path.join(import.meta.dirname, "..");
const registry = new ScopeRegistry(ROOT);

// -----------------------------------------------------------------------------
// Corpora
// -----------------------------------------------------------------------------

test("every scope in the registry has the content it declares", () => {
  for (const name of SCOPES) {
    const def = SCOPE_DEFS[name];
    if (def.overview) {
      const page = path.join(ROOT, def.overview);
      assert.ok(fs.existsSync(page), `${name} declares ${def.overview}, which does not exist`);
    }
    for (const md of def.modules) {
      if (md.dir !== undefined) {
        assert.ok(fs.existsSync(path.join(ROOT, md.dir)), `${name} declares ${md.dir}, which does not exist`);
      } else {
        assert.ok(new ScopeRegistry(ROOT).tree(md), `${name} declares ${md.release}, which no index.json holds`);
      }
    }
    if (def.examples) {
      assert.ok(fs.existsSync(path.join(ROOT, def.examples)), `${name} declares ${def.examples}`);
    }
  }
});

test("the corpora are the sizes the plan was written against", () => {
  const builtin = registry.index("builtin");
  assert.equal(builtin.items.filter((i) => i.kind === "value").length, 2298);
  assert.equal(builtin.items.filter((i) => i.kind === "type").length, 29);

  const bws = registry.index("basic-webserver");
  assert.equal(bws.items.filter((i) => i.tier === "host").length, 141);
  // `Sse.from_state` is an annotated binding inside the body of `Sse.unfold!`,
  // so it is not a member of the module, and this count excludes it.
  assert.equal(bws.items.filter((i) => i.tier === "public").length, 468);
  assert.equal(bws.items.filter((i) => i.tier === "private").length, 2);

  const cli = registry.index("basic-cli");
  assert.equal(cli.items.filter((i) => i.tier === "host").length, 120);
  assert.equal(cli.items.filter((i) => i.tier === "public").length, 290);
  assert.equal(cli.items.filter((i) => i.tier === "private").length, 0);
});

// An app pins one platform, so one address space never resolves both platforms,
// and their 197 shared names never compete.
const SHARED = ["Cmd.exec!", "Path.read_utf8!", "Sqlite.execute!", "IOErr"];

test("an address space holds one platform, so nothing in it collides", () => {
  for (const platform of PLATFORM_SCOPES) {
    const space = registry.addressSpace(platform);
    // Within one namespace a repeated name is a parser bug. Across namespaces it
    // is legal, but no shipped corpus does it. The http package uses Header,
    // Method, Request and Response, and each platform's client module is Http.
    const seen = new Set<string>();
    for (const item of space.items) {
      const key = `${item.ns}\u0000${item.fullName}`;
      assert.ok(!seen.has(key), `${item.fullName} appears twice in ${item.ns}`);
      seen.add(key);
    }
    assert.deepEqual([...space.collisions.keys()], [], `${platform} shipped a collision`);
    for (const name of SHARED) {
      assert.equal(space.byFullName.get(name)?.scope, platform, `${name} came from elsewhere`);
    }
  }
});

test("a platform outside the space is absent rather than mixed in", () => {
  const cli = registry.addressSpace("basic-cli");
  assert.ok(!cli.byFullName.has("Server.Outcome"), "basic-webserver leaked into basic-cli");
  assert.ok(cli.byFullName.has("Utc.now!"), "basic-cli lost its own item");
  // The language and the builtins are in every address space. A platform is in its own only.
  assert.ok(cli.byFullName.has("Str.concat"), "the builtins left the address space");
});

// A workspace that names no platform gets an address space with no platform,
// not a guessed one.
test("with no platform pinned, no platform is in the space", () => {
  const unpinned = registry.addressSpace(null);
  for (const name of [...SHARED, "Server.Outcome", "Utc.now!", "Response.status"]) {
    assert.ok(!unpinned.byFullName.has(name), `${name} was resolvable with nothing pinned`);
  }
  assert.ok(unpinned.byFullName.has("Str.concat"), "the builtins left the address space");
  assert.deepEqual([...new Set(unpinned.items.map((i) => i.scope))], ["builtin"]);
});

// Both platform scopes list the http package, and this server vendors it once.
// A merged lookup must not print every Response method twice.
test("the shared http package reaches both platforms and neither twice", () => {
  for (const scope of PLATFORM_SCOPES) {
    const space = registry.addressSpace(scope);
    for (const name of ["Response.status", "Request.from_method", "Method", "Header"]) {
      const item = space.byFullName.get(name);
      assert.ok(item, `${scope} lost ${name}`);
      assert.equal(item!.origin, "http 1.0.0");
      assert.equal(space.items.filter((i) => i.fullName === name).length, 1);
    }
  }
});

// A collision inside one corpus would be a parser bug.
test("no fullName collides within a single scope", () => {
  for (const scope of SCOPES) {
    const seen = new Set<string>();
    const clashes: string[] = [];
    for (const item of registry.index(scope).items) {
      if (seen.has(item.fullName)) clashes.push(item.fullName);
      seen.add(item.fullName);
    }
    assert.deepEqual(clashes, [], `${scope} declares a name twice`);
  }
});

// -----------------------------------------------------------------------------
// Namespaces and packages
// -----------------------------------------------------------------------------

/** The http pin, as both platform headers declare it. */
const HTTP_URL =
  "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst";
const HTTP_DEP = { alias: "http", id: "roc-lang/http", version: "1.0.0", url: HTTP_URL };

/** The pre-built snapshot of the release a platform's manifest names. */
function platformSnapshot(platform: string): TreeSnapshot {
  const release = SCOPE_DEFS[platform].modules[0].release!;
  const snap = readIndexFiles([path.join(ROOT, "corpus", "platforms", platform, "index.json")]).get(
    releaseHash(release)!
  );
  assert.ok(snap, `${platform}'s index.json has no snapshot of ${release}`);
  return snap!;
}

/** A package plugin serving `src/testdata/http-fork` as roc-lang/http. */
const fork = (version: string, tier: 1 | 3 = 1): PackageProvider => ({
  id: "roc-lang/http",
  version,
  dir: "src/testdata/http-fork",
  from: "@test/http-fork",
  tier,
});

test("every item carries the namespace it came from", () => {
  assert.equal(registry.index("builtin").byFullName.get("Str.concat")!.ns, "builtin");
  const cli = registry.index("basic-cli");
  assert.equal(cli.byFullName.get("Utc.now!")!.ns, "platform:basic-cli");
  assert.equal(cli.byFullName.get("Response.status")!.ns, "pkg:roc-lang/http");
  // A package has one namespace, whichever platform pins it. Otherwise a package
  // plugin would have to exist once per platform that re-exports it.
  const bws = registry.index("basic-webserver");
  assert.equal(bws.byFullName.get("Response.status")!.ns, "pkg:roc-lang/http");
  assert.equal(bws.byFullName.get("Server.Outcome")!.ns, "platform:basic-webserver");
});

// A pin declared next to the corpus would let a refresh repin the header and
// leave a second, stale copy. The platform was compiled against its header, so
// the registry reads the header.
test("a platform's packages are read from its header, not declared beside it", () => {
  for (const platform of ["basic-webserver", "basic-cli"] as const) {
    assert.deepEqual(
      platformSnapshot(platform).deps,
      [{ alias: "http", url: HTTP_URL }],
      `${platform}'s header pins something else`
    );
  }
  assert.deepEqual(parsePackageDeps("module [Thing]\n"), []);
  // A local path pin has no repo and no release, so it is nobody else's namespace.
  assert.deepEqual(parsePackageDeps('packages {\n\tlocal: "../thing/main.roc",\n}\n'), []);
});

// A package header gives both lists with no keyword before either. The public
// modules are the bracket group after `package`, and the dependencies are the
// brace group after that. With only the platform rules, a package exposes
// nothing and pins nothing, and its whole corpus goes to host tier.
const PACKAGE_HEADER = `package
	[
		Cli,
		Opt,
	]
	{
		ansi: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/A.tar.zst",
		path: "https://github.com/roc-lang/path/releases/download/4.0.0/B.tar.zst",
	}

import CliTest
`;

test("a package header's public modules and pins are read like a platform's", () => {
  assert.deepEqual(parseExposes(PACKAGE_HEADER), ["Cli", "Opt"]);
  assert.deepEqual(parsePackageDeps(PACKAGE_HEADER), [
    {
      alias: "ansi",
      id: "lukewilliamboswell/roc-ansi",
      version: "0.13.0",
      url: "https://github.com/lukewilliamboswell/roc-ansi/releases/download/0.13.0/A.tar.zst",
    },
    {
      alias: "path",
      id: "roc-lang/path",
      version: "4.0.0",
      url: "https://github.com/roc-lang/path/releases/download/4.0.0/B.tar.zst",
    },
  ]);
  // An app header's own bracket group is lowercase and names no module.
  assert.deepEqual(parseExposes('app [main!] { pf: platform "x" }\n'), []);
});

// Whether a package's types appear in the platform's exposed API decides
// whether another release can compile. The registry computes this, because a
// manifest value would be a claim about someone else's code.
test("the boundary a package crosses is read off the exposed modules", () => {
  assert.deepEqual(registry.packages("basic-webserver")[0].crossing, [
    "Http",
    "MultipartFormData",
    "Server",
  ]);
  // InternalHttp also imports the package, but it is not exposed, so no app can
  // get its types through the platform's API.
  assert.deepEqual(registry.packages("basic-cli")[0].crossing, ["Http"]);
});

test("a package plugin at the pinned release wins over what this server vendors", () => {
  const r = new ScopeRegistry(ROOT, { providers: [fork("1.0.0")] });
  assert.equal(r.packages("basic-cli")[0].provider?.from, "@test/http-fork");
  assert.ok(r.index("basic-cli").byFullName.has("Response.is_ok"), "the plugin's copy is not indexed");
});

// Two copies of one package with different content are two nominal types, and
// the compiler names both `Response`. Where the package crosses the platform's
// API, documentation for the other release describes an app that cannot compile.
test("a release the platform's API will not take is refused, and the vendored copy answers", () => {
  const r = new ScopeRegistry(ROOT, { providers: [fork("1.2.0")] });
  const [http] = r.packages("basic-cli");
  assert.equal(http.provider?.from, "roc-syntax-mcp");
  assert.deepEqual(
    http.refused.map((x) => `${x.from} ${x.version}`),
    ["@test/http-fork 1.2.0"]
  );
  const cli = r.index("basic-cli");
  assert.equal(cli.byFullName.get("Response.status")!.origin, "http 1.0.0");
  assert.ok(!cli.byFullName.has("Response.is_ok"), "the refused copy was indexed anyway");
});

test("a different release is taken where the package never crosses the boundary", () => {
  const res = resolvePackage(HTTP_DEP, [fork("1.2.0")], [], false);
  assert.equal(res.provider?.version, "1.2.0");
  assert.deepEqual(res.refused, []);
});

// The check for the platform's API reads the corpus and over-approximates, so a
// plugin author may know better. A forced namespace prints its release on every
// item it returns, so the override stays visible.
test("force overrides the refusal, and every item then prints the release it is", () => {
  const r = new ScopeRegistry(ROOT, { providers: [fork("1.2.0")], force: ["roc-lang/http"] });
  assert.equal(r.packages("basic-cli")[0].provider?.version, "1.2.0");
  assert.equal(r.index("basic-cli").byFullName.get("Response.is_ok")!.origin, "http 1.2.0");
});

// After a refusal, resolution tries the next tier, and every tier may refuse.
// The result is then a namespace with no provider, and the server must report it.
test("a namespace no provider can serve is left empty and says so", () => {
  const stale = { ...fork("1.1.0"), from: "roc-syntax-mcp", tier: 3 as const };
  const res = resolvePackage(HTTP_DEP, [stale, fork("1.2.0")], ["Http"], false);
  assert.equal(res.provider, null);
  assert.deepEqual(
    res.refused.map((x) => `${x.from} ${x.version}`),
    ["@test/http-fork 1.2.0", "roc-syntax-mcp 1.1.0"],
    "tiers were not tried in order"
  );
  assert.equal(
    formatPackageNote("roc-ray", "0.7.0", [res]),
    "No provider serves roc-lang/http.\n" +
      "roc-ray 0.7.0 requires 1.0.0; @test/http-fork serves 1.2.0; roc-syntax-mcp serves 1.1.0.\n" +
      "Install a package plugin at 1.0.0, or run this server with --force=roc-lang/http to read 1.2.0 anyway."
  );
  // No note when every namespace has a provider, as in the shipped corpora.
  assert.equal(formatPackageNote("basic-cli", "0.24.0", registry.packages("basic-cli")), null);
});

// -----------------------------------------------------------------------------
// What the workspace's own app header pins
// -----------------------------------------------------------------------------

/** A package plugin serving `src/testdata/http-fork` under a second package id. */
const json = (version: string): PackageProvider => ({
  id: "example/json",
  version,
  dir: "src/testdata/http-fork",
  from: "@test/json",
  tier: 1,
});

const jsonPin = { alias: "json", id: "example/json", version: "1.0.0", requiredBy: "app" as const };

// The platform's header names what the platform needs. The app's header names
// what the app imports, and the two lists can differ. An app can pin a package
// that its platform does not declare.
test("a package only the app pins joins the space, and no scope's own corpus", () => {
  const r = new ScopeRegistry(ROOT, { providers: [json("1.0.0")] });
  // Read first, so that the pins have a warm cache to invalidate. Detection is
  // asynchronous, and the registry must drop a space built before it completes.
  assert.equal(r.addressSpace("basic-webserver").items.filter((i) => i.ns === "pkg:example/json").length, 0);

  r.setWorkspacePins([jsonPin]);
  const space = r.addressSpace("basic-webserver");
  const mine = space.items.filter((i) => i.ns === "pkg:example/json");
  assert.ok(mine.length > 0, "the app's own pin never reached the space");
  assert.equal(mine[0].origin, "json 1.0.0");

  // A registry that has never built an index, so that no warm cache can hide a
  // broken rule. A scope's corpus is what this server ships, and a dependency of
  // one workspace is not part of it.
  const fresh = new ScopeRegistry(ROOT, { providers: [json("1.0.0")] });
  fresh.setWorkspacePins([jsonPin]);
  assert.equal(
    fresh.index("basic-webserver").items.filter((i) => i.ns === "pkg:example/json").length,
    0,
    "one workspace's pin was written into the shared corpus of a scope"
  );
});

// The app requires this package, not the platform. A note that names the
// platform would name a dependency that basic-webserver does not have.
test("a pin nothing serves is reported as the app's requirement, not the platform's", () => {
  const r = new ScopeRegistry(ROOT);
  r.setWorkspacePins([jsonPin]);
  assert.equal(
    r.packageNote("basic-webserver"),
    "No provider serves example/json.\n" +
      "Your app header pins 1.0.0.\n" +
      "Install a package plugin at 1.0.0."
  );
});

// An app on a platform that this server does not bundle still imports its
// packages. The registry reads them with the builtins in both cases, so the
// platform does not decide whether they are in the address space.
test("an app's pin reaches the space with no platform in it", () => {
  const r = new ScopeRegistry(ROOT, { providers: [json("1.0.0")] });
  r.setWorkspacePins([jsonPin]);
  const mine = r.addressSpace(null).items.filter((i) => i.ns === "pkg:example/json");
  assert.ok(mine.length > 0, "the pin was dropped for want of a platform");
  assert.equal(mine[0].scope, "builtin", "a pinned package is read with the builtins");

  // When nothing serves the package, no note would read as "that name does not
  // exist", which is wrong.
  const bare = new ScopeRegistry(ROOT);
  bare.setWorkspacePins([jsonPin]);
  assert.match(bare.packageNote(null)!, /No provider serves example\/json/);
});

// The compiler cannot give this message. Two copies of a package with different
// content are two nominal types, and the compiler diagnostic names both sides
// `Request` with no package. This server holds both pins, so it can name both.
test("an app pinning a release the platform's API refuses is told it will not compile", () => {
  const r = new ScopeRegistry(ROOT);
  r.setWorkspacePins([{ alias: "http", id: "roc-lang/http", version: "2.0.0", requiredBy: "app" }]);
  assert.equal(
    r.pinConflictNote("basic-cli"),
    "Your app pins roc-lang/http 2.0.0, and this server serves 1.0.0.\n" +
      "Http carries its types across basic-cli's API, so the two releases are different " +
      "types to the compiler and this app will not compile. Move the app's pin to 1.0.0, " +
      `which basic-cli ${SCOPE_DEFS["basic-cli"].version} requires.`
  );
  // The pin that the platform requires, as in the shipped corpora, gives no note.
  r.setWorkspacePins([{ alias: "http", id: "roc-lang/http", version: "1.0.0", requiredBy: "app" }]);
  assert.equal(r.pinConflictNote("basic-cli"), null);
});

// Where the package does not cross the platform's API, the app compiles. So the
// note is about which signatures the server shows, not about a type error.
test("an app pinning a release nothing crosses is told which one is indexed", () => {
  const res = resolvePackage({ ...jsonPin, version: "1.0.0" }, [json("2.0.0")], [], false, "1.0.0");
  assert.equal(res.provider?.version, "2.0.0");
  assert.equal(
    formatPinConflict(null, "", [res]),
    "Your app pins example/json 1.0.0, and this server serves 2.0.0.\n" +
      "Signatures shown for example/json are 2.0.0's. Verify with roc_check."
  );
});

// This collision is legal, unlike two platforms that both claim `Cmd.exec!`. An
// app reaches these names as `pf.Http` and `http.Http`, and both compile. A
// last-write-wins index would drop one with no message and could hide the one
// that the caller meant.
test("a name two namespaces claim keeps both, the platform's first", () => {
  const r = new ScopeRegistry(ROOT, { providers: [fork("1.0.0")] });
  const space = r.addressSpace("basic-cli");
  assert.deepEqual([...space.collisions.keys()], ["Http.send!"]);
  assert.deepEqual(space.collisions.get("Http.send!")!.map((i) => i.ns), [
    "platform:basic-cli",
    "pkg:roc-lang/http",
  ]);
  assert.equal(space.byFullName.get("Http.send!")!.ns, "platform:basic-cli");
});

// -----------------------------------------------------------------------------
// The host tier
// -----------------------------------------------------------------------------

test("exposes is read from the platform header, not hardcoded", () => {
  const read = (platform: string) => platformSnapshot(platform).exposes!;

  const bws = read("basic-webserver");
  assert.equal(bws.length, 19);
  assert.ok(bws.includes("Server") && bws.includes("Sqlite") && bws.includes("IOErr"));
  for (const hidden of ["Host", "InternalServer", "InternalSqlite", "SplitList"]) {
    assert.ok(!bws.includes(hidden), `${hidden} is exposed after all`);
  }

  const cli = read("basic-cli");
  assert.equal(cli.length, 19);
  assert.ok(cli.includes("Stdout") && cli.includes("Tty") && cli.includes("Utc"));
  for (const hidden of ["Host", "InternalDateTime", "InternalHttp", "InternalSqlite"]) {
    assert.ok(!cli.includes(hidden), `${hidden} is exposed after all`);
  }
});

test("a module the platform does not expose is entirely host-tier", () => {
  const bws = registry.index("basic-webserver");
  const cli = registry.index("basic-cli");
  for (const mod of ["Host", "InternalDateTime", "InternalHttp", "InternalSqlite"]) {
    const items = cli.items.filter((i) => i.module === mod);
    assert.ok(items.length > 0, `${mod} produced no items in basic-cli`);
    assert.deepEqual(
      items.filter((i) => i.tier !== "host").map((i) => i.fullName),
      [],
      `${mod} leaked app-facing items from basic-cli`
    );
  }
  for (const mod of ["Host", "InternalHttp", "InternalPath", "InternalServer", "InternalSqlite"]) {
    const items = bws.items.filter((i) => i.module === mod);
    assert.ok(items.length > 0, `${mod} produced no items`);
    assert.deepEqual(
      items.filter((i) => i.tier !== "host").map((i) => i.fullName),
      [],
      `${mod} leaked app-facing items`
    );
  }
});

test("the host tier is out of app-facing search but still addressable", () => {
  const app = registry.appFacing("basic-webserver").map((i) => i.fullName);
  const merged = registry.addressSpace("basic-webserver");
  for (const glue of ["Server.Config.to_host", "Server.Request.from_host", "Host.sqlite_open!"]) {
    assert.ok(!app.includes(glue), `${glue} is app-facing`);
    assert.ok(merged.byFullName.has(glue), `${glue} is not addressable`);
  }
});

// -----------------------------------------------------------------------------
// Naming
// -----------------------------------------------------------------------------

// A platform file is a module. A declaration that names the file is the module's
// own type, so `IOErr.roc` gives `IOErr`. The file name qualifies any other one.
test("a file-level declaration takes its name from the file", () => {
  const idx = registry.index("basic-webserver");
  for (const [name, module] of [
    ["IOErr", "IOErr"],
    ["Url", "Url"],
    ["OsStr", "OsStr"],
  ] as const) {
    const item = idx.byFullName.get(name);
    assert.ok(item, `${name} missing`);
    assert.equal(item!.module, module);
    assert.equal(item!.tier, "public");
  }
  assert.ok(!idx.byFullName.has("IOErr.IOErr"), "the module's own type was double-qualified");
});

// `roc check` rejects `Html.HtmlNode`: it is declared outside `Html :: [].{`, so
// no application can name it. `Html.Node` is the alias inside the block. Both
// are indexed, because a public signature mentions the private name, but only
// the reachable one may reach app-facing search.
test("a file-level type that does not name its file is private, not public", () => {
  const idx = registry.index("basic-webserver");
  const app = registry.appFacing("basic-webserver").map((i) => i.fullName);
  for (const [privateName, alias] of [
    ["Html.HtmlNode", "Html.Node"],
    ["MultipartFormData.ParsedFormData", "MultipartFormData.FormData"],
  ] as const) {
    assert.equal(idx.byFullName.get(privateName)?.tier, "private", `${privateName} is not private`);
    assert.ok(!app.includes(privateName), `${privateName} reached app-facing search`);
    assert.equal(idx.byFullName.get(alias)?.tier, "public", `${alias} is not the public alias`);
  }
});

test("items carry the package they ship in", () => {
  const idx = registry.index("basic-webserver");
  assert.equal(idx.byFullName.get("Method")!.origin, "http 1.0.0");
  assert.equal(idx.byFullName.get("Server.Outcome")!.origin, "basic-webserver 0.17.0");
  assert.equal(registry.index("builtin").byFullName.get("Str.concat")!.origin, "Builtin.roc");
});

test("Method and IOErr resolve with their variants", () => {
  const idx = registry.addressSpace("basic-webserver");
  const method = idx.byFullName.get("Method");
  assert.ok(method, "Method missing");
  assert.equal(method!.kind, "type");
  // Uppercase tags: a model that writes `Get` does not compile.
  for (const tag of ["OPTIONS", "GET", "POST", "PUT", "DELETE", "HEAD", "TRACE", "CONNECT",
                     "PATCH", "QUERY", "Unknown(Str)"]) {
    assert.ok(method!.signature.includes(tag), `Method is missing ${tag}`);
  }

  const ioerr = idx.byFullName.get("IOErr");
  assert.ok(ioerr, "IOErr missing");
  for (const tag of ["AlreadyExists", "BrokenPipe", "Interrupted", "NotFound", "Other(Str)",
                     "OutOfMemory", "PermissionDenied", "Unsupported"]) {
    assert.ok(ioerr!.signature.includes(tag), `IOErr is missing ${tag}`);
  }
});

// -----------------------------------------------------------------------------
// The platform overview
// -----------------------------------------------------------------------------

const overviewOf = (scope: (typeof PLATFORM_SCOPES)[number]) =>
  fs.readFileSync(path.join(ROOT, SCOPE_DEFS[scope].overview!), "utf-8");

test("every platform overview stays cheap enough to read unconditionally", () => {
  for (const scope of PLATFORM_SCOPES) {
    // The estimate used elsewhere in this server: about 3.5 characters per token.
    const tokens = Math.round(overviewOf(scope).length / 3.5);
    assert.ok(tokens < 2000, `the ${scope} page is ~${tokens} tokens`);
  }
});

// After an upstream rename, the page would be wrong with no sign of it. Its
// snippets fail `roc check` only if the rename breaks a line that they use.
test("every platform name an overview mentions resolves", () => {
  const pattern = /\b[A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)*\.[a-z_][a-z_0-9]*!?/g;
  for (const scope of PLATFORM_SCOPES) {
    // A page describes one platform, so it is checked against that platform's
    // own address space: a name only the other one has must not pass.
    const idx = registry.addressSpace(scope);
    const named = [...new Set(overviewOf(scope).match(pattern) ?? [])]
      // `Builtin.roc` is a filename, and a tarball hash beginning with a capital
      // letter parses as a qualified name whose last segment is `tar`.
      .filter((n) => !n.endsWith(".roc") && !n.endsWith(".tar"))
      .sort();
    assert.ok(named.length > 8, `${scope}: only ${named.length} names found; the regex probably broke`);
    const missing = named.filter((n) => !idx.byFullName.has(n));
    assert.deepEqual(missing, [], `named in the ${scope} overview but absent from the index`);
  }
});

// The page that `search_roc_syntax(<name>)` returns for a package that this
// server documents. The rules are the same as for a platform, plus the snippet
// rule of `plugin validate`: a page line that no compiled app holds can go out
// of date.
test("every bundled package overview resolves, compiles and stays short", () => {
  const packages = PACKAGE_DOCS.filter((d) => d.bundled);
  assert.deepEqual(packages.map((d) => d.name), ["roc-parser", "roc-random"]);
  const pattern = /\b[A-Z][A-Za-z0-9]*\.[a-z_][a-z_0-9]*!?/g;
  for (const def of packages) {
    const scope = def.name;
    const page = fs.readFileSync(path.join(ROOT, def.overview!), "utf-8");
    assert.ok(page.length / 3.5 < 1000, `the ${scope} page is ~${Math.round(page.length / 3.5)} tokens`);

    const idx = registry.packageIndex(def);
    const named = [...new Set(page.match(pattern) ?? [])].filter((n) => !n.endsWith(".roc") && !n.endsWith(".tar"));
    // `Entropy.seed_u32!` is basic-cli's, imported under another name, and
    // `Json.parse` is the standard library's.
    const elsewhere = new Set(["Entropy.seed_u32!", "Json.parse"]);
    const missing = named.filter((n) => !elsewhere.has(n) && !idx.byFullName.has(n));
    assert.deepEqual(missing, [], `named in the ${scope} overview but absent from its index`);

    const apps = (def.checks ?? [])
      .flatMap((dir) => fs.readdirSync(path.join(ROOT, dir)).map((f) => path.join(ROOT, dir, f)))
      .filter((f) => f.endsWith(".roc"))
      .map((f) => fs.readFileSync(f, "utf-8"))
      .join("\n");
    for (const block of snippets(page)) {
      for (const line of block.split("\n")) {
        assert.ok(apps.includes(line.trim()), `${scope} overview line is in no compiled app: ${line}`);
      }
    }
  }
});

test("every overview pins the version the registry does", () => {
  for (const scope of PLATFORM_SCOPES) {
    const version = SCOPE_DEFS[scope].version!;
    assert.ok(
      overviewOf(scope).includes(`/releases/download/${version}/`),
      `the ${scope} overview's app header does not pin ${version}`
    );
  }
});

// -----------------------------------------------------------------------------
// Bundled content
// -----------------------------------------------------------------------------

test("every bundled example and doc page carries a summary line", () => {
  for (const [scope, count] of [["basic-webserver", 27], ["basic-cli", 34]] as const) {
    const examples = registry.examples(scope);
    assert.equal(examples.length, count, `${scope} bundles ${examples.length} examples`);
    for (const ex of examples) {
      assert.ok(ex.title.length > 10, `${scope}/${ex.name} has no leading ## summary`);
    }
  }
  assert.deepEqual(registry.docs("basic-webserver").map((d) => d.name), ["benchmarking", "sse"]);
  // basic-cli ships no prose pages upstream, so the scope declares no docs dir.
  assert.deepEqual(registry.docs("basic-cli"), []);
});

test("a scope with no bundled content reports none rather than throwing", () => {
  assert.deepEqual(registry.examples("builtin"), []);
  assert.deepEqual(registry.docs("language"), []);
});

// -----------------------------------------------------------------------------
// Manifests
// -----------------------------------------------------------------------------

const RAY_RELEASE =
  "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.7.0/RayRelease00000000000000.tar.zst";
const HTTP_2 = "https://github.com/roc-lang/http/releases/download/2.0.0/HttpTwo0000000000000000.tar.zst";
const BRUSH = "https://github.com/someone/brush/releases/download/1.0.0/BrushRelease000000000000.tar.zst";
/** A bundle hosted somewhere other than a GitHub release. `.invalid` never resolves. */
const SELF_HOSTED = "https://roc.bundles.invalid/brush/SeLfHostedBrushBundLeHash1234567892.tar.br";

/**
 * A plugin directory holding only the `index.json` `plugin index` would write
 * for these releases. What each release is comes from its own header there.
 */
function indexedDir(releases: Record<string, Record<string, string>>): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "roc-manifest-"));
  const trees = Object.entries(releases).map(([url, files]) => {
    const tree = fs.mkdtempSync(path.join(dir, "release-"));
    for (const [name, content] of Object.entries(files)) fs.writeFileSync(path.join(tree, name), content);
    return { url, dir: tree };
  });
  fs.writeFileSync(path.join(dir, "index.json"), indexText(trees));
  return dir;
}

/** roc-ray pinning `brush`, and brush itself, both indexed. */
const RAY_DIR = indexedDir({
  [RAY_RELEASE]: {
    "main.roc": `platform ""\n    exposes [Draw]\n    packages {\n        brush: "${BRUSH}",\n    }\n`,
    "Draw.roc": "import brush.Stroke\n\nDraw := [].{\n    circle! : F32 => {}\n}\n",
  },
  [BRUSH]: { "main.roc": "package [Stroke] {}\n", "Stroke.roc": "Stroke := [].{\n    width : U8\n}\n" },
  [HTTP_2]: { "main.roc": "package [Request] {}\n", "Request.roc": "Request := [].{\n    get : Str\n}\n" },
});

/** The smallest manifest that declares a scope. */
const MINIMAL: PluginManifest = {
  schema: SCHEMA_VERSION,
  corpora: [{ release: RAY_RELEASE, description: "A graphics platform." }],
};

/** MINIMAL with its one corpus changed. */
const withRay = (corpus: Record<string, unknown>): PluginManifest => ({
  ...MINIMAL,
  corpora: [{ ...MINIMAL.corpora[0], ...corpus }],
});

// Every scope that this server serves goes through the same function as a
// plugin. So the plugin code path stays tested before any plugin exists.
test("every checked-in scope is built from a manifest on disk", () => {
  for (const dir of [
    "corpus/language",
    "corpus/platforms/basic-webserver",
    "corpus/platforms/basic-cli",
    "corpus/packages/http",
    "corpus/packages/roc-parser",
    "corpus/packages/roc-random",
  ]) {
    assert.ok(fs.existsSync(path.join(ROOT, dir, "plugin.json")), `${dir} has no manifest`);
  }
  // What the server serves, spelled out rather than read back from the same
  // file, so a manifest that stops declaring these fails here.
  const cli = SCOPE_DEFS["basic-cli"];
  assert.deepEqual(cli.modules, [
    {
      release:
        "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
      ns: "platform:basic-cli",
      origin: "basic-cli 0.24.0",
      moduleFromFilename: true,
      exposesFrom: "main.roc",
    },
  ]);
  assert.equal(cli.version, "0.24.0");
  assert.equal(cli.scaffold, "corpus/platforms/basic-cli/scaffold.roc");
  assert.equal(cli.examples, "corpus/platforms/basic-cli/examples");
  assert.equal(SCOPE_DEFS["basic-webserver"].docs, "corpus/platforms/basic-webserver/docs");
  assert.equal(SCOPE_DEFS["builtin"].modules[0].origin, "Builtin.roc");
  assert.deepEqual([...SCOPES], [
    "language",
    "builtin",
    "basic-webserver",
    "basic-cli",
  ]);
  // A package is documented, never a scope.
  assert.deepEqual(PACKAGE_DOCS.map((d) => [d.name, d.id, d.version]), [
    ["roc-parser", "lukewilliamboswell/roc-parser", "2.0.0"],
    ["roc-random", "kili-ilo/roc-random", "0.9.2"],
  ]);
  // The packages this server vendors, read from their own manifests.
  const gh = (repo: string, tag: string, hash: string) =>
    `https://github.com/${repo}/releases/download/${tag}/${hash}.tar.zst`;
  assert.deepEqual(HOST_PACKAGES, [
    { id: "roc-lang/http", version: "1.0.0", release: HTTP_URL, from: "roc-syntax-mcp", tier: 3 },
    {
      id: "lukewilliamboswell/roc-parser",
      version: "2.0.0",
      release: gh("lukewilliamboswell/roc-parser", "2.0.0", "7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW"),
      from: "roc-syntax-mcp",
      tier: 3,
    },
    {
      id: "kili-ilo/roc-random",
      version: "0.9.2",
      release: gh("kili-ilo/roc-random", "0.9.2", "2ZXLX8WRqrosGu1V3VL5aXqgtfTRvJmjFPx8a26ecVmc"),
      from: "roc-syntax-mcp",
      tier: 3,
    },
  ]);
});

// A manifest names a release, not a pattern, because a pattern from a plugin
// adds only the risk of ReDoS. So the host owns the only regex, and the regex
// must match the headers of the shipped platforms.
test("detection built from a release's repo matches the platform headers", () => {
  for (const scope of PLATFORM_SCOPES) {
    const repo = `roc-lang/${scope}`;
    const header = `    pf: platform "https://github.com/${repo}/releases/download/9.9.9/abc123.tar.br",`;
    const m = header.match(SCOPE_DEFS[scope].detect!);
    assert.equal(m?.[1], "9.9.9", `${scope} stopped matching its own header`);
    assert.equal(detectPattern(repo).source, SCOPE_DEFS[scope].detect!.source);
  }
  // The dot in a repo name is a literal, not "any character".
  assert.equal(detectPattern("a/b.c").test("https://x/a/bXc/releases/download/1.0.0/z"), false);
});

// docs/design/plugins.md promises that a host update never invalidates an
// installed plugin. A manifest written for a newer host tests that promise.
test("a manifest carrying fields this host does not know still loads", () => {
  const loaded = fromManifest(RAY_DIR, {
    ...MINIMAL,
    schema: SCHEMA_VERSION + 7,
    somethingFromLater: { deeply: ["nested"] },
    corpora: [{ ...MINIMAL.corpora[0], alsoLater: 1 }],
  });
  assert.equal(loaded.defs[0].name, "roc-ray");
  assert.equal(loaded.defs[0].version, "0.7.0");
});

// The registry reads the name, the version, the detection pattern and the kind
// from the release, so no manifest field can disagree.
test("a release names its corpus, its version and its kind", () => {
  const def = fromManifest(RAY_DIR, MINIMAL).defs[0];
  assert.equal(def.name, "roc-ray");
  assert.equal(def.version, "0.7.0");
  assert.equal(def.detect!.source, detectPattern("lukewilliamboswell/roc-ray").source);
  assert.deepEqual(def.modules, [
    { release: RAY_RELEASE, ns: "platform:roc-ray", origin: "roc-ray 0.7.0", moduleFromFilename: true, exposesFrom: "main.roc" },
  ]);
  assert.equal(fromManifest(RAY_DIR, withRay({ name: "ray" })).defs[0].name, "ray");
  // The same entry, naming a release whose header says package.
  const pkg = fromManifest(RAY_DIR, { ...MINIMAL, corpora: [{ release: BRUSH, description: "Strokes." }] });
  assert.deepEqual(pkg.defs, []);
  assert.deepEqual(pkg.docs.map((d) => [d.name, d.id, d.version]), [["brush", "someone/brush", "1.0.0"]]);
});

test("paths in a manifest are read relative to the manifest", () => {
  // Relative to the registry root, as this server's own manifests are.
  const dir = path.relative(ROOT, RAY_DIR);
  const loaded = fromManifest(dir, withRay({
    overview: "../shared/roc-ray.md",
    examples: "examples",
    scaffold: "scaffold.roc",
  }));
  // A release is a URL, so it is the one path a manifest names that is not
  // resolved against the manifest.
  assert.equal(loaded.defs[0].modules[0].release, RAY_RELEASE);
  assert.equal(loaded.defs[0].examples, path.join(dir, "examples"));
  assert.equal(loaded.defs[0].scaffold, path.join(dir, "scaffold.roc"));
  assert.equal(loaded.defs[0].overview, path.join(path.dirname(dir), "shared/roc-ray.md"));
});

// Only this server's own scopes are not releases: the language, and the
// builtins read from `Builtin.roc`.
test("a corpus with no release is this server's own, and nobody else's", () => {
  const misc = { schema: SCHEMA_VERSION, corpora: [{ name: "misc", dir: ".", description: "Not a platform." }] };
  const corpus = fromManifest("misc", misc, { tier: 3, from: "roc-syntax-mcp" }).defs[0];
  assert.deepEqual(corpus.modules, [{ dir: "misc", ns: "misc", origin: "misc", moduleFromFilename: false }]);
  assert.throws(() => fromManifest("misc", misc), /misc names a dir\. Name the release tarball URL instead/);
  const bare = { schema: SCHEMA_VERSION, corpora: [{ name: "misc", description: "Not a platform." }] };
  assert.throws(() => fromManifest("misc", bare), /misc needs a release/);
});

// A topic file is one more corpus path, so it is resolved and packed as the
// other paths are. Only a declared topic file is readable.
test("a declared topic resolves against the manifest and is served by name", () => {
  const loaded = fromManifest(RAY_DIR, withRay({
    topics: [
      {
        name: "ray_game",
        file: "topics/ray_game.roc",
        description: "How a game is put together.",
        keywords: ["game", "delta time"],
      },
    ],
  }));
  assert.deepEqual(loaded.defs[0].topics, [
    {
      name: "ray_game",
      file: path.join(RAY_DIR, "topics/ray_game.roc"),
      description: "How a game is put together.",
      keywords: ["game", "delta time"],
    },
  ]);
  assert.ok(
    manifestPaths(loaded.manifest).includes("topics/ray_game.roc"),
    "a topic outside `files` is missing once installed"
  );
});

// The tier is how the manifest arrived, never something it asks for: a plugin
// that could name its own tier could outrank the bundled copy it loads beside.
test("a manifest cannot promote its own packages", () => {
  const asked = { schema: SCHEMA_VERSION, tier: 0, corpora: [{ release: HTTP_2, tier: 0, from: "roc-lang" }] };
  const vendored = fromManifest(RAY_DIR, asked, { tier: 3, from: "roc-syntax-mcp" });
  assert.deepEqual(vendored.providers, [
    { id: "roc-lang/http", version: "2.0.0", release: HTTP_2, from: "roc-syntax-mcp", tier: 3 },
  ]);
  const plugin = fromManifest(RAY_DIR, asked);
  assert.deepEqual(plugin.docs, [], "a package with no description documents nothing");
  assert.deepEqual(plugin.providers, [
    { id: "roc-lang/http", version: "2.0.0", release: HTTP_2, from: "http", tier: 1 },
  ]);
});

// A header can pin anything that `roc deps` fetches: an https URL named by its
// content hash. Only a GitHub release URL gives more information.
test("a pin is a GitHub release, or any URL named by its content hash", () => {
  assert.deepEqual(pinFromUrl(RAY_RELEASE), { id: "lukewilliamboswell/roc-ray", version: "0.7.0" });
  assert.deepEqual(pinFromUrl(SELF_HOSTED), { id: "roc.bundles.invalid/brush", version: "SeLfHostedBr" });
  // Not a content hash, so neither the compiler nor this server reads it.
  assert.equal(pinFromUrl("https://github.com/a/b/archive/528f8848a0474dda922252f1f86b50f713206e9e.tar.gz"), null);
  assert.equal(pinFromUrl("../brush/main.roc"), null);
});

test("a corpus at a URL that is not a GitHub release is named, versioned and detected by it", () => {
  const dir = indexedDir({
    [SELF_HOSTED]: { "main.roc": `platform ""\n    exposes [Stroke]\n    packages {}\n`, "Stroke.roc": "Stroke := [].{\n    width : U8\n}\n" },
  });
  const def = fromManifest(dir, { schema: 1, corpora: [{ release: SELF_HOSTED, description: "Strokes." }] }).defs[0];
  assert.deepEqual([def.name, def.version], ["brush", "SeLfHostedBr"]);
  // Another bundle under the same directory is the same platform at another hash.
  const other = "https://roc.bundles.invalid/brush/AnotherBundLeWithAHash123456789ab.tar.zst";
  assert.equal(other.match(def.detect!)?.[1], "AnotherBundL");
  assert.equal(SELF_HOSTED.match(def.detect!)?.[1], "SeLfHostedBr");
  assert.equal("https://roc.bundles.invalid/other/AnotherBundLeWithAHash123456789ab.tar.zst".match(def.detect!), null);
  // A directory that is a version names nothing, so the corpus has to.
  const versioned = "https://roc.bundles.invalid/brush/1.0.0/SeLfHostedBrushBundLeHash1234567892.tar.br";
  const vdir = indexedDir({ [versioned]: { "main.roc": "package [Stroke] {}\n" } });
  assert.throws(() => fromManifest(vdir, { schema: 1, corpora: [{ release: versioned }] }), /Give the corpus a name/);
  assert.equal(fromManifest(vdir, { schema: 1, corpora: [{ release: versioned, name: "brush" }] }).providers[0].id, "roc.bundles.invalid/brush/1.0.0");
});

// One install with two corpora. The platform's API uses the package's types, so
// the plugin documents both. Each corpus loads as it would in a plugin alone.
test("one plugin documents a platform and the package it pins", () => {
  const loaded = fromManifest(RAY_DIR, {
    schema: SCHEMA_VERSION,
    maintainer: "someone",
    corpora: [
      { release: RAY_RELEASE, description: "A graphics platform.", purpose: "games" },
      { release: BRUSH, description: "Strokes.", overview: "brush.md" },
    ],
  });
  assert.deepEqual(loaded.defs.map((d) => [d.name, d.version, d.maintainer]), [["roc-ray", "0.7.0", "someone"]]);
  assert.deepEqual(loaded.docs.map((d) => [d.name, d.overview, d.maintainer]), [
    ["brush", path.join(RAY_DIR, "brush.md"), "someone"],
  ]);
  assert.deepEqual(loaded.providers.map((p) => [p.id, p.version, p.from, p.tier]), [["someone/brush", "1.0.0", "brush", 1]]);
});

// Two releases of one package with different content are two nominal types to
// the compiler. A plugin that ships a release other than the one its platform
// pins would document an app that cannot compile.
test("a plugin's package must be the release its own platform pins", () => {
  const other = BRUSH.replace("1.0.0/BrushRelease", "1.1.0/BrushNewer00");
  const dir = indexedDir({
    [RAY_RELEASE]: { "main.roc": `platform ""\n    exposes []\n    packages {\n        brush: "${BRUSH}",\n    }\n` },
    [other]: { "main.roc": "package [Stroke] {}\n" },
  });
  assert.throws(
    () => fromManifest(dir, { schema: 1, corpora: [{ release: RAY_RELEASE, description: "d" }, { release: other }] }),
    /roc-ray 0\.7\.0 pins someone\/brush 1\.0\.0, and this plugin ships 1\.1\.0/
  );
});

// A caller selects a platform only from the catalogue, and the catalogue is
// readable only if every line is a few words. A scope without `purpose` is
// listed with its whole description, which is a fallback.
test("every platform this server ships says what it is for in a few words", () => {
  for (const scope of PLATFORM_SCOPES) {
    const { purpose, description } = SCOPE_DEFS[scope];
    assert.notEqual(purpose, description, `${scope} declares no purpose`);
    assert.ok(purpose.length <= PURPOSE_MAX, `${scope}: purpose is ${purpose.length} chars`);
  }
});

test("a manifest this host cannot trust is rejected rather than repaired", () => {
  const brush = (c: Record<string, unknown>) => ({ schema: 1, corpora: [{ release: BRUSH, ...c }] });
  const bad: [string, unknown, RegExp][] = [
    ["not an object", "plugin.json", /not an object/],
    ["no schema version", { corpora: MINIMAL.corpora }, /schema version/],
    ["no corpora", { schema: 1 }, /corpora must be a non-empty list/],
    ["a name that is not a name", withRay({ name: "../etc" }), /not a valid name/],
    ["a release that is not a tarball URL", withRay({ release: "https://x/a/b" }), /not a tarball URL/],
    ["a release nobody indexed", withRay({ release: RAY_RELEASE.replace("RayRelease", "Unindexed") }), /is not in index\.json\. Run: roc-syntax-mcp plugin index/],
    ["a platform with no description", withRay({ description: undefined }), /roc-ray: a platform needs a description/],
    ["a scaffold for a package", brush({ description: "d", scaffold: "s.roc" }), /brush: scaffold is for a platform, and brush is a package/],
    ["docs for a package", brush({ description: "d", docs: "docs" }), /brush: docs is for a platform/],
    ["prose with nothing to list it by", brush({ overview: "o.md" }), /brush: overview needs a description/],
    ["one name claimed twice", { schema: 1, corpora: [MINIMAL.corpora[0], { ...MINIMAL.corpora[0] }] }, /roc-ray is declared twice/],
    ["a topic name that is not a name", withRay({ topics: [{ name: "Ray Game", file: "t.roc", description: "d", keywords: ["k"] }] }), /bad topic name/],
    ["a topic with no keywords", withRay({ topics: [{ name: "ray_game", file: "t.roc", description: "d", keywords: [] }] }), /needs keywords/],
    ["an empty purpose", withRay({ purpose: "" }), /purpose must be a non-empty string/],
    // A caller reads one line per platform before writing code. Three
    // descriptions in those lines make three paragraphs.
    ["a purpose too long to be a few words", withRay({ purpose: "x".repeat(PURPOSE_MAX + 1) }), /the limit is/],
    ["a topic name claimed twice", withRay({ topics: [
      { name: "ray_game", file: "a.roc", description: "d", keywords: ["k"] },
      { name: "ray_game", file: "b.roc", description: "d", keywords: ["k"] },
    ] }), /declared twice/],
  ];
  for (const [why, raw, says] of bad) {
    assert.throws(() => fromManifest(RAY_DIR, raw), says, `${why} was accepted`);
  }
});

// -----------------------------------------------------------------------------
// v1 compatibility
// -----------------------------------------------------------------------------

/**
 * This test enforces the compatibility rules in `docs/design/plugins.md`.
 *
 * `src/testdata/plugin-v1/` is frozen. It may gain fields as the schema grows.
 * No field in it may change meaning or be removed, and this test must always
 * pass. A plugin published against v1 must load on every later host.
 */
test("a v1 manifest loads on this host, field for field", () => {
  const dir = "src/testdata/plugin-v1";
  const loaded = fromManifest(dir, JSON.parse(fs.readFileSync(path.join(ROOT, dir, "plugin.json"), "utf-8")));
  assert.deepEqual(loaded.defs, [
    {
      name: "frozen-v1",
      description: "Every field a v1 manifest may carry. Frozen: add, never change.",
      // The manifest declares no `purpose`, so the description replaces it. With
      // this fallback, an installed plugin stays in the catalogue that a caller
      // selects a platform from.
      purpose: "Every field a v1 manifest may carry. Frozen: add, never change.",
      maintainer: "example",
      version: "1.2.3",
      overview: `${dir}/overview.md`,
      examples: `${dir}/examples`,
      docs: `${dir}/docs`,
      scaffold: `${dir}/scaffold.roc`,
      sample: `${dir}/sample.roc`,
      checks: [`${dir}/verify`],
      detect: /example\/frozen-v1\/releases\/download\/(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\//,
      modules: [
        {
          release: FROZEN_RELEASE,
          ns: "platform:frozen-v1",
          origin: "frozen-v1 1.2.3",
          moduleFromFilename: true,
          exposesFrom: "main.roc",
        },
      ],
    },
  ]);
  assert.deepEqual(loaded.docs, [
    {
      name: "frozen",
      id: "example/frozen-pkg",
      version: "4.5.6",
      release: FROZEN_PKG,
      description: "The package the platform's API is written in, documented beside it.",
      purpose: "widgets, on frozen-v1",
      maintainer: "example",
      bundled: false,
      overview: `${dir}/package.md`,
      topics: [
        { name: "frozen_widgets", file: `${dir}/verify/snippets.roc`, description: "Drawing a widget.", keywords: ["widget"] },
      ],
    },
  ]);
  assert.deepEqual(loaded.providers, [
    { id: "example/frozen-pkg", version: "4.5.6", release: FROZEN_PKG, from: "frozen", tier: 1 },
  ]);
});

const FROZEN_RELEASE =
  "https://github.com/example/frozen-v1/releases/download/1.2.3/FrozenV1Release000000000.tar.zst";
const FROZEN_PKG =
  "https://github.com/example/frozen-pkg/releases/download/4.5.6/FrozenPackage00000000000.tar.zst";

/**
 * A parser improvement changes the item counts of an unchanged plugin, and that
 * is correct. So this test asserts the shape of the index, never a count.
 */
test("the frozen v1 corpus indexes into the shape its manifest describes", () => {
  const dir = "src/testdata/plugin-v1";
  const loaded = fromManifest(dir, JSON.parse(fs.readFileSync(path.join(ROOT, dir, "plugin.json"), "utf-8")));
  const local = new ScopeRegistry(ROOT, {
    providers: loaded.providers,
    defs: { "frozen-v1": loaded.defs[0] },
    indexFiles: [path.join(ROOT, dir, "index.json")],
  });
  const idx = local.index("frozen-v1");
  assert.ok(idx.items.length > 0, "the frozen corpus indexed nothing");
  assert.deepEqual([...new Set(idx.items.map((i) => i.ns))], ["platform:frozen-v1", "pkg:example/frozen-pkg"]);
  assert.deepEqual([...new Set(idx.items.map((i) => i.origin))], ["frozen-v1 1.2.3", "frozen-pkg 4.5.6"]);
  // Read from the header, not the manifest: the pin a platform was compiled
  // against is the one in its own `packages` block, and the plugin serves it.
  assert.deepEqual(
    local.packages("frozen-v1").map((pkg) => [pkg.id, pkg.required, pkg.crossing, pkg.provider?.from]),
    [["example/frozen-pkg", "4.5.6", ["Widget"], "frozen"]]
  );
});
