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

/** The binary of `nightly`, unpacked at the repo root as the refresh skill does, or null. */
export function nightlyBinary(nightly) {
  const stamp = nightly.replace(/^nightly-/, "");
  const dir = fs.readdirSync(ROOT).find((d) => d.startsWith("roc_nightly-") && d.endsWith(`-${stamp}`));
  const binary = dir && path.join(ROOT, dir, process.platform === "win32" ? "roc.exe" : "roc");
  return binary && fs.existsSync(binary) ? binary : null;
}

/** The nightly for a program: its own `roc:` pin, else the nightly of the platform release it pins, else null. */
export function nightlyFor(source, nightlies = releaseNightlies()) {
  const pin = source.match(/^\s*roc:\s*"(nightly-[^"]+)"/m)?.[1];
  return pin ?? nightlies.find((n) => source.includes(`"${n.release}"`))?.nightly ?? null;
}

if (process.argv[1] === import.meta.filename) {
  for (const n of releaseNightlies(process.argv.slice(2))) console.log(`${n.release}|${n.nightly}`);
}
