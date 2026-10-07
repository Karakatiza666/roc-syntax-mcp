// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Loads the overview pages and joins them. This server writes these pages, not
 * upstream. There is one hand-written page per scope. An agent reads it first,
 * and it is small enough to stay in context for a whole session. The pages are
 * derived from the rest of `corpus/`, so a refresh that changes `corpus/` should
 * check them again.
 */
export function loadOverview(dir: string, pages: string[]): string {
  return pages
    .map((file) => {
      try {
        // `path.resolve` keeps the absolute overview path of a declared plugin as
        // it is and does not put it under the host's root.
        return fs.readFileSync(path.resolve(dir, file), "utf-8").trim();
      } catch (err) {
        return `# Overview unavailable\n\n${file}: ${err}`;
      }
    })
    .join("\n\n---\n\n");
}
