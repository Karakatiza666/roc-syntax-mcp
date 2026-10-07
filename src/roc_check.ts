// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Prepares source for `roc check`, and formats the compiler's report for the
// model. The module solves two problems, both measured on nightly db56022:
//
// 1. Bare code, e.g. a handler, gets "missing header" unless it is wrapped in
//    an app.
// 2. A package that does not build under the pinned nightly hides the real
//    errors. An app with one error that adds `gregorian` gets 15 errors. 14 of
//    them are in `Date.roc`, and no edit to the submitted code can fix them.

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { type Catalog, type ScopeName } from "./scopes.ts";

const ROOT = path.join(import.meta.dirname, "..");

// -----------------------------------------------------------------------------
// Scratch space
// -----------------------------------------------------------------------------

/**
 * A temporary directory that the compiler does not delete.
 *
 * At startup, `roc check` deletes every `/tmp/roc-*` directory to clear scratch
 * space from earlier runs. A directory named `roc-check-XXXX` disappears between
 * the write and the read, and the compiler reports its input file as not found.
 * On nightly db56022, `roc version` and `roc fmt` keep those directories and
 * `roc check` removes them. The same source under `mcp-roc-check-XXXX` checks
 * normally.
 */
export function scratchDir(purpose: string): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), `mcp-roc-${purpose}-`));
}

// -----------------------------------------------------------------------------
// Scaffolding
// -----------------------------------------------------------------------------

/** Everything above this marker is the prelude. */
const USER_CODE_MARKER = /^#\s*@user-code\s*$/;
/** Heads a definition the scaffold supplies only when the code omits it. */
const DEFAULT_MARKER = /^#\s*@default\s+(\S+)\s*$/;

const HEADER_KEYWORD = /^(app|module|package|platform|hosted)\b/;
/** A top-level type or value declaration, which is anything at column zero. */
const TOP_LEVEL_DECL = /^([A-Za-z_]\w*!?)\s*(:|=)(?!=)/;
const IMPORT = /^import\s+(?:\w+\.)?(\w+)/;

interface Template {
  prelude: string[];
  defaults: { name: string; lines: string[] }[];
}

/** Keyed by scaffold file, so two catalogs that give one scope different scaffolds never share a template. */
const templates = new Map<string, Template>();

function template(file: string): Template {
  const cached = templates.get(file);
  if (cached) return cached;

  // `path.resolve`, not `path.join`, because a declared plugin's scaffold path
  // is absolute. Joined under the repo root, it points to a file that does not
  // exist.
  const lines = fs.readFileSync(path.resolve(ROOT, file), "utf-8").split("\n");
  const prelude: string[] = [];
  const defaults: { name: string; lines: string[] }[] = [];
  let current: { name: string; lines: string[] } | null = null;
  let started = false;
  let inPrelude = true;

  for (const line of lines) {
    if (inPrelude) {
      if (USER_CODE_MARKER.test(line)) {
        inPrelude = false;
        continue;
      }
      // Skip the file's own `##` header. It describes the scaffold file, not the
      // app, so it does not belong in the wrapped source.
      if (!started && !HEADER_KEYWORD.test(line)) continue;
      started = true;
      prelude.push(line);
      continue;
    }
    const marker = line.match(DEFAULT_MARKER);
    if (marker) {
      current = { name: marker[1], lines: [] };
      defaults.push(current);
      continue;
    }
    current?.lines.push(line);
  }

  while (prelude.length > 0 && prelude[prelude.length - 1].trim() === "") prelude.pop();
  for (const d of defaults) {
    while (d.lines.length > 0 && d.lines[d.lines.length - 1].trim() === "") d.lines.pop();
  }

  const parsed = { prelude, defaults };
  templates.set(file, parsed);
  return parsed;
}

/** True when the source already opens with a module header of its own. */
export function hasHeader(code: string): boolean {
  for (const line of code.split("\n")) {
    if (line.trim() === "" || line.trimStart().startsWith("#")) continue;
    return HEADER_KEYWORD.test(line);
  }
  return false;
}

/** Names the source declares at column zero, types and values alike. */
export function topLevelNames(code: string): Set<string> {
  const names = new Set<string>();
  for (const line of code.split("\n")) {
    const m = line.match(TOP_LEVEL_DECL);
    if (m) names.add(m[1]);
  }
  return names;
}

export interface Scaffolded {
  /** The source handed to the compiler. */
  source: string;
  /** Lines the prelude added. Compiler line numbers are this much too high. */
  offset: number;
  /** Definitions the scaffold supplied because the source omitted them. */
  supplied: string[];
  /** The platform wrapped around the source, or null when nothing was wrapped. */
  scope: ScopeName | null;
  /** That platform and its release, as the report names it, or null. */
  wrappedIn: string | null;
}

