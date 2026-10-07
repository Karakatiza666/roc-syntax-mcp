// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The provenance files, cross-checked against each other and against the code.
//
// Each provenance file names the compiler nightly that the check scripts used.
// If a refresh bumps one file and not another, the refresh looks complete, but
// one corpus was last checked against a compiler that nobody has.

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { CORE, HOST_PACKAGES, ScopeRegistry } from "./scopes.ts";

const { platformScopes: PLATFORM_SCOPES, scopeDefs: SCOPE_DEFS } = CORE;

const ROOT = path.join(import.meta.dirname, "..");
const read = (name: string) => fs.readFileSync(path.join(ROOT, name), "utf-8");

/** First `key value` line, dropping the trailing parenthetical some carry. */
function field(content: string, key: string): string | undefined {
  return content.match(new RegExp(`^${key}\\s+(\\S+)`, "m"))?.[1];
}

/** The tarball URL a provenance file records, from its repo, tag and tarball. */
function releaseUrl(file: string): string {
  const content = read(file);
  return `${field(content, "repo")}/releases/download/${field(content, "tag")}/${field(content, "tarball")}`;
}

/** Every provenance file under `corpus/`, with the language file first. */
const PROVENANCE = [
  "corpus/language/UPSTREAM",
  ...["platforms", "packages"].flatMap((kind) =>
    fs.readdirSync(path.join(ROOT, "corpus", kind)).map((unit) => `corpus/${kind}/${unit}/UPSTREAM`)
  ),
];

test("every provenance file names the same compiler nightly", () => {
  const [first, ...rest] = PROVENANCE;
  const language = field(read(first), "compiler");
  assert.ok(language, `${first} records no compiler`);
  for (const scope of PLATFORM_SCOPES) {
    assert.ok(rest.includes(`corpus/platforms/${scope}/UPSTREAM`), `${scope} has no provenance file`);
  }
  // A package handed to the compiler only through a platform has no line of its own.
  for (const file of rest) {
    const compiler = field(read(file), "compiler");
    if (compiler) assert.equal(compiler, language, `${file} names a different nightly`);
  }
});

// The platform's `tag` comes first in each file. A `package` block, if there is
// one, follows it.
test("every recorded platform release is the one the registry serves", () => {
  for (const scope of PLATFORM_SCOPES) {
    assert.equal(
      field(read(`corpus/platforms/${scope}/UPSTREAM`), "tag"),
      SCOPE_DEFS[scope].version,
      `corpus/platforms/${scope}/UPSTREAM and src/scopes.ts disagree about the release`
    );
  }
});

// Two platforms use one package, and the repo vendors it once. Three places must
// agree on the release:
// 1. the header of each platform pins the package,
// 2. the registry resolves that pin to the vendored copy,
// 3. the origin string of every indexed item quotes the release.
// A bump that misses one of the three labels half the corpus with the wrong
// release.
test("the shared http package is recorded once and pinned by both platforms", () => {
  const tag = field(read("corpus/packages/http/UPSTREAM"), "tag");
  assert.ok(tag, "corpus/packages/http/UPSTREAM records no tag");
  const registry = new ScopeRegistry(ROOT);
  for (const scope of PLATFORM_SCOPES) {
    const [resolved, ...rest] = registry.packages(scope);
    assert.ok(resolved, `${scope} pins no packages`);
    assert.deepEqual(rest, [], `${scope} pins a package the provenance does not record`);
    assert.equal(resolved.id, "roc-lang/http");
    assert.equal(resolved.required, tag, `${scope}'s header pins a release corpus/packages/http/UPSTREAM does not`);
    assert.equal(resolved.provider?.release, releaseUrl("corpus/packages/http/UPSTREAM"), `${scope} resolved elsewhere`);
    assert.equal(registry.index(scope).byFullName.get("Method")!.origin, `http ${tag}`);
  }
});

// The pin has an effect only if the apps carry it. `check:platforms` compiles
// every scaffold. A scaffold that pins the same release as the platform header
// links the registry's required version to a program that the compiler accepted.
test("every scaffold pins the package release its platform header does", () => {
  const registry = new ScopeRegistry(ROOT);
  for (const scope of PLATFORM_SCOPES) {
    const scaffold = read(SCOPE_DEFS[scope].scaffold!);
    for (const pkg of registry.packages(scope)) {
      assert.ok(
        scaffold.includes(`/releases/download/${pkg.required}/`),
        `${scope}'s scaffold pins ${pkg.id} at a release its platform header does not`
      );
    }
  }
});

// A pin has an effect only if the apps carry it. `check:platforms` compiles
// every scaffold, so a scaffold that pins the recorded tarball links the
// provenance file to a program that the compiler accepted.
test("every scaffold pins the tarball its provenance file records", () => {
  for (const scope of PLATFORM_SCOPES) {
    const provenance = read(`corpus/platforms/${scope}/UPSTREAM`);
    const tarball = field(provenance, "tarball");
    assert.ok(tarball, `corpus/platforms/${scope}/UPSTREAM records no tarball`);
    const scaffold = read(SCOPE_DEFS[scope].scaffold!);
    assert.ok(scaffold.includes(tarball!), `${scope}'s scaffold pins a different tarball`);
    assert.ok(
      scaffold.includes(`/releases/download/${SCOPE_DEFS[scope].version}/`),
      `${scope}'s scaffold pins a different release`
    );
  }
});

// The manifest names the release that the server reads, and a refresh edits the
// provenance file. Two copies of one pin are safe only when a test keeps them
// equal.
test("every manifest release is the one its provenance file records", () => {
  for (const scope of PLATFORM_SCOPES) {
    assert.equal(
      SCOPE_DEFS[scope].modules[0].release,
      releaseUrl(`corpus/platforms/${scope}/UPSTREAM`),
      `corpus/platforms/${scope}/plugin.json and UPSTREAM name different releases`
    );
  }
  for (const pkg of HOST_PACKAGES) {
    const unit = pkg.id.split("/")[1];
    assert.equal(
      pkg.release,
      releaseUrl(`corpus/packages/${unit}/UPSTREAM`),
      `corpus/packages/${unit}/plugin.json and UPSTREAM name different releases`
    );
  }
});
