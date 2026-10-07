// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The signatures of a user's project, from one or more sources, cached by file
// stamps.
//
// TODO: an `lspSource` of inferred types from `roc experimental-lsp`, when it
// matures. Measured on nightly 130536d (2026-10-04):
// - Advantages over `roc docs`: it continues past a type error, prints `where`
//   clauses with the right variables, and includes unexposed modules.
// - One process per index run, never one for the server's life: a running
//   server never reloads a changed module from disk (not on reopen, not on
//   didChangeWatchedFiles, not on didOpen of the module), and memory grows
//   about 35 MB per module opened.
// - The messages of one run are initialize and initialized, then didOpen,
//   documentSymbol and hover for each file, then shutdown and exit. Each hover
//   goes to the start of a symbol of kind 12 or 13. workspace/symbol is not
//   implemented. Symbol names come qualified.
// - The type is the last ```roc block of the hover, because a doc comes first
//   and can hold its own code blocks.
// - About 8 ms to start and 200 to 300 ms per file.
// - Before you enable it, add a test under the pinned nightly that fails when
//   the hover format changes.

import * as fs from "node:fs";
import * as path from "node:path";
import { type RocFileItem, discoverRocFiles, parseRocFile } from "./roc_parser.ts";

/** `annotated` is what the source says. `inferred` is what a compiler worked out. */
export type SignatureOrigin = "annotated" | "inferred";

export interface ProjectSignature extends RocFileItem {
  origin: SignatureOrigin;
}

/** One way to read the signatures of a project's `.roc` files. */
export interface SignatureSource {
  name: string;
  /**
   * The signatures in `files` (absolute paths), with `file` relative to
   * `root`. Return null when the source cannot run here, for example with no
   * compiler on PATH. A throw becomes a note on the result.
   */
  index(root: string, files: readonly string[]): Promise<ProjectSignature[] | null>;
}

export interface ProjectSnapshot {
  root: string;
  files: number;
  items: ProjectSignature[];
  /** Why a source added nothing, for the reply. Empty when all ran. */
  notes: string[];
}

/** Annotations read from the text. Cheap, needs no compiler, and always runs. */
export const parserSource: SignatureSource = {
  name: "parser",
  async index(root, files) {
    const items: ProjectSignature[] = [];
    for (const file of files) {
      let text: string;
      try {
        text = fs.readFileSync(file, "utf-8");
      } catch {
        continue; // unreadable files are skipped
      }
      for (const it of parseRocFile(text, file, root)) items.push({ ...it, origin: "annotated" });
    }
    return items;
  },
};

/**
 * One entry per declaration. An annotation wins over an inferred type for the
 * same name, because it is the author's own wording and the compiler checks the
 * definition against it. Sources are merged in order, so the first one wins a
 * tie.
 */
export function mergeSignatures(lists: readonly ProjectSignature[][]): ProjectSignature[] {
  const byKey = new Map<string, ProjectSignature>();
  for (const list of lists) {
    for (const it of list) {
      const key = `${it.file}\0${it.fullName}`;
      const had = byKey.get(key);
      if (!had || (had.origin === "inferred" && it.origin === "annotated")) byKey.set(key, it);
    }
  }
  return [...byKey.values()];
}

/** Path, mtime and size of every file. A cached result is valid only for these values. */
function stampOf(files: readonly string[]): string {
  return files
    .map((f) => {
      try {
        const s = fs.statSync(f);
        return `${f}\0${s.mtimeMs}\0${s.size}`;
      } catch {
        return `${f}\0gone`;
      }
    })
    .sort()
    .join("\n");
}

/**
 * Caches the results of the sources. A compiler-backed source takes seconds per
 * project, and types cross modules. So any change to any file indexes the whole
 * project again, and an unchanged project gets its answer from memory.
 */
export class ProjectIndex {
  private readonly cache = new Map<string, { stamp: string; snapshot: ProjectSnapshot }>();
  private readonly running = new Map<string, { stamp: string; done: Promise<ProjectSnapshot> }>();
  private readonly sources: readonly SignatureSource[];

  constructor(sources: readonly SignatureSource[]) {
    this.sources = sources;
  }

  /** Throws only when `root` cannot be walked. */
  async get(root: string): Promise<ProjectSnapshot> {
    const abs = path.resolve(root);
    const files = discoverRocFiles(abs);
    const stamp = stampOf(files);
    const hit = this.cache.get(abs);
    if (hit?.stamp === stamp) return hit.snapshot;
    // Two calls on the same unchanged project share one run.
    const run = this.running.get(abs);
    if (run?.stamp === stamp) return run.done;

    const done = this.build(abs, files).then((snapshot) => {
      this.cache.set(abs, { stamp, snapshot });
      return snapshot;
    });
    this.running.set(abs, { stamp, done });
    try {
      return await done;
    } finally {
      if (this.running.get(abs)?.done === done) this.running.delete(abs);
    }
  }

  private async build(root: string, files: string[]): Promise<ProjectSnapshot> {
    const notes: string[] = [];
    const lists = await Promise.all(
      this.sources.map(async (s) => {
        try {
          return (await s.index(root, files)) ?? [];
        } catch (err) {
          notes.push(`${s.name}: ${err instanceof Error ? err.message : String(err)}`);
          return [];
        }
      })
    );
    return { root, files: files.length, items: mergeSignatures(lists), notes };
  }
}
