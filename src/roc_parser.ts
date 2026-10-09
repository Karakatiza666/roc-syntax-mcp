// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import * as fs from "node:fs";
import * as path from "node:path";
import { type BuiltinItem, parseBuiltin } from "./builtin_parser.ts";

/** A declaration in a project file. A type keeps `decl` and `head`, so a reply can print it as the source does. */
export interface RocFileItem extends Pick<BuiltinItem, "kind" | "name" | "modulePath" | "fullName" | "signature" | "docs" | "line" | "decl" | "head" | "unannotated"> {
  file: string;   // path relative to root
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
 * Extract the type declarations and the values in a Roc source file: those at
 * column 0 and those inside a `Name := [].{ ... }` block, qualified as
 * `Name.method`. An unannotated value has its lambda head as its signature. A
 * search by name finds it, and a search by type skips it.
 */
export function parseRocFile(content: string, filePath: string, root: string): RocFileItem[] {
  const file = path.relative(root, filePath);
  return parseBuiltin(content, { topLevel: true }).items.map(
    ({ kind, name, modulePath, fullName, signature, docs, line, decl, head, unannotated }) => ({
      kind, name, modulePath, fullName, signature, docs, line, decl, head, file,
      ...(unannotated ? { unannotated } : {}),
    })
  );
}
