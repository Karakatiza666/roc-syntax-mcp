// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Removes the source from the `files` list in package.json, so that the npm
// tarball ships the build and no source.
//
// One `files` list serves two installs:
// - A git install packs the repository with this list too. It has no build, so
//   it needs src/.
// - The registry tarball has dist/, so it does not need the files that only a
//   run from source reads.
//
// The publish workflow runs this script before `npm pack`. `prepublishOnly`
// runs it with `--check`, so a publish that skipped this script stops and does
// not ship the source.
//
// Usage: node scripts/registry-files.mjs [--check]

import * as fs from "node:fs";
import * as path from "node:path";

/** What only a run from source reads: the source, and the config to build it. */
export const SOURCE_ONLY = ["src", "tsconfig.json"];

export const registryFiles = (files) => files.filter((f) => !SOURCE_ONLY.includes(f));

if (import.meta.filename === path.resolve(process.argv[1] ?? "")) {
  const file = path.join(import.meta.dirname, "..", "package.json");
  const pkg = JSON.parse(fs.readFileSync(file, "utf-8"));
  const left = pkg.files.filter((f) => SOURCE_ONLY.includes(f));
  if (process.argv[2] === "--check") {
    if (left.length > 0) {
      console.error(
        `package.json files still lists ${left.join(", ")}, which the npm tarball does not ship. ` +
          `Run \`node scripts/registry-files.mjs\` first, or publish with .github/workflows/publish-server.yml`
      );
      process.exit(1);
    }
  } else {
    pkg.files = registryFiles(pkg.files);
    fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + "\n");
    console.log(left.length > 0 ? `removed ${left.join(", ")} from files` : "files already lists no source");
  }
}
