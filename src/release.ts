// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Finds the Roc source of a released platform or package. A pin names a
// release by its tarball URL. The hash in that URL identifies the release in
// two places: the `index.json` that a manifest ships, and the package cache of
// the compiler.
//
// This server vendors no platform or package source. For each release that it
// documents, it reads a pre-built snapshot. For any other release that an app
// header pins, it reads the tree that the compiler unpacked.

import { execFile, execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { promisify } from "node:util";
import { type BuiltinItem, parseBuiltin } from "./builtin_parser.ts";

const execFileAsync = promisify(execFile);

/** One `.roc` file of a release, parsed. */
export interface SnapshotModule {
  /** The file's module name, which is its basename. */
  name: string;
  /** The package aliases it imports from: `import http.Request` gives `http`. */
  imports: string[];
  items: BuiltinItem[];
}

/** One package that the header of a release pins. */
export interface SnapshotDep {
  alias: string;
  url: string;
}

/**
 * Everything that the registry reads from a tree of Roc source. The registry
 * treats a tree on disk and a pre-built snapshot the same way.
 */
export interface TreeSnapshot {
  /** The kind that the header declares, or null if the caller named no header file. */
  kind: ReleaseKind | null;
  /** The public module list of the header, or null if the caller named no header file. */
  exposes: string[] | null;
  /** What the header pins, in header order. */
  deps: SnapshotDep[];
  /** Every `.roc` file at the top of the tree, in name order. */
  modules: SnapshotModule[];
}

/** The file `scripts/build-index.ts` writes beside a manifest. */
export const INDEX_FILE = "index.json";
export const INDEX_FORMAT = 1;

export interface IndexFile {
  format: number;
  /** Keyed by release hash. */
  releases: Record<string, { url: string; snapshot: TreeSnapshot }>;
}

/** A package header's public module list: `package [A, B] { ... }`. */
const PACKAGE_EXPOSES = /(^|\n)\s*package\s*\[([^\]]*)\]/;

/**
 * The public module names that a header declares.
 *
 * The two header kinds use different syntax. A platform header puts the list
 * after the `exposes` keyword. A package header puts the list in the bracket
 * group after the `package` keyword, with no other keyword. The platform rule
 * matches nothing in a package header, and that result looks the same as a
 * platform that exposes nothing. With only the platform rule, every module of a
 * package would get host tier and would be missing from app-facing search.
 */
