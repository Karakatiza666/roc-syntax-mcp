// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Selects the copy of the server that a gate script runs, so that
// `plugin validate` works in every install:
//
// | Install          | Tree   | Loader                    |
// |------------------|--------|---------------------------|
// | A checkout       | src/   | tsx                       |
// | From git         | src/   | bin/strip-types.js        |
// | From npm         | dist/  | none. It ships no source  |
// | Any, under Bun   | either | none. Bun reads .ts       |
//
// In a checkout, src/ has priority over dist/. A gate must check the current
// source, and dist/ is only as new as the last build.

import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const ROOT = path.join(import.meta.dirname, "..");
const SOURCE = fs.existsSync(path.join(ROOT, "src", "index.ts"));

function loader() {
  if (!SOURCE || process.versions.bun) return null;
  try {
    return import.meta.resolve("tsx/esm");
  } catch {
    return pathToFileURL(path.join(ROOT, "bin", "strip-types.js")).href;
  }
}
const LOADER = loader();

/** The file of server module `name`, such as `scopes` or `index`. */
export const entry = (name) => path.join(ROOT, SOURCE ? "src" : "dist", `${name}.${SOURCE ? "ts" : "js"}`);

/** Node arguments that run server module `name`, for a spawn. */
export const nodeArgs = (name) => [...(LOADER ? ["--import", LOADER] : []), entry(name)];

/** Import server module `name` from this tree. */
export async function load(name) {
  if (LOADER) await import(LOADER);
  return import(pathToFileURL(entry(name)).href);
}
