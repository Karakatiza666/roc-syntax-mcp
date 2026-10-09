// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The corpus registry. One `scope` names one body of Roc: the language, the
// standard library, or a platform. Tools take a `scope` parameter that selects
// one of these. Without it, a tool uses the default working set.

import * as fs from "node:fs";
import * as path from "node:path";
import { type BuiltinItem, parseBuiltin } from "./builtin_parser.ts";
import { qualifySignatures } from "./sig_search.ts";
import {
  declarations,
  forcedNamespaces,
  lookupPlaces,
  resolvePluginDir,
  unresolvedFix,
  workspaceRoot,
} from "./plugins.ts";
import {
  INDEX_FILE,
  type IndexFile,
  type ReleaseKind,
  type TreeSnapshot,
  cachedReleaseDir,
  parseExposes,
  parseHeaderDeps,
  releaseHash,
  snapshotDir,
} from "./release.ts";

export { parseExposes };

/** The number of content-hash characters used as a version: unique, and short enough to read. */
export const HASH_VERSION_LENGTH = 12;

/** The repo root every relative path in a `ScopeDef` is resolved against. */
export const ROOT = path.join(import.meta.dirname, "..");

/**
 * The name of one corpus. A string, not a union, because scopes come from
 * manifests, and the set is not known until the host reads the plugins.
 *
 * The compiler cannot catch a mistyped scope name. At startup, validation
 * rejects a manifest that claims a name already taken.
 */
export type ScopeName = string;

/**
 * The body of Roc an item came from: `builtin`, `platform:<name>`, or
 * `pkg:<repo-path>`.
 *
 * The namespace identifies the body of Roc, and `origin` is only for display. A
 * package keeps one namespace across releases. So two providers of
 * `roc-lang/http` are two candidates for one namespace, not two unrelated
 * corpora that never resolve against each other. See `docs/design/plugins.md`.
 */
export type Namespace = string;

/** Scopes in the working set when no `scope` argument is passed. */
export const DEFAULT_SCOPES: ScopeName[] = ["language", "builtin"];

export interface ScopedItem extends BuiltinItem {
  scope: ScopeName;
  /** Which body of Roc it came from. */
  ns: Namespace;
  /** The package it ships in, e.g. `basic-webserver 0.16.0` or `http 1.0.0`. */
  origin: string;
  /** The file's module name, which a platform's `exposes` list is written in. */
  module: string;
}

export interface ScopeIndex {
  items: ScopedItem[];
  /** First declaration wins: a platform's own modules precede its packages. */
  byFullName: Map<string, ScopedItem>;
  /**
   * Names that more than one namespace in this index claims, with every claimant.
   *
   * These names are legal, unlike two platforms that both claim `Cmd.exec!`. An
   * app reaches them as `http.Request` and `pf.Request`, and both compile. In
   * the app, the import alias tells the claimants apart. Here, the namespace
   * does.
   */
  collisions: Map<string, ScopedItem[]>;
  byName: Map<string, ScopedItem[]>;
  modulePaths: Set<string>;
}

/**
 * Where one tree of Roc source is read from: a directory, or a release named by
 * its tarball URL. Exactly one of the two is set.
 *
 * A release is read from the `index.json` a manifest ships, or from the tree the
 * compiler unpacked into its package cache. No release is vendored as source.
 */
export interface TreeSource {
  /** Relative to the repo root, or absolute. */
  dir?: string;
  /** A tarball URL, whose hash names the release. */
  release?: string;
}

interface ModuleDir extends TreeSource {
  /** The namespace every item in this directory belongs to. */
  ns: Namespace;
  origin: string;
  /**
   * Take each item's module from its filename rather than from in-file nesting.
   * True for a platform, where one file is one module. False for `Builtin.roc`,
   * which wraps every module in a single `Builtin :: [].{`.
   */
  moduleFromFilename: boolean;
  /**
   * Read `exposes` from this file in `dir`. A module that the list omits is
   * part of the host ABI boundary. It is indexed and addressable, but app-facing
   * search excludes it.
   */
  exposesFrom?: string;
}

/**
 * One worked program from a corpus, addressed by name, not read as a whole
 * file. The shape is the same as the topics that this server ships. The server
 * merges the topics of a plugin into that registry, so `get_roc_syntax(topic:)` can
 * answer for a platform that this server does not bundle.
 */
export interface ScopeTopic {
  /** The `topic` that `get_roc_syntax` accepts, unique across every corpus. */
  name: string;
  /** The program, relative to the repo root or absolute for a declared plugin. */
  file: string;
  description: string;
  /** What a question about this topic looks like, matched before the prose. */
  keywords: readonly string[];
}

export interface ScopeDef {
  name: ScopeName;
  /** One line, shown by `list_roc_index(kind: "scopes")`. */
  description: string;
  /** What a program here is, in a few words, for the list a caller picks from. */
  purpose: string;
  /**
   * The maintainer of this corpus, shown next to it in
   * `list_roc_index(kind: "scopes")`. Null when a declared plugin names no
   * maintainer, and the listing shows that too. A corpus can give wrong facts
   * about Roc, and this design names the maintainer rather than restricting
   * which plugins load.
   */
  maintainer: string | null;
  /** The upstream release this corpus is pinned to, when it tracks one. */
  version?: string;
  /** The page `get_roc_syntax(scope:)` returns for this scope, relative to the repo root. */
  overview?: string;
  modules: ModuleDir[];
  /** Worked programs, relative to the repo root. */
  examples?: string;
  /** Prose bundled as is, relative to the repo root. */
  docs?: string;
  /** Worked programs this corpus answers `get_roc_syntax(topic:)` with. */
  topics?: readonly ScopeTopic[];
  /**
   * Recognizes this platform in an app header's `pf: platform "..."` string.
   * Capture group 1 is the version the app pins.
   */
  detect?: RegExp;
  /**
   * App that `roc_check` wraps bare source in, relative to the repo root. Read
   * rather than written in TypeScript so the real compiler verifies it.
   */
  scaffold?: string;
  /**
   * A sample of bare source for this platform, relative to the repo root. It
   * has no header, which is the shape that `roc_check` submits.
   * `check:platforms` wraps it in `scaffold` and compiles the result, so the
   * check covers the prelude together with real source, not only alone.
   */
  sample?: string;
  /**
   * Directories of complete programs beyond `examples` that `check:platforms`
   * type-checks, relative to the repo root: topic files, and the app that holds
   * every snippet on the overview page. The server does not serve them.
   */
  checks?: string[];
}

/**
 * The prose and worked programs that a package plugin gives about its package,
 * addressed by the plugin's name. A package is not a scope. A package is in an
 * app's address space when the app header pins it, and then the registry reads
 * its items with the builtins. So a `scope` value for a package would filter
 * nothing that a caller needs.
 */
export interface PackageDoc {
  /** The plugin's name, which `get_roc_syntax(topic:)` accepts: `roc-random`. */
  name: string;
  /** The package it documents, by repo path: `kili-ilo/roc-random`. */
  id: string;
  version: string;
  /** The release URL an app header pins it by. */
  release: string;
  description: string;
  /** What the package is for, in a few words, for the catalogue. */
  purpose: string;
  maintainer: string | null;
  /** The page `get_roc_syntax(topic: <name>)` returns, relative to the repo root. */
  overview?: string;
  /** Worked programs, relative to the repo root. */
  examples?: string;
  topics?: readonly ScopeTopic[];
  /** Directories of programs that `check:platforms` compiles. Not served. */
  checks?: string[];
  /** Shipped with this server rather than installed. */
  bundled: boolean;
}

/** One package a header pins, read from that header rather than declared. */
export interface PackageDep {
  /** The alias the header binds, which its modules import through: `http`. */
  alias: string;
  /** Repo path, which is the namespace identity: `roc-lang/http`. */
  id: string;
  /** The release the header pins, and therefore the one an app must use. */
  version: string;
  /** The pin as written. Its hash is what the compiler's cache is keyed by. */
  url?: string;
  /**
   * The header that pinned the package. `app` marks a pin in the workspace's
   * app header that the active platform does not declare. The platform puts no
   * constraint on that namespace.
   */
  requiredBy?: "platform" | "app";
}

/** Somewhere the bytes of a package namespace can come from. */
export interface PackageProvider extends TreeSource {
  id: string;
  /** The release these bytes are. */
  version: string;
  /** Who ships it, named in every diagnostic about it. */
  from: string;
  /**
   * 0 is the exact release that the header pins, read from the compiler's
   * cache. 1 is a declared plugin, and 3 is this server. The lowest tier wins.
   * So the bytes that an app compiles against beat any corpus, and an installed
   * corpus beats what this server bundles. Tier 2 is unused. A plugin ships a
   * package as a corpus of its own, not as a vendored copy in a platform.
   */
  tier: 0 | 1 | 3;
}

