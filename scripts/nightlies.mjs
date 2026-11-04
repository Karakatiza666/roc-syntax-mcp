// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The nightly that a gate checks a program with. Each platform corpus records
// the nightly of its release on the `compiler` line of its UPSTREAM file, and a
// plugin in the `compiler` field of its plugin.json. A program that pins that
// release is checked with that nightly, so a refresh can move the bundled
// nightly before every platform has a release for it.
//
// Usage: node scripts/nightlies.mjs [plugin-dir ...]
//   prints `release|nightly` for each platform release, one per line.
// Usage: node scripts/nightlies.mjs --all
//   prints each nightly that the gates of this repo use, one per line, for CI.
// Usage: node scripts/nightlies.mjs --fork <plugin-dir>
//   prints the fork that the plugin names as its `compiler`, or nothing.
//
// A plugin can name a build of a Roc fork as its compiler, in the form of a
// package's `.roc-version`: `<branch>-<40-hex commit>`. Nobody publishes such a
// build, so it lives at the repo root as roc_<compiler>/roc, often a symlink.
// Every program of that plugin is checked with the fork, because a program that
// uses the fork's language does not build on any nightly.

import * as fs from "node:fs";
import * as path from "node:path";

const ROOT = path.join(import.meta.dirname, "..");

/** First `key value` field of an UPSTREAM file. */
const field = (text, key) => text.match(new RegExp(`^${key}\\s+(\\S+)`, "m"))?.[1];

/**
 * The releases of each platform corpus of this repo, then of each plugin
 * directory in `dirs`, with their nightly. The release comes from plugin.json.
 * The nightly is its `compiler` field, else the `compiler` line of UPSTREAM. A
 * directory that names no nightly adds nothing.
 */
export function releaseNightlies(dirs = []) {
  const platforms = path.join(ROOT, "corpus", "platforms");
  const all = [...fs.readdirSync(platforms).map((d) => path.join(platforms, d)), ...dirs];
  return all.flatMap((dir) => {
    const read = (name) => (fs.existsSync(path.join(dir, name)) ? fs.readFileSync(path.join(dir, name), "utf-8") : "");
    const manifest = JSON.parse(read("plugin.json") || "{}");
    const nightly = manifest.compiler ?? field(read("UPSTREAM"), "compiler");
    if (!nightly) return [];
    return (manifest.corpora ?? []).filter((c) => c.release).map((c) => ({ release: c.release, nightly }));
  });
}

/**
 * Whether a `compiler` value names a fork build, `<branch>-<40-hex commit>`,
 * rather than a nightly. `isFork` in src/build_proof.ts must give the same answer.
 */
export const isFork = (compiler) => typeof compiler === "string" && /^(?!nightly-)[\w.-]+-[0-9a-f]{40}$/.test(compiler);

const EXE = process.platform === "win32" ? "roc.exe" : "roc";

/** Where the gates look for the binary of a fork. */
export const forkPath = (fork) => path.join(ROOT, `roc_${fork}`, EXE);

/**
 * The binary of `compiler`, or null. A nightly is unpacked at the repo root as
 * the refresh skill does. A fork is at `forkPath`.
 */
export function compilerBinary(compiler) {
  if (isFork(compiler)) return fs.existsSync(forkPath(compiler)) ? forkPath(compiler) : null;
  const stamp = compiler.replace(/^nightly-/, "");
  const dir = fs.readdirSync(ROOT).find((d) => d.startsWith("roc_nightly-") && d.endsWith(`-${stamp}`));
  const binary = dir && path.join(ROOT, dir, EXE);
  return binary && fs.existsSync(binary) ? binary : null;
}

/** The fork that the plugin in `dir` names as its compiler, or null. */
export function forkOf(dir) {
  try {
    const compiler = JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8")).compiler;
    return isFork(compiler) ? compiler : null;
  } catch {
    return null;
  }
}

const PIN = /^\s*roc:\s*"(nightly-[^"]+)"/m;

/** The nightly for a program: its own `roc:` pin, else the nightly of the platform release it pins, else null. */
export function nightlyFor(source, nightlies = releaseNightlies()) {
  const pin = source.match(PIN)?.[1];
  return pin ?? nightlies.find((n) => source.includes(`"${n.release}"`))?.nightly ?? null;
}

/**
 * Every nightly that the gates use with no plugin arguments: the bundled one,
 * the one of each platform release, and each `roc:` pin of a program that the
 * gates check (under corpus/ and eval/).
 */
export function allNightlies() {
  const upstream = fs.readFileSync(path.join(ROOT, "corpus", "language", "UPSTREAM"), "utf-8");
  const pins = ["corpus", "eval"].flatMap((top) =>
    fs
      .readdirSync(path.join(ROOT, top), { recursive: true })
      .filter((f) => f.endsWith(".roc"))
      .map((f) => fs.readFileSync(path.join(ROOT, top, f), "utf-8").match(PIN)?.[1]),
  );
  const all = [field(upstream, "compiler"), ...releaseNightlies().map((n) => n.nightly), ...pins];
  return [...new Set(all.filter(Boolean))].sort();
}

if (process.argv[1] === import.meta.filename) {
  if (process.argv[2] === "--all") console.log(allNightlies().join("\n"));
  else if (process.argv[2] === "--fork") console.log(forkOf(process.argv[3]) ?? "");
  else for (const n of releaseNightlies(process.argv.slice(2))) console.log(`${n.release}|${n.nightly}`);
}
