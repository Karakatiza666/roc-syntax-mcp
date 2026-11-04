// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Tests for BUILD-PROOF: the digest of the packed files, the proof that
// `validate --attest` writes, and the check that `validate --proof` runs.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { attest, contentDigest, forkNote, isFork, proofCheck } from "./build_proof.ts";
import { staticChecks } from "./plugin_cli.ts";
// @ts-expect-error a script, with no types
import { isFork as gateIsFork } from "../scripts/nightlies.mjs";

const FORK = `reify-${"0123456789abcdef".repeat(3).slice(0, 40)}`;
/** A release that no index holds. The static checks then run without the corpus. */
const RELEASE = `https://github.com/x/y/releases/download/1.0.0/${"Unindexed".padEnd(24, "0")}.tar.zst`;

let tmp: string;
before(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roc-build-proof-"));
});
after(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

/** A plugin directory with a fork compiler, a packed topic and an unpacked file. */
function plugin(name: string): string {
  const dir = path.join(tmp, name);
  const files: Record<string, string> = {
    "plugin.json": JSON.stringify({ schema: 1, compiler: FORK, corpora: [{ release: RELEASE, description: "A package." }] }),
    "package.json": JSON.stringify({ name: "@t/proof", version: "1.0.0", files: ["BUILD-PROOF", "plugin.json", "topics"] }),
    "topics/a.roc": "x = 1\n",
    "notes.txt": "not packed",
  };
  for (const [rel, content] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true });
    fs.writeFileSync(path.join(dir, rel), content);
  }
  return dir;
}

test("this module and the gates agree on which compiler is a fork", () => {
  for (const c of [FORK, "reify-c1e6af27a2", "nightly-2026-11-03-34bd006", "nightly-2026-11-03-" + "a".repeat(40), undefined]) {
    assert.equal(isFork(c), gateIsFork(c), String(c));
  }
  assert.equal(forkNote("nightly-2026-11-03-34bd006"), null);
  assert.match(forkNote(FORK)!, /which CI cannot download/);
});

test("validate reports a fork compiler as ok", () => {
  const compiler = staticChecks(plugin("reported")).find((c) => c.name === "compiler");
  assert.equal(compiler?.status, "ok");
  assert.match(compiler!.detail!, new RegExp(`the fork ${FORK}`));
});

test("attest writes nothing unless every check is ok", () => {
  const dir = plugin("refused");
  const result = attest(dir, [{ name: "roc check", status: "ok" }, { name: "roc_check", status: "skip" }]);
  assert.equal(result.status, "fail");
  assert.match(result.detail!, /not ok: roc_check/);
  assert.ok(!fs.existsSync(path.join(dir, "BUILD-PROOF")));
});

test("BUILD-PROOF matches until one byte of a packed file changes", () => {
  const dir = plugin("round-trip");
  assert.match(proofCheck(dir).detail!, new RegExp(`run \`plugin validate --attest\` locally with ${FORK}`));

  assert.equal(attest(dir, [{ name: "roc check", status: "ok" }]).status, "ok");
  assert.match(fs.readFileSync(path.join(dir, "BUILD-PROOF"), "utf-8"), new RegExp(`^compiler ${FORK}\ndigest   sha256:[0-9a-f]{64}\ndate     \\d{4}-\\d\\d-\\d\\d\n$`));
  assert.equal(proofCheck(dir).status, "ok", proofCheck(dir).detail);

  // A file outside `files` is not published, so it does not change the digest.
  const digest = contentDigest(dir);
  fs.writeFileSync(path.join(dir, "notes.txt"), "changed");
  assert.equal(contentDigest(dir), digest);

  fs.writeFileSync(path.join(dir, "topics/a.roc"), "x = 2\n");
  assert.equal(proofCheck(dir).status, "fail");
  assert.match(proofCheck(dir).detail!, /the plugin changed since it was validated/);
  fs.writeFileSync(path.join(dir, "topics/a.roc"), "x = 1\n");
  assert.equal(proofCheck(dir).status, "ok");

  // A renamed file has the same bytes and another path.
  fs.renameSync(path.join(dir, "topics/a.roc"), path.join(dir, "topics/b.roc"));
  assert.notEqual(contentDigest(dir), digest);
  fs.renameSync(path.join(dir, "topics/b.roc"), path.join(dir, "topics/a.roc"));

  // A proof made with another compiler does not count, even over the same files.
  const proof = path.join(dir, "BUILD-PROOF");
  fs.writeFileSync(proof, fs.readFileSync(proof, "utf-8").replace(FORK, "nightly-2026-11-03-34bd006"));
  assert.equal(proofCheck(dir).status, "fail");
});