/** Who a release read from the compiler's cache is shipped by. */
export const CACHE_PROVIDER = "the Roc package cache";

/** Why a provider that would otherwise have won was passed over. */
export interface Refusal {
  from: string;
  version: string;
  /** Exposed platform modules whose API is written in the required release. */
  crossing: string[];
}

/** One namespace a platform pins, and who ended up serving it. */
export interface PackageResolution {
  id: string;
  ns: Namespace;
  /** The release that the platform pins. No other release compiles across its API. */
  required: string;
  /**
   * Exposed modules that import this package. Empty when the package's types
   * never cross the platform's API. Then an app can pin a different release.
   */
  crossing: string[];
  /** The operator forced this namespace, so resolution refuses no release. */
  forced: boolean;
  /** Whose header `required` came from. */
  requiredBy: "platform" | "app";
  /**
   * The release that the workspace's app header pins, if it pins this
   * namespace. Resolution does not use this value. The platform's pin decides
   * what compiles across the platform's API, so an app pin that differs is a
   * conflict to report, not a second requirement.
   */
  workspaceVersion: string | null;
  provider: PackageProvider | null;
  refused: Refusal[];
}

/** `http 1.0.0`: the display string every item of a package carries. */
function packageOrigin(id: string, version: string): string {
  return `${id.split("/").pop()} ${version}`;
}

/**
 * Which provider serves one namespace, given every candidate for it.
 *
 * Tries the candidates from the lowest tier up. A release that the platform's
 * API does not accept is refused, and the next tier gets a turn. So a refusal at
 * tier 1 leaves tier 3 to answer, and every tier may be refused.
 *
 * Semver has no effect here. Two copies of one package with different content
 * are two nominal types to the compiler. Where the package crosses the
 * platform's API, a patch bump breaks the app as a major bump does.
 */
export function resolvePackage(
  dep: PackageDep,
  candidates: readonly PackageProvider[],
  crossing: string[],
  forced: boolean,
  workspaceVersion: string | null = null
): PackageResolution {
  const refused: Refusal[] = [];
  let provider: PackageProvider | null = null;
  for (const candidate of [...candidates].sort((a, b) => a.tier - b.tier)) {
    if (candidate.version !== dep.version && crossing.length > 0 && !forced) {
      refused.push({ from: candidate.from, version: candidate.version, crossing });
      continue;
    }
    provider = candidate;
    break;
  }
  return {
    id: dep.id,
    ns: `pkg:${dep.id}`,
    required: dep.version,
    crossing,
    forced,
    requiredBy: dep.requiredBy ?? "platform",
    workspaceVersion,
    provider,
    refused,
  };
}

/**
 * The message for a caller when no provider serves a namespace that the
 * platform pins.
 *
 * The alternative is to serve an incompatible release with a warning. That is
 * worse for two reasons:
 * - `roc_check` compiles against the pinned release, so it would contradict
 *   the lookup.
 * - Documentation labelled with the other release leads a model to write that
 *   pin into the app header. That pin causes a type error that the compiler
 *   cannot explain.
 *
 * With no provider, a model uses recalled Roc, which this server exists to
 * prevent. So the note names both fixes, and the end user selects one.
 */
export function formatPackageNote(
  platform: string | null,
  platformVersion: string,
  resolutions: readonly PackageResolution[]
): string | null {
  const empty = resolutions.filter((r) => !r.provider);
  if (empty.length === 0) return null;
  return empty
    .map((r) => {
      const head = `No provider serves ${r.id}.`;
      // A pin that the platform does not declare is a requirement of the app. A
      // note that the platform requires it would name a false dependency.
      const requires =
        r.requiredBy === "app" || !platform
          ? `Your app header pins ${r.required}`
          : `${platform} ${platformVersion} requires ${r.required}`;
      const who = [
        requires,
        ...r.refused.map((x) => `${x.from} serves ${x.version}`),
      ].join("; ");
      const out = `Install a package plugin at ${r.required}`;
      const forceable = r.refused[0];
      // The note names the `--force` flag because its reader cannot see the
      // server configuration and has no other way to learn about the flag.
      return forceable
        ? `${head}\n${who}.\n${out}, or run this server with --force=${r.id} to read ` +
          `${forceable.version} anyway.`
        : `${head}\n${who}.\n${out}.`;
    })
    .join("\n\n");
}

/**
 * The message when the app header pins a release other than the one that this
 * server serves.
 *
 * The compiler cannot give this message. Two copies of a package with different
 * content are two nominal types, and the compiler diagnostic names both sides
 * `Response` with no package. This server holds both pins, so it can name the
 * two releases.
 *
 * If the package crosses the platform's exposed API, the app does not compile.
 * If it does not, the app compiles, and only the signatures shown here come
 * from the wrong release.
 */
export function formatPinConflict(
  platform: string | null,
  platformVersion: string,
  resolutions: readonly PackageResolution[]
): string | null {
  const clashing = resolutions.filter(
    (r) => r.workspaceVersion && r.provider && r.provider.version !== r.workspaceVersion
  );
  if (clashing.length === 0) return null;
  return clashing
    .map((r) => {
      const head = `Your app pins ${r.id} ${r.workspaceVersion}, and this server serves ${r.provider!.version}.`;
      if (r.crossing.length === 0) {
        return `${head}\nSignatures shown for ${r.id} are ${r.provider!.version}'s. Verify with roc_check.`;
      }
      const carries = r.crossing.length === 1 ? "carries" : "carry";
      return (
        `${head}\n${r.crossing.join(", ")} ${carries} its types across ${platform}'s API, so the two ` +
        `releases are different types to the compiler and this app will not compile. ` +
        `Move the app's pin to ${r.required}, which ${platform} ${platformVersion} requires.`
      );
    })
    .join("\n\n");
}

/**
 * The manifest schema version that this host writes. The host reports a
 * different version and never refuses a manifest because of it. A manifest that
 * declares a newer version loads, because every field added after v1 is
 * optional and no existing field changes its meaning.
 */
export const SCHEMA_VERSION = 1;

/** One topic entry in a manifest, resolved against the plugin directory. */
export interface ManifestTopic {
  name: string;
  file: string;
  description: string;
  keywords: string[];
}

/**
 * One body of Roc that a manifest documents: a platform or a package, named by
 * its release. Both take the same fields. The header of the release decides the
 * kind, so no field can disagree with the bytes.
 */
export interface ManifestCorpus {
  /** Defaults to the repo name in the release URL: `roc-ray`, `joy-html`. */
  name?: string;
  /** A tarball URL, read from the manifest's `index.json`. */
  release?: string;
  /** This server's own builtins only: a directory of source, not a release. */
  dir?: string;
  /** With `dir` only: what its items are labelled with. */
  origin?: string;
  /**
   * One line for `list_roc_index(kind: "scopes")`. A platform needs one. A
   * package without one serves its signatures and documents nothing.
   */
  description?: string;
  /**
   * What a program here is, in a few words, for example "games, graphics and
   * sound". The caller selects a platform from a list of these before it writes
   * code, and three full descriptions are too long to read there. Falls back to
   * `description`.
   */
  purpose?: string;
  overview?: string;
  examples?: string;
  /** Prose bundled as is. Platform only, because only a scope serves it. */
  docs?: string;
  /** The app `roc_check` wraps bare source in. A platform only. */
  scaffold?: string;
  /** Bare source that `scaffold` wraps, so the check compiles the two as one app. */
  sample?: string;
  /**
   * The topics that this corpus serves, each a complete program in the plugin.
   * A `checks` entry makes the check compile a directory, and a topic entry
   * makes a program readable.
   */
  topics?: ManifestTopic[];
  /** Directories of complete programs beyond `examples` that `check:platforms` compiles. */
  checks?: string[];
}

/**
 * What a plugin directory declares. Data only: no regex, no path outside the
 * plugin, and no code. See `docs/design/plugins.md`.
 */
export interface PluginManifest {
  schema: number;
  /** The maintainer of the corpora. The listing shows it, and the host does not verify it. */
  maintainer?: string;
  /** The nightly the corpora were built against, reported when it differs. */
  compiler?: string;
  corpora: ManifestCorpus[];
}

