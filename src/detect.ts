// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Workspace detection. Reads the app header of the client's Roc project. If the
// header pins a platform that this server serves, detection adds that scope to
// the default working set.
//
// Detection only adds a scope and never blocks one. An explicit `scope` argument
// and the `--platform=` flag reach any corpus, whatever detection finds. See
// "Detection" in docs/plans/basic-webserver-scope.md.

import * as fs from "node:fs";
import * as path from "node:path";
import {
  type Catalog,
  isHashVersion,
  pinFromUrl,
  type PackageDep,
  type ScopeName,
} from "./scopes.ts";

export const DETECTION_TTL_MS = 24 * 60 * 60 * 1000;
/**
 * How long a result with no app header stays cached. The value is short because
 * an agent that prototypes without a header writes one next. A rescan is cheap:
 * one directory listing and a 4 KB read per file.
 */
export const EMPTY_DETECTION_TTL_MS = 5_000;

/** How long a detection stays cached: a day for a found header, seconds for none. */
export function detectionTtl(d: Detection, ttlMs = DETECTION_TTL_MS): number {
  return d.sourceFile ? ttlMs : Math.min(ttlMs, EMPTY_DETECTION_TTL_MS);
}

/**
 * How the pin in the workspace relates to the bundled corpus. `differs` means a
 * content hash other than the corpus hash. Two hashes have no order, so `older`
 * and `newer` do not apply.
 */
export type PinRelation = "match" | "older" | "newer" | "differs" | "unrecognized";

export interface Detection {
  /** The directory detection started from, and the cache key. */
  root: string;
  /** The bundled corpus the app pins, or null when nothing was recognized. */
  scope: ScopeName | null;
  /** The app file, relative to `root`, that carried the header. */
  sourceFile: string | null;
  /** The version the app pins, when the platform URL carries one. */
  detectedVersion: string | null;
  /** The raw `pf: platform "..."` string, kept for the unrecognized message. */
  platformRef: string | null;
  /**
   * The packages that the same header pins, without the platform. The packages
   * that the app imports belong in its address space, and only the header lists
   * them.
   */
  packages: PackageDep[];
  relation: PinRelation | null;
  detectedAt: number;
  /** True after the server emits the mismatch note for this root. */
  warned: boolean;
}

/** An app header at any position in the file. `PLATFORM_REF` searches one header. */
const APP_HEADER = /\bapp\s*\[[^\]]*\]\s*\{([\s\S]{0,2000}?)\}/;
const PLATFORM_REF = /\bplatform\s*"([^"]*)"/;

/** The `pf: platform "..."` target of the first app header in a file. */
export function platformRef(source: string): string | null {
  const header = source.match(APP_HEADER);
  if (!header) return null;
  const ref = header[1].match(PLATFORM_REF);
  return ref ? ref[1] : null;
}

/**
 * The packages that the first app header pins, without the platform.
 *
 * An app header binds its packages inline, and a platform header binds them in
 * a `packages { ... }` block. So this function cannot use `parsePackageDeps`.
 * Both functions parse each pin with `pinFromUrl`.
 */