/**
 * Wraps bare source in a verified app for `scope`. Source with its own header
 * comes back unchanged, because the caller wrote that header on purpose. Its
 * platform may not be the detected one.
 */
export function scaffold(code: string, scope: ScopeName | undefined, catalog: Catalog): Scaffolded {
  const bare = { source: code, offset: 0, supplied: [], scope: null, wrappedIn: null };
  const def = scope ? catalog.scopeDefs[scope] : undefined;
  if (!scope || !def?.scaffold || hasHeader(code)) return bare;
  const tpl = template(def.scaffold);

  // Drop a prelude import that the source also has. Two copies give a
  // duplicate-definition warning, which looks like a defect in the submitted code.
  const imported = new Set(
    code.split("\n").flatMap((l) => {
      const m = l.match(IMPORT);
      return m ? [m[1]] : [];
    })
  );
  const prelude = tpl.prelude.filter((l) => {
    const m = l.match(IMPORT);
    return !m || !imported.has(m[1]);
  });

  const declared = topLevelNames(code);
  const missing = tpl.defaults.filter((d) => !declared.has(d.name));

  const parts = [prelude.join("\n"), "", code.replace(/\s*$/, "")];
  for (const d of missing) parts.push("", d.lines.join("\n"));

  return {
    source: parts.join("\n") + "\n",
    offset: prelude.length + 1,
    supplied: missing.map((d) => d.name),
    scope,
    // The label does not say "bundled", because a declared plugin's platform
    // gets the same verification and is not bundled.
    wrappedIn: `${scope} ${def.version}`,
  };
}

// -----------------------------------------------------------------------------
// Reading the compiler's report
// -----------------------------------------------------------------------------

/** One block of `roc check` output. The compiler writes them to stderr. */
export interface Diagnostic {
  severity: "error" | "warning";
  /** Path named in the block header, when it names one. */
  file: string | null;
  line: number | null;
  column: number | null;
  /** The full text of the block, with its header. */
  text: string;
}

const BLOCK_START = /^──/;
const SUMMARY = /^──\s+\d+\s+(errors?|warnings?)\b/;
// The compiler pads the header to the terminal width, so the number of
// box-drawing characters before the path changes. `.*─` is greedy on purpose,
// because a match from the first dash puts the title into the path.
const LOCATION = /^.*─\s+(\S.*?):(\d+):(\d+)\s*$/;

export interface Report {
  /** Diagnostics in the submitted code, or in files beside it. */
  user: Diagnostic[];
  /** Diagnostics in a downloaded package. Nothing in the code can fix these. */
  dependency: Diagnostic[];
  /** The compiler's own closing tally, when it wrote one. */
  summary: string;
}

/**
 * A path under the package cache, e.g. `~/.cache/roc/packages/<hash>/...`. The
 * regex matches the path segment, not the resolved home directory, so it works
 * wherever XDG_CACHE_HOME points.
 */
const PACKAGE_CACHE = /[\\/]roc[\\/]packages[\\/]/;

export function parseReport(stderr: string): Report {
  const user: Diagnostic[] = [];
  const dependency: Diagnostic[] = [];
  let summary = "";

  const lines = stderr.split("\n");
  let block: string[] | null = null;

  const flush = () => {
    if (!block) return;
    const text = block.join("\n").replace(/\s*$/, "");
    const head = block[0];
    if (SUMMARY.test(head)) {
      summary = head.trim();
    } else {
      const loc = head.match(LOCATION);
      const d: Diagnostic = {
        severity: head.includes("●") ? "warning" : "error",
        file: loc ? loc[1] : null,
        line: loc ? Number(loc[2]) : null,
        column: loc ? Number(loc[3]) : null,
        text,
      };
      (d.file && PACKAGE_CACHE.test(d.file) ? dependency : user).push(d);
    }
    block = null;
  };

  for (const line of lines) {
    if (BLOCK_START.test(line)) {
      flush();
      block = [line];
    } else if (block) {
      block.push(line);
    }
  }
  flush();

  return { user, dependency, summary };
}

/**
 * Maps a diagnostic's position into the caller's own source. It subtracts the
 * prelude lines and names the file `main.roc`, because the temporary input file
 * is deleted before anyone reads the report.
 *
 * The compiler prints the path relative to its own working directory. The
 * comparison uses the resolved path, and the replacement uses the printed text.
 */
export function remap(d: Diagnostic, target: string, offset: number): Diagnostic {
  if (d.file === null || path.resolve(d.file) !== path.resolve(target)) return d;
  const line = d.line === null ? null : Math.max(1, d.line - offset);
  const from = `${d.file}:${d.line}:${d.column}`;
  const to = `main.roc:${line}:${d.column}`;
  return { ...d, file: "main.roc", line, text: d.text.replace(from, to) };
}