/** How the host got a manifest. This sets the tier and the shipper of its packages. */
export interface LoadOptions {
  /** 1 for a declared plugin, 3 for what this server vendors. */
  tier?: 1 | 3;
  /** Who to name in a diagnostic. Defaults to each corpus's own name. */
  from?: string;
}

/** One manifest, resolved against the directory it was read from. */
export interface LoadedPlugin {
  dir: string;
  manifest: PluginManifest;
  /** The platforms, or this server's language and builtin scopes. */
  defs: ScopeDef[];
  /** The packages it documents. */
  docs: PackageDoc[];
  /** Every package it serves signatures for, documented or not. */
  providers: PackageProvider[];
}

/** The names a plugin claims: its scopes, and the pages of its packages. */
export const loadedNames = (p: LoadedPlugin): string[] => [
  ...p.defs.map((d) => d.name),
  ...p.docs.map((d) => d.name),
];

const NAME = /^[a-z][a-z0-9-]*$/;
/** What `pinFromUrl` returns as an id: a repo path, or a host and directory. */
const NAMESPACE = /^[A-Za-z0-9_.~-]+(\/[A-Za-z0-9_.~@+-]+)+$/;
const TOPIC = /^[a-z][a-z0-9_]*$/;

/**
 * The pattern that recognizes a platform in an app header. This host builds it
 * from a repo path.
 *
 * A manifest never carries a regex. An app pins every Roc platform by a release
 * URL, so a repo path is all that a plugin needs to give. A pattern from a
 * plugin would add only the risk of ReDoS.
 *
 * The prerelease suffix is part of the version. An app that pins `0.10.0-rc3`
 * pins that exact tag. A pattern that matches only `x.y.z` does not detect such
 * an app and gives no warning.
 */
export function detectPattern(repo: string): RegExp {
  const escaped = repo.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`${escaped}/releases/download/(\\d+\\.\\d+\\.\\d+(?:-[0-9A-Za-z.-]+)?)/`);
}

/**
 * Detection for a platform published at a URL other than a GitHub release. The
 * pattern matches any bundle in the same directory. Capture group 1 is the hash
 * prefix, which is the version of such a pin.
 */
export function detectHashPattern(id: string): RegExp {
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`https://${escaped}/(\\w{${HASH_VERSION_LENGTH}})\\w*\\.tar\\.(?:zst|br|gz)$`);
}

/**
 * A release that the manifest names and its `index.json` does not hold yet. A
 * separate error class, because `plugin validate` can check everything else
 * about a plugin before `plugin index` runs.
 */
export class UnindexedRelease extends Error {
  readonly release: string;
  constructor(release: string) {
    super(`${release} is not in ${INDEX_FILE}. Run: roc-syntax-mcp plugin index`);
    this.release = release;
  }
}

/** The maximum length of a `purpose`, in characters: a clause, not a sentence. */
export const PURPOSE_MAX = 60;

/** Fields that only a platform uses. A package has no app to wrap. */
const PLATFORM_ONLY = ["scaffold", "sample", "docs"] as const;
/** Prose fields. A corpus with prose needs a description for the listing. */
const PROSE = ["overview", "examples", "topics", "checks"] as const;

/**
 * A manifest and the directory holding it, turned into what the registry reads.
 *
 * This is the only constructor. This repo builds its own scopes with it, from
 * manifests next to their corpora. So a plugin goes through the same code that
 * every check script in this repo runs, and that code stays tested before any
 * plugin exists.
 *
 * Each path in a manifest is relative to the manifest. The result is relative
 * to the registry root, or absolute when `dir` is absolute.
 */
export function fromManifest(dir: string, raw: unknown, opts: LoadOptions = {}): LoadedPlugin {
  if (typeof raw !== "object" || raw === null) throw new Error("manifest is not an object");
  const m = raw as Record<string, unknown>;
  if (typeof m.schema !== "number" || !Number.isInteger(m.schema) || m.schema < 1) {
    throw new Error("schema must be a positive integer, the manifest's schema version");
  }
  if (!Array.isArray(m.corpora) || m.corpora.length === 0) throw new Error("corpora must be a non-empty list");
  const manifest = m as unknown as PluginManifest;
  const at = (p: string) => path.normalize(path.join(dir, p));
  const host = opts.tier === 3;
  // Read once at load, because the kind of each release decides what its corpus becomes.
  const held = readIndexFiles([path.resolve(ROOT, dir, INDEX_FILE)]);

  const out: LoadedPlugin = { dir, manifest, defs: [], docs: [], providers: [] };
  const names = new Set<string>();
  for (const c of manifest.corpora) {
    if (typeof c !== "object" || c === null) throw new Error("a corpus entry is not an object");
    const loaded = fromCorpus(c, at, held, host, manifest.maintainer ?? opts.from ?? null, opts);
    if (names.has(loaded.name)) throw new Error(`${loaded.name} is declared twice`);
    names.add(loaded.name);
    if (loaded.def) out.defs.push(loaded.def);
    if (loaded.doc) out.docs.push(loaded.doc);
    if (loaded.provider) out.providers.push(loaded.provider);
  }

  // A plugin that ships a platform and a package that the platform pins must
  // ship the pinned release. Any other release is a second nominal type to the
  // compiler where the package crosses the platform's API.
  for (const def of out.defs) {
    const md = def.modules.find((x) => x.release);
    const snap = md ? held.get(releaseHash(md.release!) ?? "") : undefined;
    for (const dep of snap ? snapshotDeps(snap) : []) {
      const shipped = out.providers.find((p) => p.id === dep.id);
      if (shipped && releaseHash(shipped.release ?? "") !== releaseHash(dep.url ?? "")) {
        throw new Error(
          `${def.name} ${def.version} pins ${dep.id} ${dep.version}, and this plugin ships ${shipped.version}`
        );
      }
    }
  }
  return out;
}

/** One corpus entry, checked against what its release's header says it is. */
function fromCorpus(
  c: ManifestCorpus,
  at: (p: string) => string,
  held: Map<string, TreeSnapshot>,
  host: boolean,
  maintainer: string | null,
  opts: LoadOptions
): { name: string; def?: ScopeDef; doc?: PackageDoc; provider?: PackageProvider } {
  const what = c.name ?? c.release ?? "a corpus entry";
  for (const field of ["release", "dir", "name", "origin"] as const) {
    if (c[field] !== undefined && (typeof c[field] !== "string" || c[field] === "")) {
      throw new Error(`${what}: ${field} must be a non-empty string`);
    }
  }
  // Only this server's own builtins read a directory, because `Builtin.roc` is
  // not a release. A plugin ships the index of a release, never its source.
  if ((c.dir !== undefined || c.release === undefined) && !host) {
    throw new Error(
      c.dir !== undefined
        ? `${what} names a dir. Name the release tarball URL instead, and run \`roc-syntax-mcp plugin index\``
        : `${what} needs a release`
    );
  }
  if (c.dir !== undefined && c.release !== undefined) throw new Error(`${what} names both a dir and a release`);
  if (c.origin !== undefined && c.dir === undefined) throw new Error(`${what}: origin is for a dir`);
  if (c.purpose !== undefined) {
    if (typeof c.purpose !== "string" || c.purpose === "") throw new Error(`${what}: purpose must be a non-empty string`);
    // A caller reads every line of a catalogue before writing anything, so the
    // whole list has to stay short enough to read.
    if (c.purpose.length > PURPOSE_MAX) {
      throw new Error(`${what}: purpose is ${c.purpose.length} chars, the limit is ${PURPOSE_MAX}`);
    }
  }
  if (c.description !== undefined && (typeof c.description !== "string" || c.description === "")) {
    throw new Error(`${what}: description must be a non-empty string`);
  }

  // A release gives its own repo, version and kind. A manifest field that
  // repeated one of them could only disagree with the URL or the bytes.
  let pin: { id: string; version: string } | null = null;
  let kind: ReleaseKind | null = null;
  if (c.release !== undefined) {
    const hash = releaseHash(c.release);
    if (!hash) throw new Error(`${what}: release is not a tarball URL: ${c.release}`);
    pin = pinFromUrl(c.release);
    if (!pin) throw new Error(`${what}: release is not a URL a header can pin: ${c.release}`);
    const snap = held.get(hash);
    if (!snap) throw new UnindexedRelease(c.release);
    kind = snap.kind;
    if (!kind) throw new Error(`${c.release} has neither a platform nor a package header`);
  }
  // The repo name, or the last directory of a URL that is not a GitHub release.
  // A directory that is only a version number is not a name, so that corpus
  // must declare `name`.
  const name = c.name ?? pin?.id.split("/").at(-1);
  if (typeof name !== "string" || !NAME.test(name)) {
    throw new Error(`${what}: not a valid name: ${name}${c.name ? "" : ". Give the corpus a name"}`);
  }

  if (kind !== "platform") {
    for (const field of PLATFORM_ONLY) {
      if (c[field] !== undefined) throw new Error(`${name}: ${field} is for a platform, and ${name} is a package`);
    }
  }
  const prose = {
    ...(c.overview && { overview: at(c.overview) }),
    ...(c.examples && { examples: at(c.examples) }),
    ...(c.checks && { checks: c.checks.map(at) }),
    ...(c.topics && { topics: parseTopics(c.topics, at) }),
  };

  if (kind === "package") {
    const provider: PackageProvider = {
      id: pin!.id,
      version: pin!.version,
      release: c.release!,
      from: opts.from ?? name,
      tier: opts.tier ?? 1,
    };
    if (!c.description) {
      for (const field of PROSE) {
        if (c[field] !== undefined) throw new Error(`${name}: ${field} needs a description`);
      }
      return { name, provider };
    }
    const doc: PackageDoc = {
      name,
      id: pin!.id,
      version: pin!.version,
      release: c.release!,
      description: c.description,
      purpose: c.purpose ?? c.description,
      maintainer,
      bundled: host,
      ...prose,
    };
    return { name, doc, provider };
  }

  if (!c.description) throw new Error(`${name}: a ${kind ?? "scope"} needs a description`);
  const def: ScopeDef = {
    name,
    description: c.description,
    purpose: c.purpose ?? c.description,
    // If the manifest names no maintainer, this is `opts.from`: this server for
    // what it ships, and null for a plugin.
    maintainer,
    modules: [],
    ...prose,
    ...(c.docs && { docs: at(c.docs) }),
    ...(c.scaffold && { scaffold: at(c.scaffold) }),
    ...(c.sample && { sample: at(c.sample) }),
  };
  if (kind === "platform") {
    def.version = pin!.version;
    def.detect = isHashVersion(c.release!) ? detectHashPattern(pin!.id) : detectPattern(pin!.id);
    def.modules.push({
      release: c.release!,
      ns: `platform:${name}`,
      origin: `${name} ${pin!.version}`,
      moduleFromFilename: true,
      exposesFrom: "main.roc",
    });
  } else if (c.dir !== undefined) {
    def.modules.push({ dir: at(c.dir), ns: name, origin: c.origin ?? name, moduleFromFilename: false });
  }
  return { name, def };
}