export function appPins(source: string): PackageDep[] {
  const header = source.match(APP_HEADER);
  if (!header) return [];
  const out: PackageDep[] = [];
  for (const line of header[1].split("\n")) {
    const m = line.replace(/#.*$/, "").match(/^\s*(\w+)\s*:\s*(platform\s*)?"([^"]+)"/);
    if (!m || m[2]) continue;
    const pin = pinFromUrl(m[3]);
    if (pin) out.push({ alias: m[1], ...pin, url: m[3], requiredBy: "app" });
  }
  return out;
}

/** Which bundled scope a platform reference names, and the version it pins. */
export function matchPlatformRef(
  ref: string,
  catalog: Catalog
): { scope: ScopeName; version: string } | null {
  for (const name of catalog.scopes) {
    const pattern = catalog.scopeDefs[name].detect;
    if (!pattern) continue;
    const m = ref.match(pattern);
    if (m) return { scope: name, version: m[1] };
  }
  return null;
}

const sign = (d: number): number => (d < 0 ? -1 : d > 0 ? 1 : 0);

/**
 * Semver order over the release numbers, then the prerelease tail.
 *
 * A tag such as `0.10.0-rc3` has a prerelease tail, and semver orders it below
 * `0.10.0`. The tail must be split off first, because `Number("0-rc3")` is NaN.
 * Without the split, a pin equal to the bundled version compares as `newer`,
 * and the app gets a false mismatch note.
 */
export function compareVersions(a: string, b: string): number {
  const split = (v: string): [number[], string[]] => {
    const [release, ...pre] = v.split("-");
    return [release.split(".").map(Number), pre.join("-").split(".").filter(Boolean)];
  };
  const [ra, pa] = split(a);
  const [rb, pb] = split(b);
  for (let i = 0; i < Math.max(ra.length, rb.length); i++) {
    const d = sign((ra[i] ?? 0) - (rb[i] ?? 0));
    if (d !== 0) return d;
  }
  // A release ranks above each of its prereleases. A version with no tail is a release.
  if (pa.length === 0 || pb.length === 0) return sign(pb.length - pa.length);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i];
    const y = pb[i];
    if (x === undefined || y === undefined) return sign(pa.length - pb.length);
    if (x === y) continue;
    const numeric = /^\d+$/;
    // Numeric identifiers compare as numbers and rank below alphanumeric ones.
    if (numeric.test(x) && numeric.test(y)) return sign(Number(x) - Number(y));
    if (numeric.test(x) !== numeric.test(y)) return numeric.test(x) ? -1 : 1;
    return x < y ? -1 : 1;
  }
  return 0;
}

/**
 * The directories to search, nearest first: the start directory, then each
 * ancestor up to and including the git root.
 *
 * The walk up is necessary. A CLI launched from `src/` reports `src/` as both
 * cwd and root, so without the walk, detection misses an app file at the repo
 * root.
 */