export function parseExposes(content: string): string[] {
  const m = content.match(/\bexposes\s*\[([^\]]*)\]/) ?? content.match(PACKAGE_EXPOSES)?.slice(1);
  if (!m) return [];
  return m[m.length - 1]
    .split(",")
    .map((s) => s.replace(/#.*$/, "").trim())
    .filter((s) => /^[A-Z]\w*$/.test(s));
}

/**
 * The pins that a header declares: the `packages { ... }` block of a platform,
 * or the unnamed brace group after the public module list of a package header.
 */
export function parseHeaderDeps(content: string): SnapshotDep[] {
  let at = content.search(/\bpackages\s*\{/);
  if (at === -1) {
    // A package header's dependency block is the brace group that follows its
    // public module list, with no keyword in front of it.
    const header = content.match(PACKAGE_EXPOSES);
    at = header?.index === undefined ? -1 : header.index + header[0].length;
  }
  if (at === -1) return [];
  let depth = 0;
  let end = at;
  for (let i = content.indexOf("{", at); i < content.length; i++) {
    if (content[i] === "{") depth++;
    else if (content[i] === "}" && --depth === 0) {
      end = i;
      break;
    }
  }
  const out: SnapshotDep[] = [];
  for (const line of content.slice(at, end).split("\n")) {
    const m = line.replace(/#.*$/, "").match(/^\s*(\w+)\s*:\s*"([^"]+)"/);
    if (m) out.push({ alias: m[1], url: m[2] });
  }
  return out;
}

/** The kind keyword that starts a header, after any comment lines. Returns null for an app header. */
export function headerKind(content: string): ReleaseKind | null {
  const first = content.match(/^(?:\s*#.*\n|\s*\n)*\s*(\w+)/)?.[1];
  return first === "platform" || first === "package" ? first : null;
}

/** Reads one directory of Roc source. The read is not recursive, because a release root is flat. */
export function snapshotDir(dir: string, headerFile?: string): TreeSnapshot | null {
  let files: string[];
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith(".roc")).sort();
  } catch {
    return null;
  }
  let header: string | null = null;
  if (headerFile) {
    try {
      header = fs.readFileSync(path.join(dir, headerFile), "utf-8");
    } catch {
      header = null;
    }
  }
  return {
    kind: header === null ? null : headerKind(header),
    exposes: header === null ? null : parseExposes(header),
    deps: header === null ? [] : parseHeaderDeps(header),
    modules: files.map((file) => {
      const content = fs.readFileSync(path.join(dir, file), "utf-8");
      const imports = [...content.matchAll(/^\s*import\s+(\w+)\./gm)].map((m) => m[1]);
      return {
        name: path.basename(file, ".roc"),
        imports: [...new Set(imports)].sort(),
        items: parseBuiltin(content).items,
      };
    }),
  };
}

/**
 * The hash in a release URL, or null if the URL is not a release URL.
 *
 * The compiler unpacks a release into a folder with this name. Thus the hash is
 * the cache key for the compiler and for this server, and this server computes
 * no hash.
 */
export function releaseHash(url: string): string | null {
  // The pattern is loose because the compiler checks the hash. A placeholder
  // such as REPLACE_WITH_THE_TARBALL from `plugin init` must load, and then
  // fail at `plugin index`.
  const m = url.match(/^https:\/\/.+\/(\w{16,64})\.tar\.(?:zst|br|gz)$/);
  return m ? m[1] : null;
}

/**
 * Every directory where the compiler may keep packages, most likely first.
 *
 * `ROC_PACKAGE_CACHE` overrides all of them. This variable is a setting of this
 * server, not of the compiler. Use it in a test, or on a machine where the
 * compiler uses a directory that this list does not have.
 */
export function packageCacheDirs(env: Record<string, string | undefined> = process.env): string[] {
  if (env.ROC_PACKAGE_CACHE) return [env.ROC_PACKAGE_CACHE];
  const home = os.homedir();
  const out: string[] = [];
  if (env.XDG_CACHE_HOME) out.push(path.join(env.XDG_CACHE_HOME, "roc", "packages"));
  out.push(path.join(home, ".cache", "roc", "packages"));
  if (process.platform === "darwin") out.push(path.join(home, "Library", "Caches", "roc", "packages"));
  if (env.LOCALAPPDATA) out.push(path.join(env.LOCALAPPDATA, "roc", "packages"));
  return out;
}

/** The unpacked tree of a release, or null if the compiler did not fetch it. */
export function cachedReleaseDir(url: string, env = process.env): string | null {
  const hash = releaseHash(url);
  if (!hash) return null;
  for (const root of packageCacheDirs(env)) {
    const dir = path.join(root, hash);
    if (fs.existsSync(path.join(dir, "main.roc"))) return dir;
  }
  return null;
}

/** What a release's header says it is. */
export type ReleaseKind = "platform" | "package";

/**
 * The source of an app that pins one release and does nothing else. `roc deps`
 * reads the header and never the body, so the body only has to exist.
 *
 * The stub pins every release as a platform, so no code has to know the kind of
 * a release before the fetch. A package that is pinned as a platform fails with
 * "invalid platform". But `roc deps` reports that error only after it checks
 * the package and unpacks it into the cache, and the fetch needs nothing more
 * (measured on nightly 130536d). A platform that is pinned as a package gets
 * the 10 MB package limit, and basic-cli 0.24.0 is larger than that limit.
 */
export function fetchStub(url: string): string {
  return `app [main!] {\n    pf: platform "${url}",\n}\n\nmain! = |_| Ok({})\n`;
}

/** How long one release may take to download, in milliseconds. */
export const FETCH_TIMEOUT_MS = 120_000;

/**
 * Runs the compiler to download releases into its cache, and waits until it
 * finishes.
 *
 * `roc deps` does these steps, and it does not compile:
 * 1. It downloads each release that a header pins.
 * 2. It checks each tarball against the hash in its URL.
 * 3. It unpacks each tarball.
 * 4. It follows the dependencies of each release.
 *
 * Thus this server reads the same bytes that `roc check` reads, and the server
 * itself never opens a network connection.
 *
 * The function runs one stub per release, in parallel. One bad URL fails a
 * whole `roc deps` run, and it must not stop the fetch of the other releases.
 * Returns the URLs that are still not in the cache.
 */
export async function fetchReleases(
  urls: readonly string[],
  opts: { roc?: string; timeout?: number } = {}
): Promise<string[]> {
  const roc = opts.roc ?? "roc";
  const wanted = [...new Set(urls)].filter((u) => releaseHash(u) && !cachedReleaseDir(u));
  if (wanted.length === 0) return [];
  // `roc check` deletes `/tmp/roc-*`, so this prefix must not start with `roc-`.
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mcp-roc-fetch-"));
  try {
    await Promise.all(
      wanted.map(async (url, i) => {
        const file = path.join(dir, `fetch${i}.roc`);
        fs.writeFileSync(file, fetchStub(url));
        try {
          await execFileAsync(roc, ["deps", file], { timeout: opts.timeout ?? FETCH_TIMEOUT_MS });
        } catch {
          // The return value reports a failure as a URL that is still missing.
          // The caller acts only on that fact.
        }
      })
    );
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  return wanted.filter((u) => !cachedReleaseDir(u));
}

/** Every release a manifest names, in manifest order. */
export function manifestReleases(manifest: { corpora?: { release?: unknown }[] }): string[] {
  const out: string[] = [];
  for (const c of manifest.corpora ?? []) {
    if (typeof c?.release === "string" && !out.includes(c.release)) out.push(c.release);
  }
  return out;
}

/**
 * The `index.json` text for these releases, each read from its unpacked tree.
 * The text is deterministic, so `--check` can compare it byte for byte.
 */
export function indexText(trees: readonly { url: string; dir: string }[]): string {
  const file: IndexFile = { format: INDEX_FORMAT, releases: {} };
  for (const { url, dir } of trees) {
    const snapshot = snapshotDir(dir, "main.roc");
    if (!snapshot) throw new Error(`${dir} holds no Roc source for ${url}`);
    file.releases[releaseHash(url)!] = { url, snapshot };
  }
  return JSON.stringify(file, null, 1) + "\n";
}

/** What indexing one manifest directory did. */
export interface IndexOutcome {
  /**
   * - `ok`: the file on disk matches.
   * - `wrote`: the function replaced the file.
   * - `stale`: the file differs under `check`, or `missing` is not empty.
   * - `none`: the manifest names no release.
   */
  status: "ok" | "wrote" | "stale" | "none";
  /** Releases that are not in the cache and that the fetch could not download. If not empty, the function wrote nothing. */
  missing: string[];
}

/**
 * Writes the `index.json` next to one manifest, and fetches the releases that
 * the compiler did not cache. With `check`, the function compares and does not
 * write.
 *
 * `plugin index` and `npm run build:index` both call this function, so they
 * always produce the same index.
 */
export async function indexManifestDir(
  dir: string,
  opts: { check?: boolean; roc?: string } = {}
): Promise<IndexOutcome> {
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8"));
  const releases = manifestReleases(manifest);
  if (releases.length === 0) return { status: "none", missing: [] };
  const missing = await fetchReleases(releases, { roc: opts.roc });
  if (missing.length > 0) return { status: "stale", missing };
  const text = indexText(releases.map((url) => ({ url, dir: cachedReleaseDir(url)! })));
  const target = path.join(dir, INDEX_FILE);
  const current = fs.existsSync(target) ? fs.readFileSync(target, "utf-8") : null;
  if (current === text) return { status: "ok", missing: [] };
  if (opts.check) return { status: "stale", missing: [] };
  fs.writeFileSync(target, text);
  return { status: "wrote", missing: [] };
}

/** Whether a `roc` binary runs, so that a caller can tell a missing compiler apart from other failures. */
export function rocRuns(roc = "roc"): boolean {
  try {
    execFileSync(roc, ["version"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}