/** A manifest's topics, checked and resolved against its directory. */
function parseTopics(topics: ManifestTopic[], at: (p: string) => string): ScopeTopic[] {
  const seen = new Set<string>();
  return topics.map((t) => {
    if (typeof t?.name !== "string" || !TOPIC.test(t.name)) throw new Error(`bad topic name: ${t?.name}`);
    if (seen.has(t.name)) throw new Error(`topic ${t.name} is declared twice`);
    seen.add(t.name);
    if (typeof t.file !== "string" || t.file === "") throw new Error(`topic ${t.name} needs a file`);
    if (typeof t.description !== "string" || t.description === "") {
      throw new Error(`topic ${t.name} needs a description`);
    }
    if (!Array.isArray(t.keywords) || t.keywords.length === 0) {
      throw new Error(`topic ${t.name} needs keywords`);
    }
    return { name: t.name, file: at(t.file), description: t.description, keywords: t.keywords };
  });
}

/**
 * Parsed index files, keyed by path and checked against size and mtime. A
 * manifest load reads its index for the kind of each release, and the registry
 * reads the index again for the signatures. A megabyte of JSON is worth parsing
 * only once.
 */
const parsedIndexes = new Map<string, { stamp: string; parsed: IndexFile | null }>();

function readIndexFile(file: string): IndexFile | null {
  let stamp: string;
  try {
    const st = fs.statSync(file);
    stamp = `${st.size}:${st.mtimeMs}`;
  } catch {
    return null;
  }
  const hit = parsedIndexes.get(file);
  if (hit?.stamp === stamp) return hit.parsed;
  let parsed: IndexFile | null;
  try {
    parsed = JSON.parse(fs.readFileSync(file, "utf-8"));
  } catch {
    parsed = null;
  }
  parsedIndexes.set(file, { stamp, parsed });
  return parsed;
}

/** Pre-built snapshots by release hash. A missing or unreadable file adds none. */
export function readIndexFiles(files: readonly string[]): Map<string, TreeSnapshot> {
  const out = new Map<string, TreeSnapshot>();
  for (const file of files) {
    // The first file wins, and this server's own files come first. One hash is
    // one set of bytes, so a later file can only agree or be wrong. A plugin
    // must never replace the snapshot of a release that this server documents.
    for (const [hash, entry] of Object.entries(readIndexFile(file)?.releases ?? {})) {
      if (!out.has(hash)) out.set(hash, entry.snapshot);
    }
  }
  return out;
}

/** This server ships what it vendors, at the last tier. */
const HOST: LoadOptions = { tier: 3, from: "roc-syntax-mcp" };

/**
 * Manifests this server ships, in the order their scopes are listed. The
 * language and builtin scopes share `corpus/language/`, one manifest with two
 * corpora.
 */
const CORE_DIRS = [
  "corpus/language",
  "corpus/platforms/basic-webserver",
  "corpus/platforms/basic-cli",
  "corpus/packages/http",
  "corpus/packages/roc-parser",
  "corpus/packages/roc-random",
];

/**
 * Every scope and every vendored package that this server ships. The module
 * reads them at load because they are checked-in data, the same for every
 * server. `loadCatalog` reads what an operator declares, and only when called.
 *
 * A malformed manifest here throws at load and does not become a diagnostic.
 * These manifests are checked in, and every check script in this repo reads
 * them.
 */
const CORE_PLUGINS: readonly LoadedPlugin[] = CORE_DIRS.map((dir) =>
  fromManifest(dir, JSON.parse(fs.readFileSync(path.join(ROOT, dir, "plugin.json"), "utf-8")), HOST)
);

/**
 * Names that this server owns. A plugin that claims one would displace the
 * language reference or the standard library, and no `scope` argument can
 * prevent that.
 */
export const RESERVED_SCOPES: ReadonlySet<string> = new Set(["language", "builtin"]);

/** A problem that an operator must fix. The host reports it and continues without the item. */
export interface LoadDiagnostic {
  /** What was asked for: a plugin, or a namespace to force. */
  kind: "plugin" | "force";
  /** The spec as written, so that the operator can find it at its source. */
  subject: string;
  source: string;
  problem: string;
}

/** One declaration, resolved and checked, before the host acts on the result. */
export interface DeclarationOutcome {
  spec: string;
  source: string;
  /** Where the spec resolved to, or null when it resolved to nothing at all. */
  dir: string | null;
  /** What the host would serve from it, or null when it would serve nothing. */
  loaded: LoadedPlugin | null;
  /** Why it is not being served, or null. */
  problem: string | null;
}

/**
 * Every declared plugin, resolved and checked, with no action on the result.
 *
 * Startup acts on this result and `plugin doctor` prints it. So the operator
 * sees the rule that the server applies, not a second copy of the rule.
 */
