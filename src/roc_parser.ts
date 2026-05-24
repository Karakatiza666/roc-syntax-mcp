import * as fs from "node:fs";
import * as path from "node:path";
import type { SigSearchItem } from "./sig_search.js";

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
 * Extract top-level type annotations from a Roc source file.
 * Matches `name : type` lines at column 0, collecting preceding doc comments
 * and any indented `where`-clause continuation lines.
 */
export function parseRocFile(content: string, filePath: string, root: string): RocFileItem[] {
  const items: RocFileItem[] = [];
  const lines = content.split("\n");
  const rel = path.relative(root, filePath);
  let pendingDocs: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (line.trim() === "") {
      pendingDocs = [];
      continue;
    }

    // Skip indented lines (only top-level declarations are interesting)
    if (line[0] === " " || line[0] === "\t") {
      pendingDocs = [];
      continue;
    }

    // Doc comment
    if (line.startsWith("## ") || line === "##") {
      pendingDocs.push(line === "##" ? "" : line.replace(/^##\s?/, ""));
      continue;
    }

    // Other comment lines clear pending docs
    if (line.startsWith("#")) {
      pendingDocs = [];
      continue;
    }

    // Type annotation: `name : type`
    const sigMatch = line.match(/^([a-z_]\w*!?)\s*:\s*(.+)/);
    if (sigMatch) {
      let sig = sigMatch[2].trim();
      let j = i + 1;
      // Collect indented continuation lines (e.g., multi-line `where` clauses)
      while (j < lines.length) {
        const next = lines[j];
        if (next.trim() === "") break;
        if ((next[0] === " " || next[0] === "\t") && !next.trim().startsWith("##")) {
          sig += "\n" + next;
          j++;
        } else {
          break;
        }
      }
      items.push({
        fullName: sigMatch[1],
        signature: sig,
        docs: pendingDocs.join("\n").trim(),
        file: rel,
        line: i + 1,
      });
      pendingDocs = [];
      continue;
    }

    pendingDocs = [];
  }

  return items;
}