/**
 * Package aliases from an app or package header, keyed by the cache directory
 * of their URL. A reader can act on `gregorian/Date.roc`, but not on
 * `Ce3xuHN92F5o.../Date.roc`.
 */
export function packageAliases(source: string): Map<string, string> {
  const out = new Map<string, string>();
  for (const m of source.matchAll(/(\w+)\s*:\s*(?:platform\s+)?"(https?:[^"]+)"/g)) {
    const base = m[2].split("/").pop() ?? "";
    const dir = base.replace(/\.tar\.[a-z]+$/, "");
    if (dir) out.set(dir, m[1]);
  }
  return out;
}

/** `<alias>/Date.roc`, falling back to the cache hash when nothing names it. */
function dependencyLabel(file: string, aliases: Map<string, string>): string {
  const after = file.split(PACKAGE_CACHE)[1] ?? file;
  const [dir, ...rest] = after.split(/[\\/]/);
  const name = aliases.get(dir);
  const tail = rest.join("/");
  return name ? (tail ? `${name}/${tail}` : name) : after;
}

/**
 * Formats the report for the model. User diagnostics come first and in full.
 * Dependency diagnostics appear only as a count per file, because they are about
 * source the caller cannot edit, and they hide the errors the caller can fix.
 */
export function formatReport(
  report: Report,
  opts: {
    source: string;
    supplied: string[];
    /** `Scaffolded.wrappedIn`: the platform and release the source was wrapped in. */
    wrappedIn: string | null;
    /** Whether the compiler exited zero. */
    ok: boolean;
    /** The raw compiler output, for when no diagnostic in it parsed. */
    raw?: string;
  }
): string {
  const parts: string[] = [];

  if (opts.supplied.length > 0) {
    parts.push(
      `Wrapped in the ${opts.wrappedIn} app. ` +
        `Scaffolded: ${opts.supplied.join(", ")}. Line numbers below are your own.`
    );
  }

  const errors = report.user.filter((d) => d.severity === "error");
  const warnings = report.user.filter((d) => d.severity === "warning");
  const silent = report.user.length === 0 && report.dependency.length === 0;

  // A non-zero exit with no diagnostics means the compiler failed to run. Never
  // report it as a pass.
  if (silent && !opts.ok) {
    parts.push(
      "`roc check` exited non-zero without reporting a diagnostic, so this code " +
        "was not checked." + (opts.raw?.trim() ? ` It wrote:\n\n${opts.raw.trim()}` : "")
    );
  } else if (silent) {
    parts.push("`roc check` passed.");
  } else if (errors.length === 0) {
    parts.push(`\`roc check\` found no errors in this code${count(warnings, "warning")}.`);
  } else {
    parts.push(`\`roc check\` failed:${count(errors, "error")}${count(warnings, "warning")}.`);
  }

  for (const d of report.user) parts.push(d.text);

  if (report.dependency.length > 0) {
    const aliases = packageAliases(opts.source);
    const tally = new Map<string, number>();
    for (const d of report.dependency) {
      const label = dependencyLabel(d.file!, aliases);
      tally.set(label, (tally.get(label) ?? 0) + 1);
    }
    parts.push(
      [
        `${report.dependency.length} further ${plural(report.dependency.length, "diagnostic")} ` +
          `${report.dependency.length === 1 ? "comes" : "come"} from downloaded packages, not from this code:`,
        ...[...tally].map(([label, n]) => `  ${label}: ${n}`),
        "",
        "That source is under the package cache and no edit here changes it. " +
          "The package does not build with this compiler. Remove it, or pin a release that builds.",
      ].join("\n")
    );
  }

  return parts.join("\n\n");
}

const plural = (n: number, word: string) => (n === 1 ? word : `${word}s`);
const count = (d: Diagnostic[], word: string) =>
  d.length === 0 ? "" : ` ${d.length} ${plural(d.length, word)}`;

// -----------------------------------------------------------------------------
// Timeout
// -----------------------------------------------------------------------------

/** A downloaded dependency: a package URL in a header. */
const REMOTE_PACKAGE = /"https?:\/\/[^"]+\.tar\.[a-z]+"/;

/** With an empty cache, a 29MB platform download takes ~15s, and much longer on a slow link. */
export const REMOTE_TIMEOUT_MS = 120_000;
export const LOCAL_TIMEOUT_MS = 30_000;

/**
 * The time limit for the compiler. Source with no remote package does not wait
 * for a download. It gets the short timeout, so the tool still answers soon when
 * the compiler hangs.
 */
export function timeoutFor(source: string): number {
  return REMOTE_PACKAGE.test(source) ? REMOTE_TIMEOUT_MS : LOCAL_TIMEOUT_MS;
}