export function searchPath(start: string, maxLevels = 8): string[] {
  const dirs: string[] = [];
  let dir = path.resolve(start);
  for (let i = 0; i < maxLevels; i++) {
    dirs.push(dir);
    if (fs.existsSync(path.join(dir, ".git"))) break;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return dirs;
}

/** A header is at the top of a file, so this reads only the first `bytes` bytes. */
function readHead(file: string, bytes = 4096): string {
  const fd = fs.openSync(file, "r");
  try {
    const buf = Buffer.alloc(bytes);
    const read = fs.readSync(fd, buf, 0, bytes, 0);
    return buf.subarray(0, read).toString("utf-8");
  } finally {
    fs.closeSync(fd);
  }
}

/** One file along the search path that holds an app header. */
interface HeaderHit {
  dir: string;
  file: string;
  ref: string;
  /** The start of the file. The platform and its packages come from this one read. */
  source: string;
}

/**
 * The first app header along the search path that names a recognized platform,
 * else the first app header. A workspace that holds both a real app and a local
 * platform stub is then indexed against the real app.
 */
function findAppHeader(dirs: string[], catalog: Catalog): HeaderHit | null {
  let fallback: HeaderHit | null = null;
  for (const dir of dirs) {
    let files: string[];
    try {
      files = fs.readdirSync(dir).filter((f) => f.endsWith(".roc")).sort();
    } catch {
      continue;
    }
    for (const file of files) {
      let source: string;
      try {
        source = readHead(path.join(dir, file));
      } catch {
        continue;
      }
      const ref = platformRef(source);
      if (!ref) continue;
      const hit = { dir, file, ref, source };
      if (matchPlatformRef(ref, catalog)) return hit;
      fallback ??= hit;
    }
  }
  return fallback;
}

function empty(root: string, now: number): Detection {
  return {
    root,
    scope: null,
    sourceFile: null,
    detectedVersion: null,
    platformRef: null,
    packages: [],
    relation: null,
    detectedAt: now,
    warned: false,
  };
}

/** Detects one root. Pure apart from the filesystem reads. */
export function detectAt(root: string, now: number, catalog: Catalog): Detection {
  const hit = findAppHeader(searchPath(root), catalog);
  if (!hit) return empty(root, now);

  const sourceFile = path.relative(root, path.join(hit.dir, hit.file)) || hit.file;
  const matched = matchPlatformRef(hit.ref, catalog);
  if (!matched) {
    return {
      root,
      scope: null,
      sourceFile,
      detectedVersion: null,
      platformRef: hit.ref,
      packages: appPins(hit.source),
      relation: "unrecognized",
      detectedAt: now,
      warned: false,
    };
  }

  const bundled = catalog.scopeDefs[matched.scope].version!;
  const hashed = isHashVersion(catalog.scopeDefs[matched.scope].modules[0]?.release ?? "");
  const order = hashed ? (matched.version === bundled ? 0 : NaN) : compareVersions(matched.version, bundled);
  return {
    root,
    scope: matched.scope,
    sourceFile,
    detectedVersion: matched.version,
    platformRef: hit.ref,
    packages: appPins(hit.source),
    relation: order === 0 ? "match" : Number.isNaN(order) ? "differs" : order < 0 ? "older" : "newer",
    detectedAt: now,
    warned: false,
  };
}

/**
 * The note that the server appends once per root per TTL. A detected pin that
 * differs from the bundled release is common. For example, every example in the
 * upstream 0.17.0 tag pins 0.16.0.
 */
export function mismatchNote(d: Detection, catalog: Catalog): string | null {
  if (d.relation === "unrecognized") {
    const bundled = catalog.platformScopes.map((s) => `${s} ${catalog.scopeDefs[s].version}`).join(" and ");
    return (
      `Note: your app points at a local or unrecognized platform (${d.platformRef}). ` +
      `This server indexes ${bundled} and may not match it. Use search_project_symbols ` +
      `to search the platform in your workspace instead.`
    );
  }
  if (!d.scope || !d.detectedVersion) return null;
  const bundled = catalog.scopeDefs[d.scope].version!;
  if (d.relation === "older") {
    return (
      `Note: your app pins ${d.scope} ${d.detectedVersion}, this server bundles ${bundled}. ` +
      `Anything added after ${d.detectedVersion} appears here but will not compile against ` +
      `your pin. Verify with roc_check, or move the pin to ${bundled}.`
    );
  }
  if (d.relation === "differs") {
    return (
      `Note: your app pins a ${d.scope} bundle (${d.detectedVersion}) other than the one this server ` +
      `documents (${bundled}). Signatures may differ from yours. Verify with roc_check.`
    );
  }
  if (d.relation === "newer") {
    return (
      `Note: your app pins ${d.scope} ${d.detectedVersion}, this server bundles ${bundled}. ` +
      `APIs added after ${bundled} are missing here and existing signatures may have changed. ` +
      `Treat this index as a lower bound and verify with roc_check.`
    );
  }
  return null;
}

/**
 * The note for a platform that the app pins at a release other than the bundled
 * one, when the server can read that release. The signatures then come from the
 * app's release, and only the prose written for the bundled release can differ.
 */
export function servedReleaseNote(scope: ScopeName, served: string, catalog: Catalog): string {
  const bundled = catalog.scopeDefs[scope].version!;
  return (
    `Note: your app pins ${scope} ${served}. Signatures here are read from that release. ` +
    `The overview, topics and examples were written for ${bundled}, so verify code built ` +
    `from them with roc_check.`
  );
}

/**
 * Detection results, keyed by resolved root. The TTL limits how stale a result
 * can be after an edit to the app header. `invalidate` handles the change that
 * the client reports, `notifications/roots/list_changed`.
 */
export class DetectionCache {
  private readonly entries = new Map<string, Detection>();
  // Plain fields, not constructor parameter properties, because Node cannot
  // strip that TypeScript syntax. A git install with no `dist/` runs `src/`
  // directly. `erasableSyntaxOnly` in tsconfig.json enforces this rule.
  private readonly ttlMs: number;
  private readonly catalog: Catalog;

  constructor(catalog: Catalog, ttlMs = DETECTION_TTL_MS) {
    this.catalog = catalog;
    this.ttlMs = ttlMs;
  }

  get(root: string, now: number): Detection {
    const resolved = path.resolve(root);
    const hit = this.entries.get(resolved);
    if (hit && now - hit.detectedAt < detectionTtl(hit, this.ttlMs)) return hit;
    const fresh = detectAt(resolved, now, this.catalog);
    this.entries.set(resolved, fresh);
    return fresh;
  }

  invalidate(): void {
    this.entries.clear();
  }

  get size(): number {
    return this.entries.size;
  }
}
