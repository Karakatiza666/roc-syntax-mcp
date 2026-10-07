// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import * as fs from "node:fs";
import * as path from "node:path";
import { parseBuiltin } from "./builtin_parser.ts";
import type { SigSearchItem } from "./sig_search.ts";

export interface RocFileItem extends SigSearchItem {
  file: string;   // path relative to root
  line: number;
}

const SKIP_DIRS = new Set([
  ".git", "node_modules", ".cache", "dist", "build", "target", ".roc",
]);

export function discoverRocFiles(root: string): string[] {
  const results: string[] = [];

  function walk(dir: string): void {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.isDirectory()) {
        if (!SKIP_DIRS.has(entry.name) && !entry.name.startsWith(".")) {
          walk(path.join(dir, entry.name));
        }
      } else if (entry.isFile() && entry.name.endsWith(".roc")) {
        results.push(path.join(dir, entry.name));
      }
    }
  }

  walk(root);
  return results;
}

/**
 * Extract the type annotations in a Roc source file: those at column 0 and the
 * methods inside a `Name := [].{ ... }` block, qualified as `Name.method`.
 * Unannotated definitions are left out, because they have no type to search by.
 */
export function parseRocFile(content: string, filePath: string, root: string): RocFileItem[] {
  const rel = path.relative(root, filePath);
  return parseBuiltin(content, { topLevel: true })
    .items.filter((it) => it.kind === "value" && !it.unannotated)
    .map((it) => ({ fullName: it.fullName, signature: it.signature, docs: it.docs, file: rel, line: it.line }));
}