export function inspectDeclarations(
  argv: readonly string[],
  env: Record<string, string | undefined>,
  workspace: string,
  taken: ReadonlySet<ScopeName> = CORE_NAMES
): DeclarationOutcome[] {
  const out: DeclarationOutcome[] = [];
  const claimed = new Set(taken);
  for (const { spec, source } of declarations(argv, env)) {
    const row = (dir: string | null, loaded: LoadedPlugin | null, problem: string | null) =>
      out.push({ spec, source, dir, loaded, problem });
    let dir: string;
    try {
      dir = resolvePluginDir(spec, workspace, lookupPlaces(env));
    } catch (err) {
      row(null, null, reason(err));
      continue;
    }
    let loaded: LoadedPlugin;
    try {
      loaded = fromManifest(dir, JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8")));
    } catch (err) {
      row(dir, null, reason(err));
      continue;
    }
    // A path outside the plugin's directory reads a file that the operator did
    // not install.
    const escaping = manifestPaths(loaded.manifest).find((p) => path.relative(dir, path.resolve(dir, p)).startsWith(".."));
    if (escaping) {
      row(dir, null, `${escaping} is outside the plugin`);
      continue;
    }
    // A package name addresses its page, as a scope name addresses its corpus,
    // so both kinds share one set of names. The check accepts or rejects the
    // whole plugin. A plugin is one install, and half a plugin would serve pages
    // whose platform is absent.
    const names = loadedNames(loaded);
    const reserved = names.find((n) => RESERVED_SCOPES.has(n));
    const taken = names.find((n) => claimed.has(n));
    if (reserved || taken) {
      row(dir, null, reserved ? `${reserved} is a reserved name` : `${taken} is already loaded`);
      continue;
    }
    for (const n of names) claimed.add(n);
    row(dir, loaded, null);
  }
  return out;
}

/** One forced namespace, checked, before the host acts on the result. */
export interface ForceOutcome {
  /** The namespace id as written. */
  spec: string;
  source: string;
  /** Why it will be ignored, or null. */
  problem: string | null;
}

/**
 * Every namespace that the operator forces, checked, with no action on the
 * result.
 *
 * `plugin doctor` needs the result without a running server, for the same
 * reason that `inspectDeclarations` exists. An id that is not a repo path
 * cannot name a namespace, so this function reports it and does not drop it.
 * The operator wrote the id to change a resolution, and a typo would leave the
 * resolution unchanged with no sign of the cause.
 */
export function inspectForced(argv: readonly string[], env: Record<string, string | undefined>): ForceOutcome[] {
  return forcedNamespaces(argv, env).map(({ spec, source }) => ({
    spec,
    source,
    problem: NAMESPACE.test(spec) ? null : "not a repo path or a URL's directory, so it names no namespace",
  }));
}

const reason = (err: unknown) => (err instanceof Error ? err.message : String(err));

/** Every path a manifest asks the host to read, relative to its directory. */
export function manifestPaths(m: PluginManifest): string[] {
  const corpora = m.corpora ?? [];
  return [
    // The snapshot a `release` is read from, written by `plugin index`.
    corpora.some((c) => c?.release) ? INDEX_FILE : undefined,
    ...corpora.flatMap((c) => [
      c.dir,
      c.overview,
      c.examples,
      c.docs,
      c.scaffold,
      c.sample,
      ...(c.checks ?? []),
      ...(c.topics ?? []).map((t) => t.file),
    ]),
  ].filter((p): p is string => typeof p === "string");
}

const CORE_NAMES = new Set(CORE_PLUGINS.flatMap(loadedNames));

/**
 * The nightly that every bundled corpus was checked against.
 *
 * The host reports a plugin that names a different nightly, and never refuses
 * it. The end user decides whether a plugin is stale, and a host update must
 * never invalidate a plugin that they installed.
 */
export const BUNDLED_COMPILER: string =
  fs.readFileSync(path.join(ROOT, "corpus", "language", "UPSTREAM"), "utf-8").match(/^compiler\s+(\S+)/m)?.[1] ?? "";

/**
 * The packages that this server vendors. With this tier, the shipped corpora
 * work with no plugins installed.
 *
 * basic-webserver and basic-cli both re-export roc-lang/http and pin the same
 * tarball. So its own manifest under `corpus/packages/http` vendors it once,
 * and the header of each platform puts it in that platform's address space.
 *
 * lukewilliamboswell/roc-parser is indexed on the same terms, and no platform
 * pins it. A script gets CSV, YAML, XML and Markdown parsers when its own app
 * header pins the package, and `addressSpace` indexes it from there.
 *
 * kili-ilo/roc-random is vendored at the release roc-ray pins, so that
 * plugin's `rand` dependency has a provider with nothing else installed.
 */
export const HOST_PACKAGES: readonly PackageProvider[] = CORE_PLUGINS.flatMap((p) => p.providers);

/**
 * The maximum number of tokens that all loaded plugins together add to the
 * `tools/list` entry of one tool.
 *
 * The budget is per tool, not per plugin, because `plugin add` serves a plugin
 * in every workspace. A per-plugin budget sets no limit when ten plugins load.
 * Past the budget, a tool points to `list_roc_index` for the rest, and that
 * costs the same for any number of plugins. `src/resources.test.ts` has a
 * separate budget for the shipped tool text.
 *
 * 180 because a platform plugin adds 25 to 33 tokens of topic names to
 * `get_roc_syntax`, so 180 covers the topics of about six plugins. Other
 * tools grow by 3 to 6 tokens per plugin and rarely reach the limit.
 * `docs/design/plugins.md` has the table.
 */
export const PLUGIN_TOOL_GROWTH = 180;

/**
 * What one server serves: the corpora that this repo ships, then the plugins
 * that an operator declared. A value, not module state, so a server is built
 * from one catalog, and `plugin doctor` and the tests can build another.
 */
export interface Catalog {
  /** Core first, so a plugin never displaces a scope this server ships. */
  readonly plugins: readonly LoadedPlugin[];
  /** What an operator has to fix, in declaration order. Empty in a clean install. */
  readonly diagnostics: readonly LoadDiagnostic[];
  /** The namespaces that the operator forces. Only configuration sets them, never a manifest. */
  readonly forced: readonly string[];
  /** The scopes a `scope` argument accepts, in listing order. */
  readonly scopes: readonly ScopeName[];
  readonly scopeDefs: Record<ScopeName, ScopeDef>;
  /** Every package a loaded plugin documents, this server's first. */
  readonly packageDocs: readonly PackageDoc[];
  /** The packages of declared plugins: tier 1, above anything this server vendors. */
  readonly pluginPackages: readonly PackageProvider[];
  /** The scopes declared plugins add, as opposed to the ones this server ships. */
  readonly pluginScopes: ReadonlySet<ScopeName>;
  /** The packages declared plugins document, by plugin name. Their topics are filed under `language`. */
  readonly pluginDocNames: ReadonlySet<string>;
  /** Scopes that track an upstream release: the platforms, in declaration order. */
  readonly platformScopes: readonly [ScopeName, ...ScopeName[]];
  /**
   * The platforms that an operator declared, as opposed to the platforms that
   * this server bundles with every install.
   *
   * The difference is consent. Nobody chose basic-cli and basic-webserver, so
   * neither is evidence about the workspace. An installed plugin is a choice by
   * the user. Until detection contradicts it, that plugin is the best evidence
   * of the platform that the caller means.
   */
  readonly declaredPlatforms: readonly ScopeName[];
  /** Every `index.json` the loaded manifests ship, by absolute path. */
  readonly indexFiles: readonly string[];
}

function catalogOf(
  declared: readonly LoadedPlugin[],
  forced: readonly string[],
  diagnostics: readonly LoadDiagnostic[]
): Catalog {
  const plugins = [...CORE_PLUGINS, ...declared];
  const scopes = plugins.flatMap((p) => p.defs.map((d) => d.name));
  const scopeDefs: Record<ScopeName, ScopeDef> = Object.fromEntries(
    plugins.flatMap((p) => p.defs.map((d) => [d.name, d] as const))
  );
  return {
    plugins,
    diagnostics,
    forced,
    scopes,
    scopeDefs,
    packageDocs: plugins.flatMap((p) => p.docs),
    pluginPackages: declared.flatMap((p) => p.providers),
    pluginScopes: new Set(declared.flatMap((p) => p.defs.map((d) => d.name))),
    pluginDocNames: new Set(declared.flatMap((p) => p.docs.map((d) => d.name))),
    platformScopes: scopes.filter((s) => scopeDefs[s].version) as [ScopeName, ...ScopeName[]],
    declaredPlatforms: declared.flatMap((p) => p.defs.flatMap((d) => (d.version ? [d.name] : []))),
    indexFiles: plugins.map((p) => path.resolve(ROOT, p.dir, INDEX_FILE)),
  };
}

/** What this server ships, with nothing declared. The plugin CLI and the check scripts read it. */
export const CORE: Catalog = catalogOf([], [], []);

/**
 * The catalog a server started with `argv` and `env` serves: every declared
 * plugin, loaded around whatever fails.
 *
 * This function never throws. An MCP server that fails at startup is almost
 * impossible to diagnose over stdio, and the language, the builtins and the
 * bundled platforms do not depend on any plugin. The installed set is global,
 * so a throw on one stale entry would stop the server in every workspace.
 * `diagnostics` holds what failed, and the server reports it.
 */
export function loadCatalog(
  argv: readonly string[],
  env: Record<string, string | undefined>,
  workspace: string = workspaceRoot(env, argv)
): Catalog {
  const diagnostics: LoadDiagnostic[] = [];
  const forced: string[] = [];
  for (const f of inspectForced(argv, env)) {
    if (f.problem) diagnostics.push({ kind: "force", subject: f.spec, source: f.source, problem: f.problem });
    else forced.push(f.spec);
  }
  const declared: LoadedPlugin[] = [];
  for (const d of inspectDeclarations(argv, env, workspace)) {
    if (d.loaded) {
      declared.push(d.loaded);
    } else {
      const problem = d.dir === null ? `does not resolve: ${d.problem}. ${unresolvedFix(d)}` : d.problem!;
      diagnostics.push({ kind: "plugin", subject: d.spec, source: d.source, problem });
    }
  }
  return catalogOf(declared, forced, diagnostics);
}

/** How far a scope's or a package's plugin has drifted from this host, or null. */
export function staleness(catalog: Catalog, name: string): string | null {
  const m = catalog.plugins.find((p) => loadedNames(p).includes(name))?.manifest;
  if (!m) return null;
  const notes: string[] = [];
  if (m.compiler && m.compiler !== BUNDLED_COMPILER) {
    notes.push(`Built against ${m.compiler}, which this server does not bundle.`);
  }
  if (m.schema < SCHEMA_VERSION) notes.push(`Manifest schema ${m.schema}, current is ${SCHEMA_VERSION}.`);
  return notes.length > 0 ? notes.join(" ") : null;
}

/**
 * The namespace and release a pin URL names, or null for a pin that is not one.
 *
 * A pin is anything a header can name and `roc deps` can fetch: an https URL
 * whose file name is the tarball's content hash. A GitHub release URL carries
 * more, so its repo path is the identity and its tag the version. Any other URL
 * carries only where it is and what it holds, so its host and directory are the
 * identity and its hash the version. A local path pin is neither, and is not a
 * namespace anyone else can provide.
 *
 * Both kinds of header use this one function. An app header and a platform
 * header pin the same packages in the same form, and two different rules would
 * split one namespace in two.
 */
export function pinFromUrl(url: string): { id: string; version: string } | null {
  // A GitHub release is read with no hash check: the compiler checks the hash,
  // and `init`'s placeholder URL still has to name its repo and tag.
  const gh = url.match(/github\.com\/([^/]+\/[^/]+)\/releases\/download\/([^/]+)\//);
  if (gh) return { id: gh[1], version: gh[2] };
  // The hash must have the compiler's format, base58 with no 0, O, I or l,
  // because nothing else shows that a URL outside GitHub releases is a package.
  // A commit archive named by a hex SHA looks like a tarball, but `roc deps`
  // refuses it.
  const hash = releaseHash(url);
  if (!hash || !/^[1-9A-HJ-NP-Za-km-z]{32,64}$/.test(hash) || /^[0-9a-f]+$/.test(hash)) return null;
  const id = url.replace(/^https:\/\//, "").replace(/\/[^/]+$/, "");
  return { id, version: hash.slice(0, HASH_VERSION_LENGTH) };
}

/** Whether a pin's version is a release tag, which orders, or a content hash, which only compares. */
export function isHashVersion(url: string): boolean {
  return !/github\.com\/[^/]+\/[^/]+\/releases\/download\//.test(url);
}

/** A snapshot's pins as namespaces. A local path pin names none, so it is dropped. */
function snapshotDeps(snap: TreeSnapshot): PackageDep[] {
  return snap.deps.flatMap((d) => {
    const pin = pinFromUrl(d.url);
    return pin ? [{ alias: d.alias, ...pin, url: d.url }] : [];
  });
}

/**
 * The packages a header binds: a platform's `packages { ... }` block, or the
 * unnamed brace group after a package header's public module list.
 *
 * The registry reads these from the header, as it reads `exposes`, and no
 * manifest declares them. A refresh that repins a package must not leave a
 * second copy of the old version. The pin in the header is the one that the
 * platform was compiled against.
 */
export function parsePackageDeps(content: string): PackageDep[] {
  return snapshotDeps({ kind: null, exposes: null, deps: parseHeaderDeps(content), modules: [] });
}

/** One tree's items, labelled with where they came from. */
function indexTree(
  snap: TreeSnapshot,
  scope: ScopeName,
  md: Omit<ModuleDir, "dir" | "release">
): ScopedItem[] {
  // Only a module entry that names its header file applies the header's
  // `exposes`. Without `exposesFrom`, no module is hidden.
  const exposed = md.exposesFrom && snap.exposes ? new Set(snap.exposes) : null;

  const out: ScopedItem[] = [];
  for (const mod of snap.modules) {
    const moduleName = mod.name;
    // A module the platform does not expose is host-only, whatever its methods
    // are named. `Host`, `Internal*` and `SplitList` are the six such modules.
    const hidden = exposed !== null && !exposed.has(moduleName);

    for (const item of mod.items) {
      let { modulePath, fullName, tier } = item;
      if (md.moduleFromFilename && modulePath === "" && item.name !== moduleName) {
        // A file-level declaration that does not name its file sits outside the
        // module block, so no application can write it: `Html.HtmlNode` does not
        // compile, and `Html.Node` is the alias inside the block that does. It
        // is still indexed, because it appears in the signatures of methods that
        // are public. `IOErr.roc` declaring `IOErr` is the reachable case.
        modulePath = moduleName;
        fullName = `${moduleName}.${item.name}`;
        tier = "private";
      }
      out.push({
        ...item,
        tier: hidden ? "host" : tier,
        modulePath,
        fullName,
        scope,
        ns: md.ns,
        origin: md.origin,
        module: moduleName,
      });
    }
  }
  // After the renames above, so the full name of a file-level type includes its module.
  qualifySignatures(out);
  return out;
}

function buildIndex(items: ScopedItem[]): ScopeIndex {
  const byFullName = new Map<string, ScopedItem>();
  const claims = new Map<string, ScopedItem[]>();
  const byName = new Map<string, ScopedItem[]>();
  const modulePaths = new Set<string>();
  for (const item of items) {
    // First wins rather than last, so the platform's own module keeps the slot
    // when a package it re-exports claims the same name.
    if (!byFullName.has(item.fullName)) byFullName.set(item.fullName, item);
    const claimed = claims.get(item.fullName);
    if (claimed) claimed.push(item);
    else claims.set(item.fullName, [item]);
    const bucket = byName.get(item.name);
    if (bucket) bucket.push(item);
    else byName.set(item.name, [item]);
    // Only a type with methods counts as a module. A bare nominal type does not.
    if (item.kind === "value" && item.modulePath) modulePaths.add(item.modulePath);
  }
  // A lookup of a name that two namespaces claim returns both. A name that one
  // namespace claims twice is a parser bug, and `src/scopes.test.ts` asserts
  // that none exists.
  const collisions = new Map<string, ScopedItem[]>();
  for (const [name, claimants] of claims) {
    if (new Set(claimants.map((c) => c.ns)).size > 1) collisions.set(name, claimants);
  }
  return { items, byFullName, collisions, byName, modulePaths };
}

/** A file bundled with a scope: a worked program, or a page of upstream prose. */
export interface ExampleFile {
  /** The file's basename, which is also its resource id. */
  name: string;
  /** The leading heading or `##` line. */
  title: string;
  /** Absolute path. */
  path: string;
}

/** What a registry reads beyond this repo's own corpora. */
export interface RegistryOptions {
  /** What the registry serves. Defaults to what this server ships, with nothing declared. */
  catalog?: Catalog;
  /**
   * Package providers beyond what this server vendors. Plugins arrive here, and
   * a lower tier beats `HOST_PACKAGES`.
   */
  providers?: readonly PackageProvider[];
  /**
   * Package ids of namespaces that the operator forces, in addition to the
   * catalog's own. The host decides from the corpus whether a package crosses
   * the platform's API, and a plugin author may know better. Only
   * configuration sets this, never a manifest.
   */
  force?: readonly string[];
  /**
   * Scopes beyond the loaded set, for reading a corpus without registering it.
   * `plugin inspect` uses this, and a test uses it to index a foreign plugin.
   */
  defs?: Record<ScopeName, ScopeDef>;
  /** `index.json` files beyond those of the loaded manifests. */
  indexFiles?: readonly string[];
}

/** The scope pinned packages are read with: they are libraries, as the builtins are. */
export const PACKAGE_HOME: ScopeName = "builtin";

/** The pin an app header carries for its platform, as the registry needs it. */
export interface PlatformPin {
  /** The bundled scope the pin names, or null for a platform none documents. */
  scope: ScopeName | null;
  url: string;
}

export class ScopeRegistry {
  private readonly root: string;
  private readonly providers: readonly PackageProvider[];
  private readonly force: ReadonlySet<string>;
  private readonly defs: Record<ScopeName, ScopeDef>;
  private readonly scopes: readonly ScopeName[];
  private readonly indexFiles: readonly string[];
  private prebuilt: Map<string, TreeSnapshot> | null = null;
  private readonly treeCache = new Map<string, TreeSnapshot | null>();
  private readonly cache = new Map<ScopeName, ScopeIndex>();
  private readonly spaceCache = new Map<string, ScopeIndex>();
  private readonly withPinsCache = new Map<string, ScopeIndex>();
  private readonly docCacheByName = new Map<string, ScopeIndex>();
  private readonly exampleCache = new Map<string, ExampleFile[]>();
  private readonly docCache = new Map<ScopeName, ExampleFile[]>();
  private readonly packageCache = new Map<ScopeName, PackageResolution[]>();
  private readonly spacePackageCache = new Map<string, PackageResolution[]>();
  private workspacePins: readonly PackageDep[] = [];
  private workspacePlatform: PlatformPin | null = null;

  constructor(root: string, options: RegistryOptions = {}) {
    const catalog = options.catalog ?? CORE;
    this.root = root;
    this.providers = [...(options.providers ?? []), ...catalog.pluginPackages, ...HOST_PACKAGES];
    this.force = new Set([...catalog.forced, ...(options.force ?? [])]);
    this.defs = { ...catalog.scopeDefs, ...(options.defs ?? {}) };
    this.scopes = catalog.scopes;
    this.indexFiles = [...catalog.indexFiles, ...(options.indexFiles ?? [])];
  }

  def(scope: ScopeName): ScopeDef {
    return this.defs[scope];
  }

  /**
   * The package pins the workspace's own app header carries.
   *
   * An app pins its own packages, so the app header, not the platform header,
   * decides what belongs in the address space. A package that the platform does
   * not declare is still one that the app imports. If the app pins a release
   * that the platform's API refuses, the server can name the compile error
   * before the compiler reports it.
   *
   * The server sets the pins after construction because detection is
   * asynchronous, and the registry is built with the server. So this method
   * drops the caches that depend on the pins.
   */
  setWorkspacePins(pins: readonly PackageDep[]): void {
    this.workspacePins = pins;
    this.refresh();
  }

  /**
   * The platform release the workspace's app header pins.
   *
   * A bundled platform pinned at another release is read from that release, so
   * its signatures are the ones the app compiles against. The scope's overview,
   * topics and examples stay the ones written for the bundled release.
   */
  setWorkspacePlatform(pin: PlatformPin | null): void {
    this.workspacePlatform = pin;
    this.refresh();
  }

  /**
   * Drops everything read from a tree. Call it after the compiler fetches a
   * tree. Pre-built snapshots never change, so they stay.
   */
  refresh(): void {
    this.treeCache.clear();
    this.cache.clear();
    this.packageCache.clear();
    this.spacePackageCache.clear();
    this.spaceCache.clear();
    this.withPinsCache.clear();
    this.docCacheByName.clear();
  }

  /**
   * One tree of source, or null when it cannot be read.
   *
   * A release is read from a pre-built snapshot first, because the check
   * scripts tested that snapshot. Then it is read from the compiler's cache,
   * which holds the same bytes for the same hash.
   */
  tree(source: TreeSource, headerFile?: string): TreeSnapshot | null {
    if (source.dir !== undefined) {
      const dir = path.resolve(this.root, source.dir);
      const key = `dir:${dir}:${headerFile ?? ""}`;
      if (!this.treeCache.has(key)) this.treeCache.set(key, snapshotDir(dir, headerFile));
      return this.treeCache.get(key)!;
    }
    const hash = source.release ? releaseHash(source.release) : null;
    if (!hash) return null;
    this.prebuilt ??= readIndexFiles(this.indexFiles);
    const built = this.prebuilt.get(hash);
    if (built) return built;
    const key = `release:${hash}`;
    if (!this.treeCache.has(key)) {
      const dir = cachedReleaseDir(source.release!);
      this.treeCache.set(key, dir ? snapshotDir(dir, "main.roc") : null);
    }
    return this.treeCache.get(key)!;
  }

  /** Whether a release can be read without fetching it. */
  hasRelease(url: string): boolean {
    return this.tree({ release: url }) !== null;
  }

  /** A stable key for one tree, so two names for the same bytes read once. */
  private treeKey(source: TreeSource): string {
    return source.dir !== undefined
      ? `dir:${path.resolve(this.root, source.dir)}`
      : `release:${releaseHash(source.release ?? "")}`;
  }

  /**
   * Where one module entry of a scope is read from, and what to call it.
   *
   * The workspace's own pin wins over the bundled release when it names another
   * release of this platform and that release can be read. When it cannot, the
   * bundled release answers, and detection's note says the two differ.
   */
  private moduleSource(scope: ScopeName, md: ModuleDir): { source: TreeSource; origin: string } {
    const pin = this.workspacePlatform;
    if (
      md.release &&
      pin?.scope === scope &&
      releaseHash(pin.url) !== releaseHash(md.release) &&
      this.hasRelease(pin.url)
    ) {
      const version = pinFromUrl(pin.url)?.version ?? "";
      return { source: { release: pin.url }, origin: `${scope} ${version}` };
    }
    return { source: md, origin: md.origin };
  }

  /** The release of a platform this workspace reads, when it is not the bundled one. */
  servedRelease(scope: ScopeName): string | null {
    const md = this.def(scope).modules.find((m) => m.release);
    if (!md) return null;
    const { source } = this.moduleSource(scope, md);
    return source.release !== md.release ? (pinFromUrl(source.release!)?.version ?? null) : null;
  }

  /** The tree holding a scope's header, which says what it exposes and pins. */
  private headerTree(scope: ScopeName): TreeSnapshot | null {
    const md = this.def(scope).modules.find((m) => m.exposesFrom);
    if (!md) return null;
    return this.tree(this.moduleSource(scope, md).source, md.exposesFrom);
  }

  index(scope: ScopeName): ScopeIndex {
    const hit = this.cache.get(scope);
    if (hit) return hit;
    // The scope's own modules first, then the packages it pins, so a name both
    // claim resolves to the platform and reports the package beside it.
    const items = this.def(scope).modules.flatMap((md) => {
      const { source, origin } = this.moduleSource(scope, md);
      const snap = this.tree(source, md.exposesFrom);
      return snap ? indexTree(snap, scope, { ...md, origin }) : [];
    });
    for (const resolved of this.packages(scope)) {
      const p = resolved.provider;
      if (!p) continue;
      const snap = this.tree(p);
      if (!snap) continue;
      items.push(
        ...indexTree(snap, scope, {
          ns: resolved.ns,
          origin: packageOrigin(p.id, p.version),
          moduleFromFilename: true,
        })
      );
    }
    const built = buildIndex(items);
    this.cache.set(scope, built);
    return built;
  }

  /**
   * The packages this scope pins, and who serves each of them.
   *
   * Resolved once and cached, so no lookup resolves the packages again.
   */
  packages(scope: ScopeName): PackageResolution[] {
    const hit = this.packageCache.get(scope);
    if (hit) return hit;
    const out = this.deps(scope).map((dep) => this.resolve(dep, this.crossing(scope, dep)));
    this.packageCache.set(scope, out);
    return out;
  }

  /**
   * Every namespace in one address space: what the platform's header pins, then
   * what the workspace's app header pins beyond it.
   *
   * The platform's pin decides the required release where both name a
   * package. No other release compiles across the platform's API, so an app
   * pin that differs is a conflict to report, not a second requirement.
   */
  spacePackages(platform: ScopeName | null): PackageResolution[] {
    const key = platform ?? "*";
    const hit = this.spacePackageCache.get(key);
    if (hit) return hit;
    const own = platform ? this.packages(platform) : [];
    const declared = new Set(own.map((r) => r.id));
    // A pin that the platform does not declare does not cross the platform's
    // API, so any release can serve it.
    const extra = this.workspacePins
      .filter((p) => !declared.has(p.id))
      .map((p) => this.resolve({ ...p, requiredBy: "app" }, []));
    const out = [...own, ...extra];
    this.spacePackageCache.set(key, out);
    return out;
  }

  /**
   * Releases this space would read if the compiler had fetched them: the
   * platform the app pins, and every pinned package no corpus serves at the
   * pinned release. Empty when everything is pre-built or already cached.
   */
  wantedReleases(platform: ScopeName | null): string[] {
    const out: string[] = [];
    const pin = this.workspacePlatform;
    if (pin && pin.scope === platform && pin.scope !== null && !this.hasRelease(pin.url)) {
      const md = this.def(pin.scope).modules.find((m) => m.release);
      if (md && releaseHash(md.release!) !== releaseHash(pin.url)) out.push(pin.url);
    }
    for (const r of this.spacePackages(platform)) {
      if (r.provider?.version === r.required) continue;
      const url =
        r.requiredBy === "app"
          ? this.workspacePins.find((p) => p.id === r.id)?.url
          : this.deps(platform!).find((d) => d.id === r.id)?.url;
      if (url && !this.hasRelease(url)) out.push(url);
    }
    return out;
  }

  /** The platform version that the package notes name, or "" with no platform. */
  private platformVersion(platform: ScopeName | null): string {
    return platform ? (this.def(platform).version ?? "") : "";
  }

  /** `formatPackageNote` over this space's resolutions. Null when all are filled. */
  packageNote(platform: ScopeName | null): string | null {
    return formatPackageNote(
      platform,
      this.platformVersion(platform),
      this.spacePackages(platform)
    );
  }

  /** `formatPinConflict` over this space's resolutions. Null when the pins agree. */
  pinConflictNote(platform: ScopeName | null): string | null {
    return formatPinConflict(
      platform,
      this.platformVersion(platform),
      this.spacePackages(platform)
    );
  }

  /** The packages a scope's own header pins. Only a platform has one. */
  private deps(scope: ScopeName): PackageDep[] {
    const snap = this.headerTree(scope);
    return snap ? snapshotDeps(snap) : [];
  }

  /**
   * Which of a platform's exposed modules are written in a package's types.
   *
   * Two copies of one package with different content are two nominal types to
   * the compiler, and the compiler reports both under the same name. Where the
   * package crosses the platform's API, only the pinned release compiles. Where
   * it does not, an app can pin any release.
   *
   * This is an over-approximation. A module can import a package type and never
   * show it in a public signature, so this check refuses a few overrides that
   * would compile. It errs toward refusal.
   */
  private crossing(scope: ScopeName, dep: PackageDep): string[] {
    const snap = this.headerTree(scope);
    if (!snap?.exposes) return [];
    const byName = new Map(snap.modules.map((m) => [m.name, m]));
    return snap.exposes.filter((name) => byName.get(name)?.imports.includes(dep.alias) ?? false);
  }

  /** One namespace, resolved against every provider that could serve it. */
  private resolve(
    dep: PackageDep,
    crossing: string[]
  ): PackageResolution {
    const candidates = this.providers.filter((p) => p.id === dep.id);
    // The exact release the header pins, when no corpus serves it and the
    // compiler has it. Those are the bytes the app compiles against, so they
    // beat a corpus documenting some other release.
    if (dep.url && !candidates.some((c) => c.version === dep.version) && this.hasRelease(dep.url)) {
      candidates.push({ id: dep.id, version: dep.version, release: dep.url, from: CACHE_PROVIDER, tier: 0 });
    }
    const pinned = this.workspacePins.find((p) => p.id === dep.id)?.version ?? null;
    return resolvePackage(dep, candidates, crossing, this.force.has(dep.id), pinned);
  }

  /**
   * One scope, as a search in this address space reads it. The builtins scope
   * also holds every package that the app header pins beyond the platform. A
   * package is a library that an app imports, as the builtins are, and a scope
   * of its own would filter nothing that a caller needs. A platform's own
   * packages are already in its index.
   */
  scopeIndex(scope: ScopeName, platform: ScopeName | null): ScopeIndex {
    if (scope !== PACKAGE_HOME) return this.index(scope);
    const key = platform ?? "*";
    const hit = this.withPinsCache.get(key);
    if (hit) return hit;
    const built = buildIndex([...this.index(scope).items, ...this.pinnedItems(platform)]);
    this.withPinsCache.set(key, built);
    return built;
  }

  /** The items of every package the app pins beyond the platform. */
  private pinnedItems(platform: ScopeName | null): ScopedItem[] {
    const items: ScopedItem[] = [];
    for (const r of this.spacePackages(platform)) {
      if (r.requiredBy !== "app" || !r.provider) continue;
      const snap = this.tree(r.provider);
      if (!snap) continue;
      items.push(
        ...indexTree(snap, PACKAGE_HOME, {
          ns: r.ns,
          origin: packageOrigin(r.provider.id, r.provider.version),
          moduleFromFilename: true,
          // A module the package does not expose is one no app can import.
          exposesFrom: "main.roc",
        })
      );
    }
    return items;
  }

  /** The public items of `scopeIndex`, for app-facing search. */
  appFacingIn(scope: ScopeName, platform: ScopeName | null): ScopedItem[] {
    return this.scopeIndex(scope, platform).items.filter((i) => i.tier === "public");
  }

  /**
   * The items of a package that a plugin documents, read from the documented
   * release, whether or not an app pins it. A miss uses this index to name a
   * package that the app does not pin, and the checks test the package page
   * against it.
   */
  packageIndex(doc: PackageDoc): ScopeIndex {
    const hit = this.docCacheByName.get(doc.name);
    if (hit) return hit;
    const snap = this.tree({ release: doc.release });
    const built = buildIndex(
      snap
        ? indexTree(snap, PACKAGE_HOME, {
            ns: `pkg:${doc.id}`,
            origin: packageOrigin(doc.id, doc.version),
            moduleFromFilename: true,
            exposesFrom: "main.roc",
          })
        : []
    );
    this.docCacheByName.set(doc.name, built);
    return built;
  }

  /**
   * The index that a lookup by name resolves against: the language, the
   * builtins with the packages that the app pins, and one platform.
   * `search_symbols` and `get_roc_module` read this index, not a single
   * scope, so a caller who has a name never gets "not found" because of a wrong
   * corpus guess.
   *
   * At most one platform, because an app header pins exactly one. So the 197
   * names that basic-webserver and basic-cli share never collide here. The
   * other platform's `Path.read_utf8!` answers a question that this workspace
   * cannot ask.
   *
   * `null` means that no platform is pinned or requested, and then the address
   * space holds no platform. The server does not guess a platform. It tells the
   * caller where the name is and which `scope` value reaches it.
   *
   * A package that nothing pins is in no address space. A shipped or installed
   * package page does not mean that the app imports the package. Without this
   * rule, roc-random's `Random` would be next to basic-cli's in every app.
   */
  addressSpace(platform: ScopeName | null): ScopeIndex {
    const key = platform ?? "*";
    const hit = this.spaceCache.get(key);
    if (hit) return hit;
    const wanted = this.scopes.filter((s) => !this.def(s).version || s === platform);
    // The app's own pins last, so a name the platform also claims keeps the
    // platform's slot and reports the package beside it.
    const built = buildIndex([...wanted.flatMap((s) => this.index(s).items), ...this.pinnedItems(platform)]);
    this.spaceCache.set(key, built);
    return built;
  }

  /** The scope's bundled prose, in name order. */
  docs(scope: ScopeName): ExampleFile[] {
    const hit = this.docCache.get(scope);
    if (hit) return hit;
    const dir = this.def(scope).docs;
    let out: ExampleFile[] = [];
    if (dir) {
      const abs = path.resolve(this.root, dir);
      out = fs
        .readdirSync(abs)
        .filter((f) => f.endsWith(".md"))
        .sort()
        .map((f) => {
          const file = path.join(abs, f);
          const first = fs.readFileSync(file, "utf-8").split("\n")[0];
          return { name: path.basename(f, ".md"), title: first.replace(/^#+\s*/, "").trim(), path: file };
        });
    }
    this.docCache.set(scope, out);
    return out;
  }

  /** The scope's worked programs, in name order. */
  examples(scope: ScopeName): ExampleFile[] {
    return this.programs(this.def(scope).examples);
  }

  /** A documented package's worked programs, in name order. */
  packageExamples(doc: PackageDoc): ExampleFile[] {
    return this.programs(doc.examples);
  }

  private programs(dir: string | undefined): ExampleFile[] {
    if (!dir) return [];
    const abs = path.resolve(this.root, dir);
    const hit = this.exampleCache.get(abs);
    if (hit) return hit;
    const out = fs
      .readdirSync(abs)
      .filter((f) => f.endsWith(".roc"))
      .sort()
      .map((f) => {
        const file = path.join(abs, f);
        const first = fs.readFileSync(file, "utf-8").split("\n")[0];
        return {
          name: path.basename(f, ".roc"),
          title: first.startsWith("##") ? first.replace(/^##\s*/, "").trim() : "",
          path: file,
        };
      });
    this.exampleCache.set(abs, out);
    return out;
  }

  /** The public items of a scope, for app-facing search. */
  appFacing(scope: ScopeName): ScopedItem[] {
    return this.index(scope).items.filter((i) => i.tier === "public");
  }
}
