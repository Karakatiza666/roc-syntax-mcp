// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Writes an `index.json` next to each manifest that names a release. The server
// reads this parsed snapshot, not vendored source.
//
//   node --import tsx/esm scripts/build-index.ts [--check] [manifest dirs...]
//
// With no dirs, the script covers every manifest under corpus/ and plugins/.
// `--check` writes nothing and exits 1 when a file is out of date. The script
// reads the releases from the package cache of the compiler. `roc deps` fills
// the cache, so a release that is not cached needs a Roc nightly on PATH or in
// $ROC. A plugin author runs the same code as `roc-syntax-mcp plugin index`.

import * as fs from "node:fs";
import * as path from "node:path";
import {
  INDEX_FILE,
  cachedReleaseDir,
  indexManifestDir,
  manifestReleases,
  rocRuns,
} from "../src/release.ts";

const ROOT = path.join(import.meta.dirname, "..");

const args = process.argv.slice(2);
const check = args.includes("--check");
const named = args.filter((a) => !a.startsWith("--"));

/**
 * Every directory that holds a manifest, in corpus/ (up to two levels down) and
 * plugins/ (up to one level down).
 */
function manifestDirs(): string[] {
  const out: string[] = [];
  const walk = (dir: string, depth: number) => {
    if (fs.existsSync(path.join(dir, "plugin.json"))) out.push(dir);
    if (depth === 0) return;
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.isDirectory() && e.name !== "node_modules") walk(path.join(dir, e.name), depth - 1);
    }
  };
  walk(path.join(ROOT, "corpus"), 2);
  walk(path.join(ROOT, "plugins"), 1);
  return out.sort();
}

const dirs = named.length > 0 ? named.map((d) => path.resolve(d)) : manifestDirs();
const roc = process.env.ROC || "roc";

const uncached = dirs
  .flatMap((d) => manifestReleases(JSON.parse(fs.readFileSync(path.join(d, "plugin.json"), "utf-8"))))
  .filter((url) => !cachedReleaseDir(url));
if (uncached.length > 0 && !rocRuns(roc)) {
  // scripts/check-all.sh reports exit 2 as a skipped gate.
  console.error(`No roc to fetch ${uncached.length} release(s) with. Set ROC=/path/to/roc.`);
  process.exit(2);
}

let failed = 0;
for (const dir of dirs) {
  const rel = path.relative(ROOT, path.join(dir, INDEX_FILE));
  const { status, missing } = await indexManifestDir(dir, { check, roc });
  if (status === "none") continue;
  if (missing.length > 0) {
    console.log(`fetch  ${rel}: roc deps could not fetch ${missing.join(", ")}`);
    failed++;
  } else {
    console.log(`${status.padEnd(6)} ${rel}`);
    if (status === "stale") failed++;
  }
}
if (failed > 0) {
  console.error(`${failed} index file(s) out of date. Run: npm run build:index`);
  process.exit(1);
}
