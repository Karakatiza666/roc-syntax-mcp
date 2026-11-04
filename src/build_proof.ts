// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// BUILD-PROOF, for a plugin whose `compiler` is a fork of Roc rather than a
// nightly. CI cannot build a fork, so the author validates the plugin locally
// with `plugin validate --attest`, which writes BUILD-PROOF. CI then runs
// `plugin validate --offline --proof`, which runs no compiler and checks that
// BUILD-PROOF names the compiler of plugin.json and the digest of the files
// that npm packs.
//
// The file records which compiler validated which content, so that CI finds a
// stale validation. It authenticates nobody, because anybody who can push can
// write a matching file.
//
// To remove the feature, delete this file, build_proof.test.ts, the calls in
// src/plugin_cli.ts (the `compiler` check of a fork, `--attest` and `--proof`),
// the "Verify the build proof" path of .github/workflows/publish-plugin.yml and
// the `fork-plugins` job of .github/workflows/ci.yml. The gates keep checking a
// fork plugin with roc_<compiler>/roc (scripts/nightlies.mjs).

import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";

export const PROOF_FILE = "BUILD-PROOF";

/** The result of one check, as `plugin validate` prints it. */
type Check = { name: string; status: "ok" | "fail"; detail?: string };

/**
 * Whether a `compiler` names a fork build, `<branch>-<40-hex commit>`, the form
 * of a package's `.roc-version`. The gates decide with `isFork` of
 * scripts/nightlies.mjs, so keep the two equal.
 */
export const isFork = (compiler?: string): compiler is string =>
  /^(?!nightly-)[\w.-]+-[0-9a-f]{40}$/.test(compiler ?? "");

/** The detail of the `compiler` check for a fork, or null for a nightly. */
export function forkNote(compiler?: string): string | null {
  if (!isFork(compiler)) return null;
  return (
    `the fork ${compiler}, which CI cannot download. The gates run roc_${compiler}/roc at the repo root, ` +
    `and CI checks the ${PROOF_FILE} that \`validate --attest\` writes`
  );
}

/**
 * The sha256 over the files that npm packs: package.json and everything under
 * the `files` list of package.json, minus BUILD-PROOF. Each file adds one
 * `<sha256 of its content>  <path>` line, in path order, so a rename changes
 * the digest too.
 */
export function contentDigest(dir: string): string {
  const files: unknown = JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf-8")).files;
  if (!Array.isArray(files)) throw new Error("package.json has no files list, so nothing defines what is published");
  const packed = new Set(["package.json"]);
  const walk = (rel: string): void => {
    const abs = path.join(dir, rel);
    if (!fs.existsSync(abs)) return;
    if (fs.statSync(abs).isDirectory()) for (const name of fs.readdirSync(abs)) walk(path.posix.join(rel, name));
    else packed.add(rel);
  };
  for (const f of files) walk(String(f).replace(/^\.\//, "").replace(/\/+$/, ""));
  packed.delete(PROOF_FILE);
  const sha = (data: string | Buffer) => crypto.createHash("sha256").update(data).digest("hex");
  const lines = [...packed].sort().map((rel) => `${sha(fs.readFileSync(path.join(dir, rel)))}  ${rel}\n`);
  return `sha256:${sha(lines.join(""))}`;
}

const compilerOf = (dir: string): string =>
  JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8")).compiler ?? "none";

/**
 * Writes BUILD-PROOF when every check of a `validate` run is ok. A `skip`
 * blocks it, because a skipped check did not run. The `roc_check` gate of a
 * package plugin is ok with nothing to run, because a package has no scaffold.
 */
export function attest(dir: string, checks: readonly { name: string; status: string }[]): Check {
  const notOk = checks.filter((c) => c.status !== "ok").map((c) => c.name);
  if (notOk.length > 0) {
    return { name: "attest", status: "fail", detail: `no ${PROOF_FILE}, because these checks are not ok: ${notOk.join(", ")}` };
  }
  const digest = contentDigest(dir);
  const date = new Date().toISOString().slice(0, 10);
  fs.writeFileSync(path.join(dir, PROOF_FILE), `compiler ${compilerOf(dir)}\ndigest   ${digest}\ndate     ${date}\n`);
  return { name: "attest", status: "ok", detail: `wrote ${PROOF_FILE}: ${digest}` };
}

/** Compares BUILD-PROOF with the compiler of plugin.json and the digest of the files. Runs no compiler. */
export function proofCheck(dir: string): Check {
  try {
    const compiler = compilerOf(dir);
    const file = path.join(dir, PROOF_FILE);
    const proof = fs.existsSync(file) ? fs.readFileSync(file, "utf-8") : "";
    const field = (key: string) => proof.match(new RegExp(`^${key}\\s+(\\S+)`, "m"))?.[1];
    if (field("compiler") === compiler && field("digest") === contentDigest(dir)) {
      return { name: "proof", status: "ok", detail: `validated with ${compiler} on ${field("date")}, and unchanged since` };
    }
    return {
      name: "proof",
      status: "fail",
      detail: `the plugin changed since it was validated; run \`plugin validate --attest\` locally with ${compiler}`,
    };
  } catch (err) {
    return { name: "proof", status: "fail", detail: err instanceof Error ? err.message : String(err) };
  }
}
