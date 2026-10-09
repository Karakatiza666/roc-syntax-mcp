// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Every tool and resource, built by `createServer` from a `ServerConfig`.
// Importing this module reads no configuration and starts nothing.

import { McpServer, ResourceTemplate } from "@modelcontextprotocol/server";
import { z } from "zod";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const ROOT = path.join(import.meta.dirname, "..");
const FULL_SYNTAX_FILE = path.join(ROOT, "corpus", "language", "examples", "all_roc_syntax.roc");
const BUILTIN_FILE = path.join(ROOT, "corpus", "language", "Builtin.roc");
// The version comes from package.json only, so a release changes one file.
const VERSION: string = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf-8")).version;
// The largest number of nested-module items that `get_roc_module` prints
// in full. The largest roc-ray module, `App`, has 67. `Encoding` has 213 and
// `Num` 1754, and at about 15 tokens a signature, those pages cost thousands.
const NESTED_CAP = 100;

import { type BuiltinItem } from "./builtin_parser.ts";
import { loadTopic, matchTopic, topicsFor, type TopicMatch, type TopicMeta, type TopicRank } from "./topics.ts";
import { nameCoverage, question, type Question, symbolScore } from "./words.ts";
import { hintFor } from "./builtin_hints.ts";
import {
  DEFAULT_SCOPES,
  PLUGIN_TOOL_GROWTH,
  ScopeRegistry,
  loadCatalog,
  staleness,
  type Catalog,
  type ScopeIndex,
  type ScopeName,
  type ExampleFile,
  type ScopedItem,
  type PackageDoc,
} from "./scopes.ts";
import {
  formatReport,
  scratchDir,
  parseReport,
  remap,
  scaffold,
  timeoutFor,
} from "./roc_check.ts";
import { workspaceFlag, workspaceRoot } from "./plugins.ts";
import { fetchReleases } from "./release.ts";
import { rocCommand, rocMissing } from "./roc_bin.ts";
import {
  DetectionCache,
  detectionTtl,
  mismatchNote,
  servedReleaseNote,
  type Detection,
} from "./detect.ts";
import { elsewhere as elsewhereIn, type Candidate, type Reach } from "./elsewhere.ts";
import { loadOverview } from "./overview.ts";
import { compareItems, type SigMatch, searchBySig, SUBSTRING_SCORE } from "./sig_search.ts";
import { type NamePattern, nameQuality, nameRank, parseSymbolQuery } from "./symbol_query.ts";
import { type ProjectSignature, ProjectIndex, parserSource, type SignatureSource } from "./project_index.ts";

/** What one server serves, read from its arguments and environment once. */
/** What a reply prints of a declaration, from a bundled index or from a project file. */
type Decl = Pick<BuiltinItem, "kind" | "name" | "modulePath" | "fullName" | "signature" | "docs" | "decl" | "head" | "unannotated">;

export interface ServerConfig {
  catalog: Catalog;
  /** The platform `--platform=` named, or null. */
  platform: ScopeName | null;
  /** How long a lookup waits on `roc deps` before it answers from the bundled release. */
  fetchWaitMs: number;
  /** The input that locates the compiler and the workspace. The server reads it again on every call. */
  argv: readonly string[];
  env: Record<string, string | undefined>;
  /** The signature sources of `search_project_symbols`. The default reads only the annotations in the files. */
  projectSources?: readonly SignatureSource[];
}

/**
 * The configuration for a server started with `argv` and `env`. Only this
 * function lets `argv` and `env` decide what the server serves, so a test or an
 * embedder can build a `ServerConfig` by hand.
 */
export function serverConfig(argv: readonly string[], env: Record<string, string | undefined>): ServerConfig {
  const catalog = loadCatalog(argv, env);
  return {
    catalog,
    platform: configuredPlatform(argv, catalog),
    fetchWaitMs: Number(env.ROC_MCP_FETCH_WAIT_MS) || 60_000,
    argv,
    env,
  };
}

/**
 * `--platform=<name>` names the platform this client's projects are written
 * for. It sets the default and never restricts: an explicit `scope` argument
 * always reaches any corpus. The server sends `instructions` during
 * `initialize`, before any tool call. Thus this flag is the only way to name the
 * active platform in the instructions that clients inject at connect time. If
 * the flag occurs more than once, the last one wins.
 */
function configuredPlatform(argv: readonly string[], catalog: Catalog): ScopeName | null {
  let wanted: string | null = null;
  for (const arg of argv) {
    const m = arg.match(/^--platform=(.+)$/);
    if (m) wanted = m[1].trim();
  }
  if (wanted === null) return null;
  const platforms = catalog.platformScopes;
  if (platforms.includes(wanted)) return wanted;
  console.error(`roc-syntax: unknown platform ${wanted} from --platform=; expected one of ${platforms.join(", ")}`);
  return null;
}

/**
 * A server for `config`, with every tool and resource registered. Building one
 * reads nothing and starts nothing: it serves once a transport is connected.
 */
export function createServer(config: ServerConfig): McpServer {
  const { catalog } = config;
  const {
    scopes: SCOPES,
    scopeDefs: SCOPE_DEFS,
    packageDocs: PACKAGE_DOCS,
    platformScopes: PLATFORM_SCOPES,
    pluginScopes: PLUGIN_SCOPES,
    pluginDocNames: PLUGIN_DOC_NAMES,
    declaredPlatforms: DECLARED_PLATFORMS,
    diagnostics: LOAD_DIAGNOSTICS,
  } = catalog;
  const { topics: TOPICS } = topicsFor(catalog);

  const registry = new ScopeRegistry(ROOT, { catalog });

  /** The index of the standard library only. Tools that serve only builtins read it. */
  function getBuiltinIndex(): ScopeIndex {
    return registry.index("builtin");
  }

  /**
   * The address space that an addressed lookup resolves over. `explicit` is the
   * tool's own `scope` argument, which reaches a platform that the workspace does
   * not pin.
   */
  function getMergedIndex(explicit?: ScopeName): ScopeIndex {
    return registry.addressSpace(activePlatform(explicit));
  }

  // -----------------------------------------------------------------------------
  // Scopes
  // -----------------------------------------------------------------------------

  const CONFIGURED_PLATFORM = config.platform;

  // -----------------------------------------------------------------------------
  // Detection
  // -----------------------------------------------------------------------------

  /** Detection is a convenience. It must never block the tool call that it precedes. */
  const DETECTION_ROOTS_TIMEOUT_MS = 2000;

  // Read once, so that the server logs a missing folder only once.
  const workspaceFromFlag = workspaceFlag(config.argv);
  const detections = new DetectionCache(catalog);
  let detected: Detection | null = null;
  let detecting: Promise<Detection> | null = null;

  /**
   * Where to look for an app header, in priority order:
   * 1. `--workspace=`, set by the operator.
   * 2. `roots/list`, answered by the client.
   * 3. The environment.
   *
   * Protocol revision 2026-07-28 deprecates `roots/list`, and several clients
   * never declare the capability. Thus the environment is the usual source.
   */
  async function detectionRoot(): Promise<string> {
    if (workspaceFromFlag) return workspaceFromFlag;
    // Ask only a client that declared the capability. A client that did not will
    // never answer, and an unanswered request blocks until the protocol timeout.
    if (server.server.getClientCapabilities()?.roots) {
      try {
        const res = await server.server.listRoots({}, { timeout: DETECTION_ROOTS_TIMEOUT_MS });
        const first = res.roots?.find((r) => r.uri.startsWith("file://"));
        if (first) return fileURLToPath(first.uri);
      } catch {
        // The client declared the capability but the request failed, or the
        // protocol revision removed the request. Both cases use the environment.
      }
    }
    return workspaceRoot(config.env);
  }

  /**
   * How long one answer waits for `roc deps`. Many clients cancel a tool call
   * after about a minute, and a cancelled call returns no answer.
   * `ROC_MCP_FETCH_WAIT_MS` exists for tests.
   */
  const FETCH_WAIT_MS = config.fetchWaitMs;

  /** The releases a fetch was still downloading when an answer stopped waiting. */
  let stillFetching: string[] = [];
  let stillFetchingTold = false;
  let fetching: Promise<unknown> | null = null;

  /**
   * Runs `roc deps` to download the releases that the app header pins and that
   * the registry cannot read yet. Waits for the download up to `FETCH_WAIT_MS`.
   *
   * The wait delays one answer, once per release. A "not fetched yet" answer
   * costs the model one turn to run `roc_check` and one more turn to ask again.
   * An answer from the wrong release costs more than both. After the wait, the
   * server answers from the bundled release with a note, and the fetch
   * continues. The first call after the fetch completes reads the pinned release.
   */
  async function fetchPinnedReleases(platform: ScopeName | null): Promise<void> {
    // One download at a time. A detection that expires while one runs does not
    // start a second, and does not wait again.
    if (fetching) return;
    const wanted = registry.wantedReleases(platform);
    if (wanted.length === 0) return;
    console.error(`roc-syntax: fetching ${wanted.join(", ")} with roc deps`);
    const run = fetchReleases(wanted, { roc: rocCommand(config.argv, config.env) })
      .catch(() => wanted)
      .then((missing) => {
        registry.refresh();
        fetching = null;
        stillFetching = [];
        if (missing.length > 0) console.error(`roc-syntax: could not fetch ${missing.join(", ")}`);
      });
    fetching = run;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const waited = new Promise<"late">((resolve) => {
      timer = setTimeout(() => resolve("late"), FETCH_WAIT_MS);
    });
    const outcome = await Promise.race([run, waited]);
    clearTimeout(timer);
    if (outcome === "late") {
      stillFetching = wanted;
      stillFetchingTold = false;
      console.error(`roc-syntax: still fetching after ${FETCH_WAIT_MS / 1000}s, answering from the bundled releases`);
    }
  }

  /** Says, once per stalled fetch, that the answer is not from the release that the app pins. */
  function stillFetchingNote(): string {
    if (stillFetching.length === 0 || stillFetchingTold) return "";
    stillFetchingTold = true;
    return (
      `\n\nNote: \`roc deps\` is still downloading ${stillFetching.join(", ")}, which your app header pins. ` +
      `This answer is from the release this server bundles. Ask again in a minute for the pinned release.`
    );
  }

  /** Detect once, then serve from the cache until the TTL expires. */
  async function ensureDetection(): Promise<Detection> {
    if (detected && Date.now() - detected.detectedAt < detectionTtl(detected)) return detected;
    detecting ??= detectionRoot()
      .catch(() => process.cwd())
      .then(async (root) => {
        const found = detections.get(root, Date.now());
        // The app header decides what is in the address space. Thus the registry
        // takes the app's pins here, and does not read only the platform's header.
        registry.setWorkspacePins(found.packages);
        registry.setWorkspacePlatform(
          found.platformRef ? { scope: found.scope, url: found.platformRef } : null
        );
        // Fetch before `detected` is set. A call that arrives during the fetch
        // then waits on this promise, and does not read an address space that
        // lacks a release.
        await fetchPinnedReleases(activePlatform(undefined, found));
        detected = found;
        detecting = null;
        // The active platform decides what each override is read against. The
        // active platform is known only from this point.
        readForcedOverrides();
        // stdout is the JSON-RPC channel, so a stdio server can report its
        // conclusion only on stderr. This line shows a wrong default in the
        // client's server log, and not only in an answer.
        console.error(`roc-syntax: ${detectionLine()}`);
        return detected;
      });
    return detecting;
  }

  /**
   * The version-mismatch note, at most once per root per TTL. A pin that differs
   * from the bundled release is common: every example in the upstream 0.17.0 tag
   * pins 0.16.0.
   *
   * The note appears only when the call read the corpus that the note is about.
   */
  function mismatchOnce(active: ScopeName[]): string {
    const d = detected;
    if (!d || d.warned) return "";
    const readsPlatform = active.some((s) => SCOPE_DEFS[s].version);
    if (d.scope ? !active.includes(d.scope) : !readsPlatform) return "";
    // Both notes say that a pin in the workspace differs from what this server
    // serves, so they share the once-per-root limit.
    const served = d.scope ? registry.servedRelease(d.scope) : null;
    const notes = [
      served ? servedReleaseNote(d.scope!, served, catalog) : mismatchNote(d, catalog),
      registry.pinConflictNote(activePlatform()),
    ].filter(Boolean);
    if (notes.length === 0) return "";
    d.warned = true;
    return `\n\n${notes.join("\n\n")}`;
  }

  /** What detection has to say about this answer. */
  function detectionNote(active: ScopeName[]): string {
    return mismatchOnce(active);
  }

  let pluginProblemsShown = false;

  /**
   * The declared plugins that this server could not serve. Shown once per
   * session, on the first overview. An operator reads the stderr log, but a model
   * never does. A model that does not know about a missing plugin concludes that
   * the platform does not exist.
   */
  function pluginProblemNote(): string {
    const missing = LOAD_DIAGNOSTICS.filter((d) => d.kind === "plugin");
    if (pluginProblemsShown || missing.length === 0) return "";
    pluginProblemsShown = true;
    const rows = missing.map((d) => `- ${d.subject} (${d.source}): ${d.problem}`);
    return `\n\nDeclared plugins not served, so nothing here answers from them. Tell the user:\n${rows.join("\n")}`;
  }

  /**
   * The packages that the app pins and the active platform does not declare, and
   * the provider of each. Reported beside the platform line, because otherwise
   * an unserved namespace is invisible until a lookup fails on it.
   */
  function pinLine(): string {
    const extra = registry.spacePackages(activePlatform()).filter((r) => r.requiredBy === "app");
    if (extra.length === 0) return "";
    const parts = extra.map(
      (r) => `${r.id} ${r.required} (${r.provider ? `served by ${r.provider.from}` : "no provider"})`
    );
    return ` Also pinned: ${parts.join(", ")}.`;
  }

  /**
   * What detection concluded, in one line. Reported by
   * `list_roc_index(kind: "scopes")` only. This line on every response would
   * cost tokens on calls that do not need it. A wrong default is a problem only
   * if no tool can show it.
   */
  function detectionLine(): string {
    const d = detected;
    if (!d) return "No workspace detection has run yet.";
    if (d.scope) {
      const served = registry.servedRelease(d.scope);
      return (
        `Detected ${d.scope} ${d.detectedVersion} from ${d.sourceFile}, ` +
        `bundled ${SCOPE_DEFS[d.scope].version}` +
        `${served ? `, signatures read from ${served}` : ""}.${pinLine()}`
      );
    }
    if (d.relation === "unrecognized") {
      return `Detected an app pinning ${d.platformRef}, which this server does not bundle.${pinLine()}`;
    }
    return `No platform detected under ${d.root}. Pass \`scope\` explicitly to read one.`;
  }

  /** The pages `get_roc_syntax()` returns, with no topic and no scope. */
  const DEFAULT_OVERVIEW_PAGES = DEFAULT_SCOPES.map((s) => SCOPE_DEFS[s].overview).filter(
    (p): p is string => !!p
  );
  /** The token cost of `pages`, measured from the text so that a refresh does not have to update a number. */
  const pageCost = (pages: string[]): string => `~${(loadOverview(ROOT, pages).length / 3.5 / 1000).toFixed(1)}k tokens`;

  /**
   * The corpora that each class of tool offers. Derived from the catalog, so a
   * new platform in the registry appears in every enum without an edit here. A
   * tool declares only the scopes that have a meaning for it. A smaller enum
   * costs fewer `tools/list` tokens and makes a meaningless argument impossible.
   */
  // Here a `scope` argument selects topics, not platforms, so the set comes from
  // the merged topic table. A set made from `PLATFORM_SCOPES` would make the
  // topics of a non-platform plugin unreachable.
  const TOPIC_SCOPES = new Set(Object.values(TOPICS).map((m) => m.scope ?? "language"));
  const SYNTAX_SCOPES = SCOPES.filter((s) => TOPIC_SCOPES.has(s)) as [ScopeName, ...ScopeName[]];
  // Signatures come from any corpus with indexed items, for the same reason. The
  // signatures of a package plugin are as searchable as those of a platform.
  const SIGNATURE_SCOPES = SCOPES.filter((s) => s !== "language") as [ScopeName, ...ScopeName[]];

  /**
   * The platforms a tool description names, before anything is detected.
   *
   * The server answers `tools/list` before the first tool call, and detection
   * runs only at that call. Thus only the configuration is available here. A
   * configured platform is the answer if there is one. If not, the answer is the
   * platforms that an operator installed, because no other part of the process
   * knows more.
   */
  const ADVERTISED_PLATFORMS: ScopeName[] = CONFIGURED_PLATFORM
    ? [CONFIGURED_PLATFORM]
    : [...DECLARED_PLATFORMS];

  /**
   * The remaining characters that the loaded plugins can add to one tool's
   * `tools/list` entry, at 3.5 characters per token. Each tool has one budget,
   * and the parts of the tool spend it in the order that they are built.
   */
  class Growth {
    private left = Math.floor(PLUGIN_TOOL_GROWTH * 3.5);

    /** Whether `names` fit, at the cost of one list entry each. If they fit, spends that cost. */
    fits(names: readonly string[]): boolean {
      const cost = names.reduce((n, name) => n + name.length + 3, 0);
      if (cost > this.left) return false;
      this.left -= cost;
      return true;
    }
  }

  /** Whether a declared plugin supplies this topic, and not this server. */
  function fromPlugin(meta: TopicMeta): boolean {
    return meta.scope ? PLUGIN_SCOPES.has(meta.scope) : !!meta.package && PLUGIN_DOC_NAMES.has(meta.package);
  }

  /**
   * The topic names that `get_roc_syntax` lists in its description, and the
   * count of plugin topics that did not fit its growth budget.
   *
   * Only the platforms in reach are listed. The topics of every platform would
   * cost tokens on every request, to advertise calls that this workspace cannot
   * make. A basic-cli workspace paid 29 tokens for basic-webserver names.
   *
   * The description is the cheapest place to name an installed plugin. A model
   * asks for a listed topic by name. It must guess an omitted topic, miss it and
   * retry. That was the real cost after an install of roc-ray and a search for
   * `ray_project`. Thus the description names plugin topics while they fit, in
   * declaration order, and counts the rest.
   */
  function enumeratedTopics(growth: Growth): { names: string[]; more: number } {
    const names: string[] = [];
    let more = 0;
    for (const [name, m] of Object.entries(TOPICS)) {
      const scope = m.scope ?? "language";
      if (scope !== "language" && !ADVERTISED_PLATFORMS.includes(scope)) continue;
      if (!fromPlugin(m) || growth.fits([name])) names.push(name);
      else more++;
    }
    return { names, more };
  }

  /**
   * Every platform that this server can answer for, and what a program on each
   * platform is.
   *
   * Printed where a caller has not chosen a platform, which is the state at the
   * start of a project. The server does not choose for the caller. An installed
   * corpus shows what is available, not what somebody writes. One line per
   * platform gives the choice to the caller, who is the only party that knows
   * the answer.
   */
  function platformCatalogue(): string {
    const rows = PLATFORM_SCOPES.map((s) => `- ${s}: ${SCOPE_DEFS[s].purpose}`).join("\n");
    return (
      `No Roc code here imports a platform, so none is chosen yet. Available:\n${rows}\n` +
      `Pass the one you are writing for as \`scope\`, on this and every other tool, ` +
      `for its overview, API and topics: get_roc_syntax(scope: "${PLATFORM_SCOPES[0]}").`
    );
  }

  /**
   * The packages documented here, one clause each, with a mark on the packages
   * that this app pins. Without this list, a model that needs CSV or random
   * numbers can learn that these packages exist only by guessing.
   */
  function packageCatalogue(): string {
    if (PACKAGE_DOCS.length === 0) return "";
    const pinned = pinnedIds();
    const rows = PACKAGE_DOCS.map(
      (d) => `${d.name} (${d.purpose}${pinned.has(d.id) ? ", pinned by this app" : ""})`
    );
    return (
      `\nPackages documented here: ${rows.join("; ")}. ` +
      `get_roc_syntax(topic: "${PACKAGE_DOCS[0].name}") for one's page.`
    );
  }

  /** The repo paths of the packages in the address space: the platform's and the app's own. */
  function pinnedIds(): Set<string> {
    return new Set(registry.spacePackages(activePlatform()).map((r) => r.id));
  }

  /**
   * How a reply tells the model to read an example, because not every client
   * reads resources. The text quotes a real address, not a template, so the
   * format is unambiguous.
   */
  const readExample = (id: string) => `Read one with get_roc_syntax(topic: "${id}").`;

  /** The documented package a query names, by its plugin name or its repo path. */
  function packageNamed(query: string): PackageDoc | null {
    const q = query.trim().toLowerCase();
    return PACKAGE_DOCS.find((d) => d.name === q || d.id.toLowerCase() === q) ?? null;
  }

  /**
   * What `get_roc_syntax(topic: <package name>)` returns: the package's page, the
   * programs that teach it, and whether this app pins it.
   */
  function packagePage(doc: PackageDoc): string {
    const page = doc.overview
      ? fs.readFileSync(path.resolve(ROOT, doc.overview), "utf-8").trimEnd()
      : `# ${doc.name} ${doc.version}\n\n${doc.description}`;
    const topics = (doc.topics ?? []).map((t) => t.name);
    const examples = registry.packageExamples(doc).map((ex) => `${doc.name}/${ex.name}`);
    // The page does not state the release, so a repin does not change the page.
    // This line states the release.
    const more = [
      doc.overview ? `This page documents ${doc.name} ${doc.version}.` : "",
      topics.length > 0 ? `Topics: ${topics.join(", ")}.` : "",
      examples.length > 0 ? `Examples: ${examples.join(", ")}. ${readExample(examples[0])}` : "",
      pinnedIds().has(doc.id)
        ? "This app pins it, so its modules are searched with the builtins."
        : `This app does not pin it. ${howToPin(doc)}`,
    ].filter(Boolean);
    return `${page}\n\n${more.join("\n")}`;
  }

  /** How an app header pins a package, for a caller whose app does not. */
  function howToPin(doc: PackageDoc): string {
    return `Add it to the app header, then import its modules through the alias:\n    <alias>: "${doc.release}",`;
  }

  /**
   * When to name a platform in `scope`. Every tool that takes `scope` carries
   * this text.
   *
   * The working set holds a platform only when one is pinned or installed. Thus
   * the server answers a question about an unpinned platform from the language
   * and the builtins only. That answer reads as "no such thing", not as "not
   * here". One sentence on the parameter costs less than the miss and the retry
   * that it prevents.
   */
  function scopeHint(platforms: readonly ScopeName[]): string {
    return (
      `Name a platform (${platforms.join(", ")}) for what a host provides, such as I/O, ` +
      `graphics or networking, rather than the language or the builtins.`
    );
  }

  /**
   * A tool's optional `scope` argument, over `values`.
   *
   * The plugin scopes go in the enum, and in the hint if the tool has one, while
   * they fit the tool's growth budget. If they do not fit, the argument is a
   * string checked against the same values. The text then names the bundled
   * platforms and points to the listing for the rest. That text costs the same
   * for any number of plugins.
   */
  function scopeArg(
    values: readonly ScopeName[],
    describe: string,
    opts: { hint?: boolean; growth?: Growth } = {}
  ) {
    const growth = opts.growth ?? new Growth();
    const added = values.filter((s) => PLUGIN_SCOPES.has(s));
    const hinted = opts.hint ? PLATFORM_SCOPES.filter((s) => PLUGIN_SCOPES.has(s)) : [];
    if (growth.fits([...added, ...hinted])) {
      const text = opts.hint ? `${describe} ${scopeHint(PLATFORM_SCOPES)}` : describe;
      return z.enum(values as [ScopeName, ...ScopeName[]]).optional().describe(text);
    }
    const bundled = PLATFORM_SCOPES.filter((s) => !PLUGIN_SCOPES.has(s));
    const text = `${opts.hint ? `${describe} ${scopeHint(bundled)}` : describe} list_roc_index(kind='scopes') names every value.`;
    return z
      .string()
      .refine((v) => values.includes(v as ScopeName), { message: `scope must be one of: ${values.join(", ")}` })
      .optional()
      .describe(text);
  }

  /**
   * The one platform in play, or null when there is none.
   *
   * An app header names exactly one platform, so the server tracks one platform.
   * The documented resolution order is:
   * 1. an explicit argument,
   * 2. the configured default,
   * 3. the result of detection.
   *
   * Only one platform is active at a time, so the names that platforms share do
   * not collide.
   */
  function activePlatform(explicit?: ScopeName, from: Detection | null = detected): ScopeName | null {
    for (const candidate of [explicit, CONFIGURED_PLATFORM, from?.scope]) {
      if (candidate && SCOPE_DEFS[candidate].version) return candidate;
    }
    return null;
  }

  /**
   * Scopes read when a call passes no `scope` argument: every corpus that is not
   * a platform, plus the one platform in play.
   *
   * If nobody chose a platform, the set holds no platform. An installed corpus
   * shows what is available, never what this program is. That difference is
   * largest in an empty directory. There, the server lists the platforms that
   * exist and lets the caller choose. `platformCatalogue` gives that list, at one
   * line per platform.
   */
  function workingSet(): ScopeName[] {
    const set = SCOPES.filter((s) => !SCOPE_DEFS[s].version && DEFAULT_SCOPES.includes(s));
    const platform = activePlatform();
    if (platform) set.push(platform);
    return set;
  }

  /**
   * One scope as this call reads it: the builtins carry the packages the app
   * pins. `explicit` is the call's own `scope`, which may name a platform.
   */
  function scopeIndex(scope: ScopeName, explicit?: ScopeName): ScopeIndex {
    return registry.scopeIndex(scope, activePlatform(explicit));
  }

  function appFacing(scope: ScopeName, explicit?: ScopeName): ScopedItem[] {
    return registry.appFacingIn(scope, activePlatform(explicit));
  }

  /**
   * Which corpora one call reads. Without `scope`, the call reads the working
   * set. With `scope`, the call reads only that scope, so the model always knows
   * that it narrowed the search.
   */
  function resolveScopes(
    scope: ScopeName | undefined,
    allowed: readonly ScopeName[]
  ): ScopeName[] {
    if (scope) return [scope];
    return workingSet().filter((s) => allowed.includes(s));
  }

  /**
   * How many items in one scope match a `search_symbols` name query exactly. The
   * rules are the same as in that tool, without the list of partial names. A hint must count
   * the names that the caller asked for, not the names that they possibly meant.
   */
  function nameMatchCount(idx: ScopeIndex, query: string): number {
    if (!query.includes(".")) return (idx.byName.get(query) ?? []).length;
    if (idx.byFullName.has(query)) return 1;
    return idx.items.filter((it) => it.fullName.endsWith("." + query)).length;
  }

  /**
   * `elsewhere`, with two facts that each caller would otherwise repeat: the
   * platform in the address space, and the scopes that are platforms.
   */
  function elsewhere(
    from: readonly ScopeName[],
    shown: readonly ScopeName[],
    reach: Reach,
    count: (scope: ScopeName) => number
  ): Candidate[] {
    return elsewhereIn({
      from,
      shown,
      reach,
      platform: activePlatform(),
      isPlatform: (s) => Boolean(SCOPE_DEFS[s].version),
      count,
    });
  }

  /**
   * Where a name that the caller asked for is defined, if the name is outside
   * the address space of this workspace. There are two cases:
   * - A platform is pinned, and the name belongs to a different platform. The
   *   API of that platform will not compile here.
   * - Nothing is pinned, and the address space holds no platform.
   *
   * Both cases end at a `scope` value, so the caller can act on the hint or
   * ignore it.
   *
   * The candidates are a list, not a sentence, because a sentence does not
   * scale. Two platforms join with "and", a third needs commas, and each one
   * makes a message longer that the caller may not want. A list costs one line
   * per platform and reads the same at any count.
   */
  function outOfScopeNote(subject: string, found: Candidate[], active: ScopeName | null): string | null {
    if (found.length === 0) return null;
    const head = active
      ? `${subject} is not in the builtins or ${active} ${SCOPE_DEFS[active].version}, ` +
        `the platform this app's header imports, so it will not compile here.`
      : `${subject} is not in the builtins, and no platform is in scope.`;
    const list = found
      .map((f) => `${f.scope} ${SCOPE_DEFS[f.scope].version}: ${f.count}`)
      .join("\n");
    const retry =
      found.length === 1
        ? `Try again with \`scope: ${found[0].scope}\` to see it.`
        : "Try again with `scope:` set to one of these to see it.";
    return `${head}\nFound in:\n${list}\n${retry}`;
  }

  /**
   * A documented package that has what the caller asked for, when the app does
   * not pin it. Appended to a miss with the matches, because the fix is a line
   * in the app header. No `scope` retry reaches a package, because an unpinned
   * package does not compile.
   */
  function unpinnedPackageNote(subject: string, matches: (idx: ScopeIndex) => ScopedItem[]): string {
    const pinned = pinnedIds();
    const lines = PACKAGE_DOCS.flatMap((doc) => {
      if (pinned.has(doc.id)) return [];
      const found = matches(registry.packageIndex(doc)).filter((it) => it.tier === "public");
      if (found.length === 0) return [];
      // Only three, because a miss is the wrong place to list a whole module.
      const shown = found
        .slice(0, 3)
        .map((it) => `    ${it.modulePath ? `${it.modulePath}.` : ""}${declLine(it, it.signature.split("\n")[0])}`);
      const more = found.length > 3 ? `\n    (${found.length - 3} more)` : "";
      return [
        `${subject} is in ${doc.name} ${doc.version}, a package this app does not pin:\n` +
          `${shown.join("\n")}${more}\n${howToPin(doc)}\n` +
          `get_roc_syntax(topic: "${doc.name}") says what the package is for.`,
      ];
    });
    return lines.length > 0 ? `\n\n${lines.join("\n\n")}` : "";
  }

  /** The items that match a `search_symbols` name query exactly, by the rules that `nameMatchCount` counts. */
  function nameMatches(idx: ScopeIndex, query: string): ScopedItem[] {
    if (!query.includes(".")) return idx.byName.get(query) ?? [];
    const exact = idx.byFullName.get(query);
    if (exact) return [exact];
    return idx.items.filter((it) => it.fullName.endsWith("." + query));
  }

  /**
   * A namespace the active platform pins that no provider serves, appended to a
   * miss. The registry finds these namespaces once at startup. This function
   * only prints the result.
   */
  function unservedNote(active: ScopeName | null): string {
    const note = registry.packageNote(active);
    return note ? `\n\n${note}` : "";
  }

  /**
   * The line that makes a retry possible. A report of empty results only is not
   * sufficient. The dangerous case is a plausible hit in the wrong corpus, after
   * which the model stops and does not look again. The line costs about 12
   * tokens.
   */
  function scopeFooter(active: ScopeName[], shown: number, candidates: Candidate[]): string {
    // Only two, because a third candidate gives the caller nothing more to act on.
    const others = [...candidates].sort((a, b) => b.count - a.count).slice(0, 2);
    const head = `\n\n${shown} ${shown === 1 ? "match" : "matches"} in scope=${active.join("+")}.`;
    if (others.length === 0) return head;
    const list = others.map((o, i) => (i === 0 ? `${o.scope}: ${o.count} other` : `${o.scope}: ${o.count}`)).join(", ");
    return `${head}\n(${list}. Retry with scope= to see them.)`;
  }

  /**
   * No `scope` value reaches the host tier, so this footer names an addressed
   * call. See "The host tier" in docs/plans/basic-webserver-scope.md.
   */
  function hostTierFooter(hidden: number): string {
    if (hidden === 0) return "";
    return (
      `\n\n${hidden} host-boundary items hidden. Address them directly, for example ` +
      `get_roc_module("Host") or search_symbols("Server.Config.to_host").`
    );
  }

  /**
   * Everything appended after a body, composed and ordered in one place.
   *
   * If each site adds its notes by hand, a note reaches only the sites that
   * somebody remembered. This function derives each note from the answer, so no
   * site can forget one. A new note reaches every tool that calls this function.
   *
   * The detection note is opt-in. It is the only note whose correct placement
   * depends on the tool. `list_roc_index(kind: "scopes")` already reports
   * detection in full, and would print it twice.
   */
  function trailingNotes(opts: {
    /** The scopes that this answer read. */
    read: ScopeName[];
    /** The count that the body shows, and the other scopes with matches. Omitted if there is no listing. */
    found?: { shown: number; others: Candidate[] };
    hostTier?: number;
    detection?: boolean;
    /** For an answer that is a miss without being a listing, such as a lookup. */
    empty?: boolean;
    /**
     * Collects the notes about the session in place of the return value. A reply
     * to several queries prints each of these notes once, after the last query.
     */
    sessionNotes?: Set<string>;
  }): string {
    // An unserved namespace matters only when the answer is empty. It is the only
    // reason why a miss may not mean that the name does not exist. The flag comes
    // from the answer, not from an argument, so no site can forget it.
    const empty = opts.found ? opts.found.shown === 0 : (opts.empty ?? false);
    const session = (opts.detection ? detectionNote(opts.read) : "") + (empty ? unservedNote(activePlatform()) : "");
    if (opts.sessionNotes && session) opts.sessionNotes.add(session);
    return (
      (opts.found ? scopeFooter(opts.read, opts.found.shown, opts.found.others) : "") +
      hostTierFooter(opts.hostTier ?? 0) +
      (opts.sessionNotes ? "" : session)
    );
  }

  /**
   * For each forced namespace whose served release differs from the release that
   * the active platform requires, the required release. Empty in a default
   * install, because nobody overrode a namespace.
   *
   * Recomputed when detection completes, because the active platform decides
   * which requirement the override is read against.
   */
  let forcedOverrides = new Map<string, string>();

  function readForcedOverrides(): void {
    forcedOverrides = new Map(
      registry
        .spacePackages(activePlatform())
        .filter((r) => r.forced && r.provider && r.provider.version !== r.required)
        .map((r) => [r.ns, r.required] as const)
    );
  }

  /**
   * Names `origin`, because a scope can draw on more than one package. A forced
   * namespace also names the required release that the override replaced.
   *
   * Per item, not in a footer: an override changes what every signature in that
   * namespace says. A caller who reads one signature and stops must also get
   * this information. Without the suffix, the served release reads as the truth.
   */
  function originSuffix(item: ScopedItem): string {
    if (item.origin === "Builtin.roc") return "";
    const over = forcedOverrides.get(item.ns);
    return over ? ` (${item.origin}, forced over ${over})` : ` (${item.origin})`;
  }

  /**
   * One line of Roc as the source declares it. A type must keep its own operator:
   * `Bool := [False, True]` is a nominal type, `Bool : [False, True]` would be an
   * alias, and a model that copies the wrong one writes code that will not compile.
   */
  function declLine(item: Decl, sig: string): string {
    if (item.kind === "type") return `${item.head} ${item.decl} ${sig}`;
    // An unannotated value has no type to print. A lambda head after `:` would
    // look like a type, so the line keeps the `=` from the source.
    return item.unannotated ? `${item.name} = ${sig}` : `${item.name} : ${sig}`;
  }

  function formatBuiltinItem(item: BuiltinItem): string {
    const header = `## ${item.fullName}`;
    const sigBlock = "```roc\n" + declLine(item, item.signature) + "\n```";
    const docs = item.docs ? `\n${item.docs}` : "";
    return `${header}\n${sigBlock}${docs}`;
  }

  /** As `formatBuiltinItem`, plus the package of the item, which a scope with many packages needs. */
  function formatScopedItem(item: ScopedItem): string {
    const header = `## ${item.fullName}${originSuffix(item)}`;
    const sigBlock = "```roc\n" + declLine(item, item.signature) + "\n```";
    const docs = item.docs ? `\n${item.docs}` : "";
    return `${header}\n${sigBlock}${docs}`;
  }




  // -----------------------------------------------------------------------------
  // MCP server
  // -----------------------------------------------------------------------------

  /**
   * Every tool here reads bundled reference files or runs `roc check` / `roc fmt`
   * on a scratch copy, so no tool can change the user's files. Clients use
   * `readOnlyHint` to skip the approval prompt. `destructiveHint` and
   * `idempotentHint` have a meaning only when `readOnlyHint` is false, so the
   * server omits them to keep the tool list small.
   */
  const READ_ONLY = { readOnlyHint: true, openWorldHint: false } as const;
  // Also read-only, but may download. The first call in a workspace runs `roc deps`
  // to fetch the releases that its app header pins, and `roc check` fetches packages.
  const READ_ONLY_FETCHES = { readOnlyHint: true, openWorldHint: true } as const;

  const server = new McpServer(
    {
      name: "roc-syntax",
      version: VERSION,
      description: "Roc syntax, builtins, and language reference for the Zig-based compiler.",
      websiteUrl: "https://github.com/Karakatiza666/roc-syntax-mcp",
    },
    {
      // Clients may inject this text into the model's context at connect time.
      // Thus it stays short and points to the tools. It must name the trigger,
      // because otherwise a model that believes it knows Roc will never call a tool.
      instructions:
        "Roc language reference for the Zig-based compiler in roc-lang/roc (2026 nightlies). " +
        "Before reading, writing, or reasoning about any Roc code, call `get_roc_syntax` once with no arguments. " +
        `It returns the whole language and its builtins as two compact pages (${pageCost(DEFAULT_OVERVIEW_PAGES)}), ` +
        "usually enough to finish the task without another call. " +
        "Do this even when you believe you know Roc: the syntax changed with this compiler, so " +
        "recalled Roc is unreliable (`Try` replaced `Result`, `value.method()` static dispatch is " +
        "the normal style, and every builtin lives in one `Builtin.roc`). " +
        "For details, use `get_roc_syntax(topic:)` for a worked example and the rules of one construct, " +
        "`get_roc_module` for one module, and `roc_check` / " +
        "`roc_fmt` to verify what you wrote. " +
        // Measured in docs/evals/agentic.md: on a local platform, agents searched the
        // source with Grep, often with one regex for several questions.
        "To find a Roc function or type, call `search_symbols`, and `search_project_symbols` for " +
        "the `.roc` files of a project, before Grep. They return the whole signature with its docs, " +
        "and one call takes up to 8 queries. Use Grep only when both find nothing. " +
        "Name the platform in `scope` when the workspace has no app header yet: a project you are " +
        "starting has no app header yet, so nothing but you knows which platform its code is for. " +
        "Never request `Builtin.roc` whole. It is hundreds of thousands of tokens.",
    }
  );

  // The answer of any tool can wait on a fetch. Thus this wrapper adds the
  // stalled-fetch note in one place, not in the footer of each tool.
  {
    const register = server.registerTool.bind(server);
    server.registerTool = ((name: string, config: unknown, cb: (...a: unknown[]) => Promise<any>) =>
      register(name, config as never, (async (...a: unknown[]) => {
        const result = await cb(...a);
        const note = stillFetchingNote();
        const last = result?.content?.at(-1);
        if (note && last?.type === "text") last.text += note;
        return result;
      }) as never)) as typeof server.registerTool;
  }

  /** What `get_roc_syntax` returns without a topic: the overview pages, or the page of `scope`. */
  async function overviewPage(scope?: ScopeName): Promise<{ content: { type: "text"; text: string }[] }> {
    await ensureDetection();
    // This is the only answer whose default is not the working set. Detection adds
    // a platform to the default of every other tool. Here, the platform page in
    // the default would print the language and builtins again on a call that
    // wanted only the platform.
    const wanted: ScopeName[] = scope ? [scope as ScopeName] : [...DEFAULT_SCOPES];
    const pages = scope
      ? [SCOPE_DEFS[scope as ScopeName].overview].filter((p): p is string => !!p)
      : DEFAULT_OVERVIEW_PAGES;
    let overview = loadOverview(ROOT, pages);
    // The page does not state the release, so a repin does not change the page.
    // This line states the release.
    const version = scope ? SCOPE_DEFS[scope as ScopeName].version : undefined;
    if (version && pages.length > 0) overview += `\n\nThis page documents ${scope} ${version}.`;

    // Never add a detected platform to the default answer. The `scope`
    // parameter exists to prevent a copy of the language and builtins pages on
    // every platform call. Thus the answer points to `scope`.
    if (!scope) {
      const platform = activePlatform();
      if (platform) {
        const from =
          detected?.scope === platform
            ? ` (from ${detected.sourceFile}, pins ${detected.detectedVersion})`
            : "";
        const page = SCOPE_DEFS[platform].overview;
        overview +=
          `\n\nPlatform detected: ${platform} ${SCOPE_DEFS[platform].version}${from}.` +
          (page ? `\nget_roc_syntax(scope: "${platform}") adds ${pageCost([page])}.` : "");
      } else if (detected?.relation === "unrecognized") {
        // This is the only case where an answer without a note misleads. The app
        // imports a platform, and nothing that this server bundles describes it.
        overview +=
          `\n\nThe app header here imports a platform this server does not have ` +
          `(${detected.platformRef}). Search its files with search_project_symbols.`;
      } else {
        // This is the first call that a model makes, at the start of a project.
        // Without the catalogue, a model with no platform in mind has none after
        // the call. A model with a platform in mind cannot tell if this server
        // knows that platform.
        overview += `\n\n${platformCatalogue()}`;
      }
      overview += packageCatalogue();
    }
    overview += detectionNote(wanted) + pluginProblemNote();

    return { content: [{ type: "text", text: overview }] };
  }

  /** The call that reads a topic. A topic name resolves in any scope, so the call needs no `scope`. */
  const topicCall = (name: string) => `get_roc_syntax(topic: "${name}")`;

  /**
   * Names up to 3 other candidates after a topic that the words of a question
   * found. A sure match can be the wrong topic, and this line costs fewer
   * tokens than a second call.
   */
  function alsoLine(match: TopicMatch): string {
    if (match.by !== "words" || match.ranked.length === 0) return "";
    return `\n\nAlso: ${match.ranked.slice(0, 3).map((r) => topicCall(r.name)).join(", ")}.`;
  }

  /**
   * Builds the reply when no topic is a sure match. The reply lists the closest
   * topics, worked programs and symbols, each as the call that reads it. A list
   * costs a few lines, and a wrong topic costs a whole program.
   */
  function pointerReply(query: string, scope: ScopeName | undefined, wanted: ScopeName[], ranked: TopicRank[]): string {
    const q = question(query);
    // The three kinds share one scale. A word in a topic name or keyword counts
    // 2, the same as a word in a symbol name. So for "sort list", `List.sort`
    // scores 4, and the topics that cover only "list" score 2 and are removed.
    const topics = best(ranked.map((r) => ({ r, score: r.covered * 2 })), 4);
    const programs = best(
      wanted.flatMap((s) => filedExamples(s)).map(({ id, ex }) => ({ id, ex, score: symbolScore(q, { name: ex.name, modulePath: "", docs: ex.title }) })),
      3
    );
    // Here a symbol needs a content word in its name or module path. One word of
    // a long question that only the docs contain is noise.
    const symbols = mentioned(q, scope, 4).filter((m) => nameCoverage(q, m.item) > 0);
    const sections = best([
      { score: topics[0]?.score ?? 0, text: `Topics:\n${topics.map(({ r }) => `- ${topicCall(r.name)}: ${TOPICS[r.name].description}`).join("\n")}` },
      { score: programs[0]?.score ?? 0, text: `Worked programs:\n${programs.map(({ id, ex }) => `- ${topicCall(id)}: ${ex.title}`).join("\n")}` },
      {
        score: symbols[0]?.score ?? 0,
        text:
          "Symbols (`search_symbols` gives the docs):\n" +
          symbols.map(({ item }) => `- \`${item.fullName}\`${originSuffix(item)}: \`${declLine(item, item.signature.split("\n")[0])}\``).join("\n"),
      },
    ], 3).map((sec) => sec.text);
    const others = elsewhere(SYNTAX_SCOPES, wanted, "pinned", (s) => {
      const m = matchTopic(query, [s], TOPICS);
      return (m.topic ? 1 : 0) + m.ranked.length;
    });
    const head = sections.length
      ? `No topic is a sure match for "${query}" in scope=${wanted.join("+")}. The closest, best first:`
      : `Nothing matched "${query}" in scope=${wanted.join("+")}. ` +
        (Object.values(TOPICS).some((m) => wanted.includes(m.scope ?? "language"))
          ? "list_roc_index(kind='topics') describes each topic."
          : "This corpus has no topics.");
    return [head, ...sections].join("\n\n") + trailingNotes({ read: wanted, found: { shown: topics.length, others } });
  }

  /**
   * Drops the topic that the words of a question found when the name or module
   * path of a symbol covers more of the question. Such a question asks for a
   * function. For "sort list", `List.sort` covers 2 words and `list_patterns` 1.
   */
  function askedForSymbol(match: TopicMatch, query: string, scope: ScopeName | undefined): TopicMatch {
    if (match.by !== "words" || !match.topic) return match;
    const q = question(query);
    const symbols = resolveScopes(scope, SIGNATURE_SCOPES).flatMap((s) => appFacing(s, scope));
    if (!symbols.some((item) => nameCoverage(q, item) > match.covered!)) return match;
    return { topic: null, ranked: [{ name: match.topic, covered: match.covered! }, ...match.ranked] };
  }

  /** The app-facing symbols of `scope`, else of the working set, that best answer a question in words. */
  function mentioned(q: Question, scope: ScopeName | undefined, max: number): { item: ScopedItem; score: number }[] {
    return best(
      resolveScopes(scope, SIGNATURE_SCOPES).flatMap((s) => appFacing(s, scope)).map((item) => ({ item, score: symbolScore(q, item) })),
      max
    );
  }

  /**
   * Lists the symbols whose module or docs contain the words of a query that no
   * name matched. "urlencoded" is in no name, and the docs of
   * `parse_form_url_encoded` contain "application/x-www-form-urlencoded".
   */
  function mentionList(query: string, scope: ScopeName | undefined, max: number): string {
    const hits = mentioned(question(query), scope, max);
    if (hits.length === 0) return "";
    const n = hits.length;
    return `\n\n${n} ${n === 1 ? "symbol has" : "symbols have"} these words in the module or the docs:\n\n` + hits.map(({ item }) => compactItem(item)).join("\n\n");
  }

  /**
   * The entries with the top scores above 0, at most `max`. An entry more than
   * 1 below the top score is removed, because one-word matches under a match of
   * the whole question are noise.
   */
  function best<T extends { score: number }>(entries: T[], max: number): T[] {
    const top = Math.max(0, ...entries.map((e) => e.score));
    return entries
      .filter((e) => e.score > 0 && e.score >= top - 1)
      .sort((a, b) => b.score - a.score)
      .slice(0, max);
  }

  /** Answers `get_roc_syntax(topic:)` with a topic, a package page, an example or pointers. docs/design/syntax-lookup.md has every rule. */
  async function syntaxTopic(
    query: string,
    scope?: ScopeName
  ): Promise<{ content: { type: "text"; text: string }[] }> {
    // `overview` is the name of the answer without a topic, and the name of its resource.
    if (query.trim().toLowerCase() === "overview") return overviewPage(scope);
    await ensureDetection();
    // A package name addresses the package page for any scope, because no scope
    // holds a package.
    const doc = packageNamed(query);
    if (doc) return { content: [{ type: "text" as const, text: packagePage(doc) }] };
    // An example address, like a package name, resolves for any scope.
    const example = exampleNamed(query);
    if (example) return { content: [{ type: "text" as const, text: example }] };
    const wanted = resolveScopes(scope, SYNTAX_SCOPES);
    // A topic name is an address, and a caller who writes one has already chosen.
    // The name resolves outside the working set for the same reason as in
    // `search_symbols`. `tools/list` names the topics of an installed platform,
    // so a refusal here would advertise a call and then answer "no topic matched".
    // The address comes before the words of the query, because the words of a
    // topic name can match another topic in the working set. "cli" in
    // `cli_files` is a word of `weaver_cli`.
    const addressed = scope ? null : (TOPICS[query.trim().toLowerCase()] ? query.trim().toLowerCase() : null);
    const match: TopicMatch = addressed
      ? { topic: addressed, by: "name", ranked: [] }
      : askedForSymbol(matchTopic(query, wanted, TOPICS), query, scope);
    const matched = match.topic;
    if (!matched) return { content: [{ type: "text" as const, text: pointerReply(query, scope, wanted, match.ranked) }] };

    const meta = TOPICS[matched];
    const from = meta.scope ?? "language";
    const examples = loadTopic(matched, TOPICS) ?? "(example file missing)";
    // An answer from outside the working set gets one line. The caller asked for
    // this name, and no other part of the reply says that the app does not import
    // the corpus of the topic.
    const pkg = meta.package ? PACKAGE_DOCS.find((d) => d.name === meta.package) : undefined;
    const aside = pkg
      ? pinnedIds().has(pkg.id)
        ? ""
        : `\n\nFrom ${pkg.name} ${pkg.version}, a package this app does not pin. ${howToPin(pkg)}`
      : wanted.includes(from)
        ? ""
        : `\n\nA ${from} topic, which this workspace has not chosen. ` +
          `Pass \`scope: "${from}"\` to search the rest of that corpus.`;
    return {
      content: [
        {
          type: "text" as const,
          text:
            `## ${matched}\n\n${meta.description}\n\n\`\`\`roc\n${examples}\n\`\`\`${aside}${alsoLine(match)}` +
            trailingNotes({ read: wanted.includes(from) ? wanted : [from], detection: true }),
        },
      ],
    };
  }

  // Topics spend the growth budget first. A model asks for a listed topic by
  // name, which is worth more than an enum value that the listing also gives.
  const SYNTAX_GROWTH = new Growth();
  const SYNTAX_TOPICS = enumeratedTopics(SYNTAX_GROWTH);

  // One tool answers the overview and the topics, because a model looks for
  // the overview under a tool name with "syntax" in it.
  server.registerTool(
    "get_roc_syntax",
    {
      annotations: READ_ONLY_FETCHES,
      title: "Roc Overview and Syntax Topics (start here)",
      // With no platform in reach, a keyword or an explicit `scope` finds the
      // topics of a platform. The pointer costs fewer tokens than the names.
      description:
        "Call with no arguments before reading, writing, or reasoning about any Roc code. It returns the whole language and its builtins: syntax, types, operator desugaring, modules, and where LLMs get Roc wrong. Call it even when you believe you know Roc: the Zig-based compiler changed the syntax. " +
        `Pass \`topic\` for one construct: a worked example, its rules, and the errors it gives. Topics: ${SYNTAX_TOPICS.names.join(", ")}.` +
        (SYNTAX_TOPICS.more > 0
          ? ` ${SYNTAX_TOPICS.more} more topics: list_roc_index(kind='topics').`
          : ADVERTISED_PLATFORMS.length > 0
            ? ""
            : ` A platform's own topics are listed by list_roc_index(kind='topics').`),
      inputSchema: z.object({
        topic: z
          .string()
          .optional()
          .describe("Omit for the overview. A topic name (e.g. 'pattern_matching'), a package name for its page (e.g. 'roc-parser'), an example (e.g. 'basic-cli/hello'), or a question, which gets pointers when no topic is a sure match."),
        scope: scopeArg(
          SCOPES,
          "One corpus only. Without `topic`, returns the page of that corpus. Omit for the language and builtins, or name a platform for its API. With `topic`, searches only the topics of that corpus.",
          { hint: true, growth: SYNTAX_GROWTH }
        ),
      }),
    },
    async ({ topic, scope }) =>
      topic?.trim() ? syntaxTopic(topic, scope as ScopeName | undefined) : overviewPage(scope as ScopeName | undefined)
  );

  server.registerTool(
    "list_roc_index",
    {
      annotations: READ_ONLY_FETCHES,
      title: "List What the Other Roc Tools Accept",
      description:
        "What the other tools accept. `scopes`: the corpora `scope` takes, and documented packages. `topics`: the topics `get_roc_syntax` takes. `modules`: the module paths `get_roc_module` takes. `examples`: worked programs.",
      inputSchema: z.object({
        kind: z
          .enum(["scopes", "topics", "modules", "examples"])
          .describe("Which index to list."),
        scope: scopeArg(
            SCOPES,
            "For kind='topics', 'modules', 'examples': one corpus only. Omit for the working set."
          ),
      }),
    },
    async ({ kind, scope }) => {
      await ensureDetection();
      const wanted = resolveScopes(scope as ScopeName | undefined, SCOPES);

      if (kind === "scopes") {
        const items = SCOPES.map((s) => {
          const def = SCOPE_DEFS[s];
          const idx = registry.index(s);
          const app = idx.items.filter((i) => i.tier === "public").length;
          const parts = [def.description];
          if (def.version) parts.push(`Pinned to ${def.version}.`);
          if (app > 0) parts.push(`${app} indexed items.`);
          // This line gives attribution and restricts nothing. The only harm that a
          // corpus can do is wrong information about Roc, and no check script finds
          // a page that is wrong. If nobody is named, the line says so.
          parts.push(def.maintainer ? `Maintained by ${def.maintainer}.` : "Maintainer not named.");
          const stale = staleness(catalog, s);
          if (stale) parts.push(stale);
          return { name: s, detail: parts.join(" ") };
        });
        const active = workingSet().join(" + ");
        const pinned = pinnedIds();
        // Listed for attribution, not as scopes. After the app pins a package, the
        // server reads it with the builtins, and its page is addressed by name.
        const packages = PACKAGE_DOCS.map((d) => {
          const parts = [d.description, `Release ${d.version}.`];
          parts.push(pinned.has(d.id) ? "Pinned by this app." : "Not pinned by this app.");
          parts.push(d.maintainer ? `Maintained by ${d.maintainer}.` : "Maintainer not named.");
          const stale = staleness(catalog, d.name);
          if (stale) parts.push(stale);
          return `- **${d.name}**: ${parts.join(" ")}`;
        });
        const text = [
          "# Scopes",
          "",
          ...items.map((s) => `- **${s.name}**: ${s.detail}`),
          "",
          `Omitting \`scope\` reads ${active}. Passing one reads that corpus alone.`,
          ...(packages.length > 0
            ? [
                "",
                "# Documented packages",
                "",
                ...packages,
                "",
                "A pinned package is searched with the builtins. get_roc_syntax(topic: <name>) reads a package's page.",
              ]
            : []),
          detectionLine(),
          // Only this response carries the load diagnostics. On every answer, they
          // would cost tokens on calls that did not ask about plugins.
          ...LOAD_DIAGNOSTICS.map(
            (d) => `\n${d.kind === "force" ? "Forced" : "Plugin"} ${d.subject} (${d.source}): ${d.problem}`
          ),
        ].join("\n");
        return {
          content: [{ type: "text", text }],
        };
      }

      if (kind === "topics") {
        const items = Object.entries(TOPICS)
          .filter(([, meta]) => wanted.includes(meta.scope ?? "language"))
          .map(([name, meta]) => ({ name, detail: meta.description }));
        const text = items.map((t) => `- **${t.name}**: ${t.detail}`).join("\n");
        const others = elsewhere(SCOPES, wanted, "pinned", (s) =>
          Object.values(TOPICS).filter((m) => (m.scope ?? "language") === s).length
        );
        const notes = trailingNotes({ read: wanted, found: { shown: items.length, others } });
        return {
          content: [{ type: "text", text: `# Roc Syntax Topics\n\n${text}${notes}` }],
        };
      }

      if (kind === "modules") {
        // A module is a path that has methods. The list holds a module only if
        // some of its methods are app-facing. A host-tier name here would look like
        // an invitation to call the ABI, and an app author must never call it.
        const visible = new Set(
          wanted.flatMap((s) =>
            scopeIndex(s, scope as ScopeName | undefined)
              .items.filter((i) => i.kind === "value" && i.tier === "public" && i.modulePath)
              .map((i) => i.modulePath)
          )
        );
        const items = [...visible].sort().map((name) => ({ name }));
        const text = items.map((m) => `- ${m.name}`).join("\n");
        const others = elsewhere(SCOPES, wanted, "pinned", (s) => registry.index(s).modulePaths.size);
        const notes = trailingNotes({ read: wanted, found: { shown: items.length, others } });
        return {
          content: [{ type: "text", text: `# Modules\n\n${text}${notes}` }],
        };
      }

      // The last kind, `examples`. Each entry is a complete program, so the listing
      // names the programs and does not quote them. get_roc_syntax(topic:) reads
      // one by its address.
      const items = wanted.flatMap((sc) => filedExamples(sc).map(({ id, ex }) => ({ name: id, detail: ex.title })));
      const others = elsewhere(SCOPES, wanted, "pinned", (sc) => filedExamples(sc).length);
      const body =
        items.length === 0
          ? "No scope in the working set bundles worked programs."
          : `${readExample(items[0].name)}\n\n${items.map((e) => `- ${e.name}\n  ${e.detail}`).join("\n")}`;
      const notes = trailingNotes({ read: wanted, found: { shown: items.length, others } });
      return {
        content: [{ type: "text", text: `# Examples\n\n${body}${notes}` }],
      };
    }
  );


  // -----------------------------------------------------------------------------
  // Symbol search: by name, by type, or both. See docs/design/symbol-search.md.
  // -----------------------------------------------------------------------------

  /** One entry of a list. The signature is complete, because a `where` clause on a later line changes what the item accepts. */
  function compactEntry(item: Decl, head: string): string {
    const decl = declLine(item, item.signature.replace(/\t/g, "  "));
    return `${head}\n\`\`\`roc\n${decl}\n\`\`\`` + (item.docs ? "\n" + item.docs.split("\n")[0] : "");
  }

  /** An entry from a bundled index. `match` adds the match kind and the type score. */
  function compactItem(item: ScopedItem, match?: SigMatch): string {
    const label = match ? ` (${match.matchKind}, score ${match.score})` : "";
    return compactEntry(item, `**${item.fullName}**${originSuffix(item)}${label}`);
  }

  /** Items in order of how well their names match `pattern`, best first: the name level, then the word order. */
  function byNameQuality<T extends Decl>(items: T[], pattern: NamePattern): T[] {
    return items
      .map((item) => ({ item, q: nameRank(item, pattern) }))
      .filter(({ q }) => q >= 0)
      .sort((a, b) => b.q - a.q || compareItems(a.item, b.item))
      .map(({ item }) => item);
  }

  /** The line under a list that shows only `max` of `total` entries. */
  function moreLine(total: number, max: number, hint: string): string {
    return total > max ? `\n\nShowing ${max} of ${total}. Raise \`limit\`, or ${hint}.` : "";
  }

  /** `a`, `a` and `b`, or `a`, `b` and `c`. */
  function andList(words: string[]): string {
    const quoted = words.map((w) => `\`${w}\``);
    return quoted.length < 2 ? quoted.join("") : `${quoted.slice(0, -1).join(", ")} and ${quoted.at(-1)}`;
  }

  /**
   * The names that match `pattern`, under a head line, or null when nothing
   * matches. One name with no exact match reads as its last segment in the
   * module before it: `F32.floor_to_i64` finds `Num.F32.floor_to_i64_try`.
   */
  function nameList<T extends Decl>(
    query: string,
    pattern: NamePattern,
    items: T[],
    max: number,
    entry: (item: T) => string
  ): { text: string; shown: T[] } | null {
    const close = byNameQuality(items, pattern);
    if (close.length === 0) return null;
    const shown = close.slice(0, max);
    const n = close.length;
    const where = pattern.module ? ` in \`${pattern.module}\`` : "";
    const head =
      pattern.parts.length > 1
        ? `${n} ${n === 1 ? "name contains" : "names contain"} ${andList(pattern.parts)}${where}:`
        : pattern.parts.length === 1
          ? `Nothing is named \`${query}\`. ${n} ${n === 1 ? "name contains" : "names contain"} \`${pattern.parts[0]}\`:`
          : `${n} ${n === 1 ? "symbol is" : "symbols are"} in \`${pattern.module}\`:`;
    return {
      text:
        `${head}\n\n${shown.map(entry).join("\n\n")}` +
        moreLine(n, max, `add a type to rank them, as in \`${query} : -> Bool\``),
      shown,
    };
  }

  /** The pattern of one name with no exact match: the last segment, in the module before it. `Foo` is a word here, not a module. */
  function lastSegment(query: string): NamePattern {
    const dot = query.lastIndexOf(".");
    const part = query.slice(dot + 1);
    return { raw: query, module: dot > 0 ? query.slice(0, dot) : "", parts: part ? [part] : [] };
  }

  /** The matches of `query` with a type score above a substring match. */
  function typedCount(values: Decl[], query: string): number {
    return searchBySig(values, query, Number.MAX_SAFE_INTEGER).filter((m) => m.score > SUBSTRING_SCORE).length;
  }

  /**
   * The count of the type reading of a type's name: the functions that take it
   * first, and those that return it. A count tells the caller if the call is
   * worth making, and the query in it finds the methods of the type. Empty when
   * both counts are 0.
   */
  function countLine(types: Decl[], values: Decl[]): string {
    const lines = [...new Map(types.filter((t) => t.kind === "type").map((t) => [t.name, t])).values()].map((t) => {
      const head = t.head ?? t.name;
      const a = /^[AEIOU]/.test(t.name) ? "an" : "a";
      const take = typedCount(values, `${head} ->`);
      const give = typedCount(values, `-> ${head}`);
      const takes = take > 0 ? `${take} ${take === 1 ? "function takes" : "functions take"} ${a} \`${t.name}\` (\`${head} ->\`).` : "";
      const gives =
        give === 0
          ? ""
          : take > 0
            ? `${give} ${give === 1 ? "returns" : "return"} one (\`-> ${head}\`).`
            : `${give} ${give === 1 ? "function returns" : "functions return"} ${a} \`${t.name}\` (\`-> ${head}\`).`;
      return [takes, gives].filter(Boolean).join(" ");
    });
    return lines.filter(Boolean).map((l) => `\n\n${l}`).join("");
  }

  /** The module that `query` names, as a full path, or null. `Snapshot` names `Devices.Snapshot`. */
  function moduleNamed(paths: Iterable<string>, query: string): string | null {
    for (const p of paths) if (p === query || p.endsWith("." + query)) return p;
    return null;
  }

  /**
   * A miss that a different query shape answers, or null. The caller learns the
   * shape at the moment that it needs it:
   * - `Frame.text!`, when `Frame` is a type: a method is declared in its module.
   * - `Space`: a tag is part of a union type, and the index has no tags.
   */
  function shapeHint(query: string, items: Decl[]): string | null {
    const dot = query.lastIndexOf(".");
    if (dot > 0) {
      const owner = query.slice(0, dot);
      const bare = owner.slice(owner.lastIndexOf(".") + 1);
      const type = items.find((it) => it.kind === "type" && (it.fullName === owner || it.name === bare));
      if (!type) return null;
      const head = type.head ?? type.name;
      const home = type.modulePath ? ` in \`${type.modulePath}\`` : "";
      return (
        `\`${owner}\` is a type${home}. Its functions are in their module, so search ` +
        `\`${query.slice(dot + 1)}\`, or \`${head} ->\` for the functions that take ${/^[AEIOU]/.test(bare) ? "an" : "a"} \`${bare}\`.`
      );
    }
    if (!/^[A-Z]/.test(query)) return null;
    const typeNames = new Set(items.filter((it) => it.kind === "type").map((it) => it.name));
    const tags: string[] = [];
    for (const it of items) {
      if (it.kind !== "type") continue;
      for (const tag of new Set(it.signature.match(/(?<![\w.])[A-Z]\w*(?![\w.])/g) ?? [])) {
        if (tag.includes(query) && !typeNames.has(tag)) tags.push(`\`${tag}\` in \`${it.fullName}\``);
      }
    }
    if (tags.length === 0) return null;
    const shown = tags.slice(0, 3).join(", ") + (tags.length > 3 ? `, and ${tags.length - 3} more` : "");
    return tags.length === 1
      ? `No symbol is named \`${query}\`. ${tags[0].replace(" in ", " is a tag in ")}.`
      : `No symbol is named \`${query}\`. Tags that contain it: ${shown}.`;
  }

  /** The matches of `type` among `named`, above a substring match, and with the name level to break a tie. */
  function typedHits<T extends Decl>(named: T[], pattern: NamePattern, type: string): SigMatch<T>[] {
    return searchBySig(named, type, Number.MAX_SAFE_INTEGER, (it) => nameRank(it, pattern)).filter(
      (m) => m.score > SUBSTRING_SCORE
    );
  }

  /**
   * The reply to a name and a type, for symbols whose names match. The name
   * filters, and the type ranks. The name decides only the order of matches
   * with equal type scores, so the answer uses one ranking. A `substring` match
   * only contains the type as text, so it does not count as an answer here.
   * Without a name filter, stronger matches hide such a match. When nothing
   * matches, the substring matches come first in the list of closest symbols.
   */
  function nameAndType<T extends Decl>(
    pattern: NamePattern,
    type: string,
    named: T[],
    max: number,
    entry: (item: T, match?: SigMatch<T>) => string
  ): { text: string; shown: number } {
    const hits = typedHits(named, pattern, type);
    if (hits.length === 0) {
      // A type that contains the query type as text is closer than one that does
      // not. So `ceiling_to_i32_try : F32 -> ..` comes before
      // `Dec.ceiling : Dec -> Dec`.
      const near = searchBySig(named, type, Number.MAX_SAFE_INTEGER, (it) => nameRank(it, pattern)).map((m) => m.item);
      const closest = [...new Set([...near, ...byNameQuality(named, pattern)])];
      const shown = closest.slice(0, max);
      return {
        text:
          `No symbol similar to \`${pattern.raw}\` matches \`${type}\`. ` +
          `${named.length} ${named.length === 1 ? "symbol has" : "symbols have"} a different type. ` +
          `Closest ${shown.length === 1 ? "match" : "matches"}:\n\n` +
          shown.map((it) => entry(it)).join("\n\n") +
          moreLine(closest.length, max, "change the type"),
        shown: 0,
      };
    }
    const shown = hits.slice(0, max);
    return {
      text: shown.map((m) => entry(m.item, m)).join("\n\n") + moreLine(hits.length, max, "narrow the name"),
      shown: shown.length,
    };
  }

  const TYPE_TIP = "Tip: type variable names don't matter (structural match), but argument order does.";

  // The parser is the only source. See the TODO in project_index.ts.
  const projectIndex = new ProjectIndex(config.projectSources ?? [parserSource]);

  /** The declarations in the workspace, or none when it cannot be walked. */
  async function workspaceItems(): Promise<ProjectSignature[]> {
    const root = await detectionRoot().catch(() => process.cwd());
    return projectIndex.get(root).then((snap) => snap.items, () => []);
  }

  /**
   * The reply for `name` when it is a module of the project, else null. The
   * reply names the source file, because the file is the whole module and the
   * index has only what the parser read.
   */
  function projectModuleNote(name: string, items: ProjectSignature[]): string | null {
    // `Geo.` is the query shape that lists a module.
    const module = moduleNamed(new Set(items.map((it) => it.modulePath).filter(Boolean)), name.replace(/\.$/, ""));
    if (!module) return null;
    const files = [...new Set(items.filter((it) => it.modulePath === module).map((it) => `\`${it.file}\``))];
    return (
      `\`${module}\` is a module of this project, in ${files.join(", ")}. ` +
      `Read ${files.length === 1 ? "that file" : "those files"}, or call \`search_project_symbols\` with \`${module}.\` for its signatures.`
    );
  }

  /**
   * The project declarations that a bundled miss reads. `items` is null on the
   * first pass, which only records the miss. The project index costs a walk of
   * the workspace, so only a miss reads it.
   */
  type ProjectProbe = { items: ProjectSignature[] | null; missed: boolean };

  /** The reply in place of a bundled miss when `name` is a project module, else null. Records the miss in `probe`. */
  function projectModule(probe: ProjectProbe | undefined, name: string): string | null {
    if (!probe) return null;
    probe.missed = true;
    return probe.items ? projectModuleNote(name, probe.items) : null;
  }

  /** A note that counts the project symbols that match `pattern`. Records the miss in `probe`. */
  function projectMatches(probe: ProjectProbe | undefined, pattern: NamePattern): string {
    if (!probe) return "";
    probe.missed = true;
    const n = probe.items?.filter((it) => nameQuality(it, pattern) >= 0).length ?? 0;
    if (n === 0) return "";
    return `\n\n\`search_project_symbols\` has ${n} ${n === 1 ? "match" : "matches"} for \`${pattern.raw.trim()}\` in this project.`;
  }

  /** The note on a reply that shows a symbol of the host ABI boundary. */
  function hostNote(items: ScopedItem[]): string {
    return items.some((m) => m.tier === "host")
      ? "\n\nThis is the host ABI boundary. An application must not call it. A platform author writing glue does."
      : "";
  }

  /**
   * A name. An exact hit resolves across the whole address space, so a caller
   * who has a name never gets "not found" because of a wrong corpus guess.
   * Without an exact hit, the answer is a list of the names that contain the
   * query, from the `scope` corpus when the call names one.
   */
  function searchByName(
    query: string,
    scope: ScopeName | undefined,
    max: number,
    notes: Set<string>,
    probe?: ProjectProbe
  ): string {
    // The address space holds one platform at most, so platform names do not
    // collide in it. A name outside it gets an "out of scope" report, not
    // "unknown".
    const active = activePlatform(scope);
    const idx = getMergedIndex(scope);
    const matches: ScopedItem[] = [];

    if (query.includes(".")) {
      // Try an exact fully qualified match first. If two namespaces claim a name,
      // the answer shows both, each with the label of its package. The app
      // reaches them as `http.Request` and `pf.Request`, and both compile. A
      // choice of one could hide the one that the caller meant.
      const claimed = idx.collisions.get(query);
      const exact = idx.byFullName.get(query);
      if (claimed) {
        matches.push(...claimed);
      } else if (exact) {
        matches.push(exact);
      } else {
        // Maybe the user wrote `U64.from_str` and the actual path is `Num.U64.from_str`.
        for (const item of idx.items) {
          if (item.fullName.endsWith("." + query)) matches.push(item);
        }
      }
    } else {
      matches.push(...(idx.byName.get(query) ?? []));
    }

    if (matches.length > 0) {
      // `Try`, `Bool`, `Dict` and similar names are both a type and a module. The
      // type body is the internal representation, not the API. Without this line,
      // the caller reads `Dict :: [HashMap({ ... })]` and tries to construct it.
      const alsoModule = idx.modulePaths.has(query)
        ? `\n\n\`${query}\` is also a module. Call \`get_roc_module("${query}")\` for its methods.`
        : "";
      // A name that two namespaces declare is two items, which an app reaches
      // through two aliases. The origin on each heading identifies the item. This
      // line says why there are two.
      const shared = [...new Set(matches.map((m) => m.fullName))].filter(
        (n) => new Set(matches.filter((m) => m.fullName === n).map((m) => m.ns)).size > 1
      );
      const sharedNote = shared
        .map(
          (n) =>
            `\`${n}\` is declared by ${new Set(matches.filter((m) => m.fullName === n).map((m) => m.ns)).size} modules, one per origin below. An app imports each through its own header alias.\n\n`
        )
        .join("");
      return (
        sharedNote +
        matches.map(formatScopedItem).join("\n\n") +
        countLine(matches, workingValues(scope)) +
        hostNote(matches) +
        alsoModule
      );
    }

    // A module is not a symbol. Its page lists what it holds.
    const module = moduleNamed(idx.modulePaths, query);
    if (module) return `\`${query}\` is a module. Call \`get_roc_module("${module}")\` for its page.`;

    const close = nameList(query, lastSegment(query), scope ? scopeIndex(scope, scope).items : idx.items, max, (it) =>
      compactItem(it)
    );
    if (close) return close.text + hostNote(close.shown);

    // A tag of the host ABI is not one that an app writes.
    const hint = shapeHint(query, idx.items.filter((it) => it.tier === "public"));
    if (hint) return hint;
    const local = projectModule(probe, query);
    if (local) return local;
    const found = elsewhere(PLATFORM_SCOPES, active ? [active] : [], "anywhere", (sc) =>
      nameMatchCount(registry.index(sc), query)
    );
    const away = outOfScopeNote(`\`${query}\``, found, active);
    // The docs fallback cannot filter by module, so a qualified name gets no fallback.
    const mentions = away || query.includes(".") ? "" : mentionList(query, scope, max);
    return (
      (away ??
        (mentions
          ? `Nothing is named \`${query}\`.${mentions}`
          : `Nothing matched "${query}". Call \`list_roc_index\` with kind='modules', or \`get_roc_module\` with a name like Str, List, Num, U64, Dec.`)) +
      projectMatches(probe, lastSegment(query)) +
      unpinnedPackageNote(`\`${query}\``, (idx) => nameMatches(idx, query)) +
      trailingNotes({ read: active ? [active] : [], empty: true, sessionNotes: notes })
    );
  }

  /**
   * The values that a type search reads in one scope: only annotated values. A
   * type body is not a function signature, and neither is the lambda head of a
   * value that upstream did not annotate.
   */
  function typedValuesIn(s: ScopeName, scope: ScopeName | undefined): ScopedItem[] {
    return appFacing(s, scope).filter((it) => it.kind === "value" && !it.unannotated);
  }

  /** The values that a type search reads over the working set, or over the one corpus that `scope` names. */
  function workingValues(scope: ScopeName | undefined): ScopedItem[] {
    return resolveScopes(scope, SIGNATURE_SCOPES).flatMap((s) => typedValuesIn(s, scope));
  }

  /** Several words. No name is several words, so the answer is a list, from the corpus of a list (section 2 of the design doc). */
  function searchWords(
    pattern: NamePattern,
    scope: ScopeName | undefined,
    max: number,
    notes: Set<string>,
    probe?: ProjectProbe
  ): string {
    const active = activePlatform(scope);
    const items = scope ? scopeIndex(scope, scope).items : getMergedIndex(scope).items;
    const list = nameList(pattern.raw, pattern, items, max, (it) => compactItem(it));
    if (list) return list.text + hostNote(list.shown);
    const where = pattern.module ? ` in \`${pattern.module}\`` : "";
    return (
      `No name contains ${andList(pattern.parts)}${where}.` +
      // The docs fallback cannot filter by module, so `F32.try ceil` gets no fallback.
      (pattern.module ? "" : mentionList(pattern.raw, scope, max)) +
      projectMatches(probe, pattern) +
      unpinnedPackageNote(`\`${pattern.raw}\``, (idx) => idx.items.filter((it) => nameQuality(it, pattern) >= 0)) +
      trailingNotes({ read: active ? [active] : [], empty: true, sessionNotes: notes })
    );
  }

  /** A Hoogle-style structural search, over the working set or the one corpus that `scope` names. */
  function searchByType(type: string, scope: ScopeName | undefined, max: number, notes: Set<string>): string {
    const wanted = resolveScopes(scope, SIGNATURE_SCOPES);
    const top = searchBySig(wanted.flatMap((s) => typedValuesIn(s, scope)), type, max);

    // Count the matches in every scope, so the footer can point to a corpus with
    // matches. The result count has a cap, so a narrower search saves no tokens.
    // It changes only which ten results the search returns.
    const others = elsewhere(
      SCOPES.filter((s) => s !== "language"),
      wanted,
      "pinned",
      (s) => searchBySig(typedValuesIn(s, scope), type, 1000).length
    );

    if (top.length === 0) {
      return (
        `No matches for \`${type}\` in scope=${wanted.join("+")}.\n\n${TYPE_TIP}` +
        trailingNotes({ read: wanted, found: { shown: 0, others }, sessionNotes: notes })
      );
    }
    return (
      top.map((m) => compactItem(m.item, m)).join("\n\n") +
      trailingNotes({ read: wanted, found: { shown: top.length, others }, detection: true, sessionNotes: notes })
    );
  }

  /** A name and a type, over the working set or the one corpus that `scope` names. */
  function searchByNameAndType(
    pattern: NamePattern,
    type: string,
    scope: ScopeName | undefined,
    max: number,
    notes: Set<string>
  ): string {
    const wanted = resolveScopes(scope, SIGNATURE_SCOPES);
    const namedIn = (s: ScopeName) => typedValuesIn(s, scope).filter((it) => nameQuality(it, pattern) >= 0);
    const named = wanted.flatMap(namedIn);

    if (named.length === 0) {
      const others = elsewhere(SCOPES.filter((s) => s !== "language"), wanted, "anywhere", (s) => namedIn(s).length);
      return (
        `No annotated symbol in scope=${wanted.join("+")} has a name that matches \`${pattern.raw}\`.` +
        unpinnedPackageNote(`\`${pattern.raw}\``, (idx) => idx.items.filter((it) => nameQuality(it, pattern) >= 0)) +
        trailingNotes({ read: wanted, found: { shown: 0, others }, sessionNotes: notes })
      );
    }

    const reply = nameAndType(pattern, type, named, max, compactItem);
    const others = elsewhere(
      SCOPES.filter((s) => s !== "language"),
      wanted,
      "pinned",
      (s) => typedHits(namedIn(s), pattern, type).length
    );
    return (
      reply.text +
      trailingNotes({ read: wanted, found: { shown: reply.shown, others }, detection: reply.shown > 0, sessionNotes: notes })
    );
  }

  /**
   * At most 8 queries, so one call cannot return a whole corpus. The schema
   * shows only the list, but a lone string also answers, because a caller that
   * sends one by habit must not lose a turn to a validation error.
   */
  const QUERY_LIST = z.preprocess((v) => (typeof v === "string" ? [v] : v), z.array(z.string()).min(1).max(8));

  /** The entries per list: 10 for one query, 5 each for several, unless `limit` says otherwise. */
  const listMax = (queries: string[], limit?: number) => limit ?? (queries.length === 1 ? 10 : 5);

  /** One reply per query, each under its query when there are several, then the notes about the session. */
  function joinReplies(queries: string[], answer: (query: string) => string, notes: Iterable<string>): string {
    const body =
      queries.length === 1
        ? answer(queries[0])
        : queries.map((q) => `# \`${q.trim()}\`\n\n${answer(q)}`).join("\n\n");
    return body + [...notes].join("");
  }

  server.registerTool(
    "search_symbols",
    {
      annotations: READ_ONLY_FETCHES,
      title: "Search Symbols by Name or Type",
      description:
        "Find builtins and platform APIs by name, by type, or both, written as a Roc annotation `name : Type`. " +
        "A name (`concat`, `Str.concat`) returns each exact match with its docs, else the names that contain it. " +
        "A type (`: Str`, or anything with `->`) is a structural search: a type variable matches any type, " +
        "`-> T` matches the return type, `T ->` the arguments, and argument order matters. " +
        "Both, as in `ceil : -> Dec`, lists the names that contain `ceil`, ranked by type.",
      inputSchema: z.object({
        query: QUERY_LIST.describe(
          "Up to 8 queries. Each is a name ('Str.concat'), words in a name ('size window'), a module ending in '.' " +
            "('Keys.'), a type ('-> Bool', or 'Frame ->' for the functions that take a Frame), or a name and a type ('ceil : -> Dec')."
        ),
        scope: scopeArg(
          SIGNATURE_SCOPES,
          "A platform to read in place of the one this app's header imports, or one corpus to limit a list to.",
          { hint: true }
        ),
        limit: z.number().int().positive().optional().describe("Max list entries per query (default 10, or 5 for several queries)."),
      }),
    },
    async ({ query, scope, limit }) => {
      await ensureDetection();
      const sc = scope as ScopeName | undefined;
      const max = listMax(query, limit);
      const notes = new Set<string>();
      const probe: ProjectProbe = { items: null, missed: false };
      const answer = (one: string) => {
        const q = parseSymbolQuery(one);
        return q.kind === "error"
          ? q.message
          : q.kind === "name"
            ? searchByName(q.name, sc, max, notes, probe)
            : q.kind === "words"
              ? searchWords(q.name, sc, max, notes, probe)
              : q.kind === "type"
              ? searchByType(q.type, sc, max, notes)
              : searchByNameAndType(q.name, q.type, sc, max, notes);
      };
      let text = joinReplies(query, answer, notes);
      // A name that the bundled indexes lack may be the caller's own.
      if (probe.missed) {
        probe.items = await workspaceItems();
        text = joinReplies(query, answer, notes);
      }
      return { content: [{ type: "text", text }] };
    }
  );

  server.registerTool(
    "get_roc_module",
    {
      annotations: READ_ONLY_FETCHES,
      title: "Get a Roc Module",
      description:
        "Every function and type in one module as a signature list: a builtin (`Str`, `U64`), a module of the app's platform (`Path`), or a module of a documented package (`Html`). Bare `U64` resolves to `Num.U64`. detail='full' adds docstrings and examples. For one function use `search_symbols`. For a module of your project, read its file.",
      inputSchema: z.object({
        module: z.string().describe("Module name, e.g. 'Str', 'U64', 'Num.Dec', 'Path'."),
        detail: z
          .enum(["signatures", "full"])
          .optional()
          .describe("'signatures' (default) lists name and type only. 'full' adds docstrings and examples, ~5x longer."),
        scope: scopeArg(PLATFORM_SCOPES, "Read a platform other than the one this app's header imports. Rarely needed."),
      }),
    },
    async ({ module: modName, detail, scope }) => {
      await ensureDetection();
      const active = activePlatform(scope as ScopeName | undefined);
      const idx = getMergedIndex(scope as ScopeName | undefined);
      const requested = modName.trim();
      const full = detail === "full";

      // Resolve module path.
      let resolved: string | null = null;
      if (idx.modulePaths.has(requested)) {
        resolved = requested;
      } else {
        // Look for a path that ends with `.<requested>`, then for a case-insensitive match.
        for (const p of idx.modulePaths) {
          if (p === requested || p.endsWith("." + requested)) {
            resolved = p;
            break;
          }
        }
        if (!resolved) {
          const lower = requested.toLowerCase();
          for (const p of idx.modulePaths) {
            if (p.toLowerCase() === lower) {
              resolved = p;
              break;
            }
          }
        }
        // `modulePaths` holds only paths that declare a value, so it lacks `Num`.
        // `Num.U64` and 22 other modules sit under it.
        if (!resolved && [...idx.modulePaths].some((p) => p.startsWith(`${requested}.`))) resolved = requested;
      }

      if (!resolved) {
        // A name that no bundled module has may be a module of the project.
        const local = projectModuleNote(requested, await workspaceItems());
        if (local) return { content: [{ type: "text", text: local }] };
        // A module outside the address space is out of scope. An out-of-scope
        // module calls for a different next step than an unknown module.
        // The count is what the caller would see in that scope, so the rule of the
        // listing applies: public members, or all members of a host-only module.
        const found = elsewhere(PLATFORM_SCOPES, active ? [active] : [], "anywhere", (sc) => {
          if (!registry.index(sc).modulePaths.has(requested)) return 0;
          const members = registry.index(sc).items.filter((it) => it.modulePath === requested);
          const shown = members.filter((it) => it.tier === "public");
          return shown.length || members.length;
        });
        const miss =
          unpinnedPackageNote(`\`${requested}\``, (idx) => idx.items.filter((it) => it.modulePath === requested)) +
          trailingNotes({ read: active ? [active] : [], empty: true });
        const note = outOfScopeNote(`\`${requested}\``, found, active);
        if (note) return { content: [{ type: "text", text: note + miss }] };
        // The suggestion list omits host-tier modules for the same reason as
        // `list_roc_index`. But `Host` resolves above, so a caller who knows the
        // name gets it.
        const list = [...idx.modulePaths]
          .filter((p) => idx.items.some((i) => i.modulePath === p && i.tier === "public"))
          .sort()
          .join(", ");
        return {
          content: [
            {
              type: "text",
              text: `Unknown module "${modName}". Available modules: ${list}` + miss,
            },
          ],
        };
      }

      // The address space holds one platform, so it has one `Path`. A module of a
      // different platform here would advertise an API that this workspace cannot
      // compile against.
      const all = idx.items.filter((it) => it.modulePath === resolved);
      // Exclude the host ABI boundary, unless the module is host-only. For a
      // host-only module, that would answer a direct question with an empty page.
      const moduleIsHost = all.length > 0 && all.every((it) => it.tier === "host");
      const own = moduleIsHost ? all : all.filter((it) => it.tier === "public");
      // Counted across the subtree. `Server.Config.to_host` is not a direct child
      // of `Server`, but a question about `Server` includes it.
      const hiddenHost = moduleIsHost
        ? 0
        : idx.items.filter(
            (it) =>
              it.tier === "host" &&
              (it.modulePath === resolved || it.modulePath.startsWith(`${resolved}.`))
          ).length;
      // Types first, because the signatures below use them.
      const ordered = (items: ScopedItem[]) => [
        ...items.filter((it) => it.kind === "type"),
        ...items.filter((it) => it.kind === "value"),
      ];
      const tallyOf = (items: ScopedItem[]) => {
        const types = items.filter((it) => it.kind === "type").length;
        const values = items.length - types;
        const methods = values === 1 ? "1 method" : `${values} methods`;
        return types > 0 ? `${methods}, ${types === 1 ? "1 type" : `${types} types`}.` : `${methods}.`;
      };
      const signatures = (items: ScopedItem[]) => [
        "```roc",
        ...ordered(items).flatMap((m) => {
          const sig = declLine(m, m.signature.replace(/\s+/g, " ").trim());
          const hint = hintFor(m);
          return hint ? [`# ${hint}`, sig] : [sig];
        }),
        "```",
      ];
      // Two namespaces can expose one module name, e.g. `Random` in basic-cli and
      // in roc-random. An app imports them as two modules, so each gets its own
      // section. The common case is one namespace, which stays one flat list.
      const groups = new Map<string, ScopedItem[]>();
      for (const it of own) groups.set(it.ns, [...(groups.get(it.ns) ?? []), it]);
      const split = groups.size > 1;
      const origins = [...new Set(own.map((it) => it.origin))].filter((o) => o !== "Builtin.roc");
      const tally =
        tallyOf(own) +
        (split
          ? ` ${groups.size} modules share this name, one per origin below. An app imports each through its own header alias.`
          : origins.length > 0
            ? ` From ${origins.join(", ")}.`
            : "") +
        (moduleIsHost ? " This module is the host ABI boundary; an application must not call it." : "");

      // Docstrings and their `expect` blocks are about 6x the size of the
      // signatures. Thus the default answers "what methods exist", and
      // search_symbols answers "how does this one work".
      const section = (items: ScopedItem[]): string[] =>
        full ? [ordered(items).map((m) => formatScopedItem(m)).join("\n\n")] : signatures(items);
      const sections = split
        ? [...groups.values()].flatMap((items) => [
            `## ${items[0].origin}`,
            "",
            ...(full ? [] : [tallyOf(items), ""]),
            ...section(items),
            "",
          ])
        : [...section(own), ""];
      // The methods of a type declared in this module, such as `Text.Builder.size`,
      // have their own module path. Static dispatch calls them on a value of that
      // type, so a page that omits them hides the type's API. Above NESTED_CAP,
      // the page names each nested module and its item count.
      const nestedGroups = new Map<string, ScopedItem[]>();
      if (!moduleIsHost) {
        for (const it of idx.items) {
          if (it.tier === "public" && it.modulePath.startsWith(`${resolved}.`)) {
            nestedGroups.set(it.modulePath, [...(nestedGroups.get(it.modulePath) ?? []), it]);
          }
        }
      }
      const nestedCount = [...nestedGroups.values()].reduce((n, items) => n + items.length, 0);
      const nested =
        nestedCount === 0
          ? []
          : nestedCount <= NESTED_CAP
            ? [...nestedGroups.entries()]
                .sort(([a], [b]) => a.localeCompare(b))
                .flatMap(([p, items]) => [`## ${p}`, "", ...(full ? [] : [tallyOf(items), ""]), ...section(items), ""])
            : [
                "Nested modules, with the item count of each: " +
                  [
                    ...[...nestedGroups.entries()].reduce((children, [p, items]) => {
                      const child = `${resolved}.${p.slice(resolved.length + 1).split(".")[0]}`;
                      return children.set(child, (children.get(child) ?? 0) + items.length);
                    }, new Map<string, number>()),
                  ]
                    .sort(([a], [b]) => a.localeCompare(b))
                    .map(([p, n]) => `\`${p}\` (${n})`)
                    .join(", ") +
                  ". Call `get_roc_module` on one.",
                "",
              ];
      const body = [
        `# ${resolved}`,
        "",
        ...(own.length === 0 ? [] : [...(full && !split ? [] : [tally, ""]), ...sections]),
        ...nested,
        ...(full ? [] : ["Use `search_symbols` for a docstring and examples, or call this again with `detail: \"full\"`."]),
      ]
        .join("\n")
        .trimEnd();

      // A project module with the same name is a different module. The caller may
      // have meant it.
      const local = projectModuleNote(requested, await workspaceItems());
      const shadow = local ? `\n\nThe page above is the bundled \`${resolved}\`. ${local}` : "";
      const text = body + shadow + trailingNotes({ read: active ? [active] : [], hostTier: hiddenHost });

      return {
        content: [{ type: "text", text }],
      };
    }
  );


  // -----------------------------------------------------------------------------
  // roc check
  // -----------------------------------------------------------------------------

  type RocCheckResult = {
    ok: boolean;
    exit_code: number;
    stdout: string;
    stderr: string;
    checked_path: string;
    [key: string]: unknown;
  };

  async function runRocCheck(targetPath: string, timeout: number): Promise<RocCheckResult> {
    try {
      const { stdout, stderr } = await execFileAsync(rocCommand(config.argv, config.env), ["check", "--no-color", targetPath], {
        timeout,
        maxBuffer: 4 * 1024 * 1024,
      });
      return { ok: true, exit_code: 0, stdout, stderr, checked_path: targetPath };
    } catch (err: any) {
      if (err?.code === "ENOENT" || err?.code === "EACCES") {
        throw new Error(rocMissing(config.argv, config.env));
      }
      if (err?.killed) {
        throw new Error(
          `\`roc check\` timed out after ${timeout / 1000}s on ${targetPath}. ` +
            "A first check of code with a new platform downloads it; run `roc check` " +
            "once in a shell to fill the package cache, then call this again."
        );
      }
      // Non-zero exit from `roc check` is the expected failure path, so return it.
      return {
        ok: false,
        exit_code: typeof err?.code === "number" ? err.code : 1,
        stdout: err?.stdout ?? "",
        stderr: err?.stderr ?? String(err?.message ?? err),
        checked_path: targetPath,
      };
    }
  }

  /** Enough of a file to hold its header, which is where package URLs live. */
  function readHeadSync(file: string, bytes = 8192): string {
    const fd = fs.openSync(file, "r");
    try {
      const buf = Buffer.alloc(bytes);
      const read = fs.readSync(fd, buf, 0, bytes, 0);
      return buf.subarray(0, read).toString("utf-8");
    } finally {
      fs.closeSync(fd);
    }
  }

  const badInput = (message: string) => ({
    content: [{ type: "text" as const, text: message }],
    isError: true,
  });

  server.registerTool(
    "roc_check",
    {
      annotations: READ_ONLY_FETCHES,
      title: "Type-check Roc source with `roc check`",
      description: "Type-check Roc source with the real compiler. Pass `code` or `path`. Requires the Roc compiler.",
      inputSchema: z.object({
        code: z.string().optional().describe("Roc source to check. Not with `path`."),
        path: z.string().optional().describe("Absolute path to a .roc file. Not with `code`."),
        scope: scopeArg(PLATFORM_SCOPES, "Wrap headerless `code` in this platform's app. Omit if it has a header."),
      }),
    },
    async ({ code, path: filePath, scope }) => {
      await ensureDetection();
      if ((code === undefined || code === "") && !filePath) {
        return badInput("Provide either `code` (Roc source) or `path` (an absolute .roc path).");
      }
      if (code !== undefined && code !== "" && filePath) {
        return badInput("Pass `code` OR `path`, not both.");
      }
      if (filePath && !path.isAbsolute(filePath)) {
        return badInput(`\`path\` must be absolute, got: ${filePath}`);
      }

      // If the caller names no platform, wrap the code in the workspace platform,
      // if there is one. Nothing else supplies a platform. An installed platform
      // does not show what the caller writes. The wrapper decides if the report
      // says that the code compiles, so a wrong guess gives a wrong verdict.
      const wrapWith = (scope as ScopeName | undefined) ?? detected?.scope ?? undefined;
      const wrapped = filePath ? null : scaffold(code!, wrapWith, catalog);

      let target: string;
      let cleanup: (() => void) | null = null;

      if (filePath) {
        target = filePath;
      } else {
        const tmpDir = scratchDir("check");
        target = path.join(tmpDir, "main.roc");
        fs.writeFileSync(target, wrapped!.source, "utf-8");
        cleanup = () => {
          try {
            fs.rmSync(tmpDir, { recursive: true, force: true });
          } catch {
            /* ignore */
          }
        };
      }

      try {
        // The header decides the timeout, so read a header in both cases. The
        // compiler reports a file that cannot be read, not this tool.
        let header = wrapped?.source ?? "";
        if (filePath) {
          try {
            header = readHeadSync(filePath);
          } catch {
            header = "";
          }
        }

        const raw = await runRocCheck(target, timeoutFor(header));
        const report = parseReport(raw.stderr);
        if (wrapped) {
          report.user = report.user.map((d) => remap(d, target, wrapped.offset));
        }
        const text = formatReport(report, {
          source: header,
          supplied: wrapped?.supplied ?? [],
          wrappedIn: wrapped?.wrappedIn ?? null,
          ok: raw.ok,
          raw: [raw.stderr, raw.stdout].filter((s) => s.trim()).join("\n"),
        });

        // The compiler's own count adds the errors of dependencies to the errors of
        // the caller. This tool exists to separate them, so `isError` follows the
        // partitioned report and not the exit code of the compiler.
        const ok = raw.ok && report.user.every((d) => d.severity !== "error");
        return {
          content: [{ type: "text", text }],
          isError: !ok,
        };
      } catch (err: any) {
        const message = err?.message ?? String(err);
        return {
          content: [{ type: "text", text: message }],
          isError: true,
        };
      } finally {
        cleanup?.();
      }
    }
  );

  // -----------------------------------------------------------------------------
  // roc fmt
  // -----------------------------------------------------------------------------

  type RocFmtResult = {
    ok: boolean;
    exit_code: number;
    formatted: string;
    stderr: string;
    unchanged: boolean;
    [key: string]: unknown;
  };

  server.registerTool(
    "roc_fmt",
    {
      annotations: READ_ONLY,
      title: "Format Roc source with `roc fmt`",
      description: "Format Roc source. Pass `code` or `path`, the same either/or as `roc_check`. Never writes the file. Requires the Roc compiler.",
      inputSchema: z.object({
        code: z.string().optional().describe("Roc source to format. Not with `path`."),
        path: z.string().optional().describe("Absolute path to a .roc file. Not with `code`."),
      }),
    },
    async ({ code, path: filePath }) => {
      // The same input rules and messages as `roc_check`. If two neighbouring
      // tools took different inputs, a model would need a failed call to tell
      // them apart.
      if ((code === undefined || code === "") && !filePath) {
        return badInput("Provide either `code` (Roc source) or `path` (an absolute .roc path).");
      }
      if (code !== undefined && code !== "" && filePath) {
        return badInput("Pass `code` OR `path`, not both.");
      }
      if (filePath && !path.isAbsolute(filePath)) {
        return badInput(`\`path\` must be absolute, got: ${filePath}`);
      }

      let source: string;
      if (filePath) {
        try {
          source = fs.readFileSync(filePath, "utf-8");
        } catch (err: any) {
          return badInput(`Could not read ${filePath}: ${err?.message ?? String(err)}`);
        }
      } else {
        source = code!;
      }

      const tmpDir = scratchDir("fmt");
      const target = path.join(tmpDir, "main.roc");
      fs.writeFileSync(target, source, "utf-8");

      try {
        try {
          const { stderr } = await execFileAsync(rocCommand(config.argv, config.env), ["fmt", target], {
            timeout: 30_000,
            maxBuffer: 4 * 1024 * 1024,
          });
          const formatted = fs.readFileSync(target, "utf-8");
          const result: RocFmtResult = {
            ok: true,
            exit_code: 0,
            formatted,
            stderr,
            unchanged: formatted === source,
          };
          // A caller who passed a path expects to know if the format of the file
          // changed, and that this tool did not write the file.
          const subject = filePath ? `${filePath} is` : "The source was";
          const summary = result.unchanged
            ? `\`roc fmt\` made no changes. ${subject} already canonical.`
            : "`roc fmt` reformatted the source. The canonical version is below" +
              (filePath ? `. ${filePath} is unchanged on disk.` : ".");
          return {
            content: [
              { type: "text", text: `${summary}\n\n\`\`\`roc\n${formatted}\n\`\`\`` },
            ],
          };
        } catch (err: any) {
          if (err?.code === "ENOENT" || err?.code === "EACCES") {
            const message = rocMissing(config.argv, config.env);
            return {
              content: [{ type: "text", text: message }],
              isError: true,
            };
          }
          if (err?.killed) {
            const message = `\`roc fmt\` timed out after 30s.`;
            return {
              content: [{ type: "text", text: message }],
              isError: true,
            };
          }
          const stderr = err?.stderr ?? String(err?.message ?? err);
          const exit = typeof err?.code === "number" ? err.code : 1;
          return {
            content: [
              {
                type: "text",
                text: `\`roc fmt\` failed (exit ${exit}).\n\n--- stderr ---\n${stderr}`,
              },
            ],
            isError: true,
          };
        }
      } finally {
        try {
          fs.rmSync(tmpDir, { recursive: true, force: true });
        } catch {
          /* ignore */
        }
      }
    }
  );

  // -----------------------------------------------------------------------------
  // Worked programs
  // -----------------------------------------------------------------------------

  /**
   * The worked programs filed under one scope, each with its address, such as
   * `basic-cli/hello`. The programs of a documented package are filed under
   * `language`, as its topics are. A package works on any platform, and a
   * program is how a caller finds the package.
   */
  function filedExamples(scope: ScopeName): { id: string; ex: ExampleFile }[] {
    const own = registry.examples(scope).map((ex) => ({ id: `${scope}/${ex.name}`, ex }));
    if (scope !== "language") return own;
    return [
      ...own,
      ...PACKAGE_DOCS.flatMap((d) => registry.packageExamples(d).map((ex) => ({ id: `${d.name}/${ex.name}`, ex }))),
    ];
  }

  /**
   * An example read by its address, `basic-cli/hello`, or by its resource URI.
   * A tool reads examples because a client may not read resources. Claude Code
   * also makes the resource read a deferred tool, which a model must load first.
   * Null if the query is not an address, so that the caller searches it as a
   * topic.
   */
  function exampleNamed(query: string): string | null {
    const m = /^(?:roc-syntax:\/\/(?:platform|package)\/)?([a-z][a-z0-9-]*)(?:\/example)?\/([^/\s]+)$/.exec(query.trim());
    if (!m) return null;
    const [, corpus, name] = m;
    const doc = PACKAGE_DOCS.find((d) => d.name === corpus);
    const examples = doc
      ? registry.packageExamples(doc)
      : (SCOPES as readonly string[]).includes(corpus)
        ? registry.examples(corpus as ScopeName)
        : null;
    if (!examples) return null;
    const ex = examples.find((e) => e.name === name.replace(/\.roc$/, ""));
    if (!ex) {
      const names = examples.map((e) => e.name).join(", ");
      return `No example "${name}" in ${corpus}. ${names ? `Its examples: ${names}.` : "It bundles none."}`;
    }
    return `## ${corpus}/${ex.name}\n\n${ex.title}\n\n\`\`\`roc\n${fs.readFileSync(ex.path, "utf-8").trimEnd()}\n\`\`\``;
  }

  // -----------------------------------------------------------------------------
  // Project signature search
  // -----------------------------------------------------------------------------

  /** An entry from a project file. It marks a type that a compiler inferred, because the author did not write that type. */
  function projectEntry(item: ProjectSignature, match?: SigMatch): string {
    const label = [match?.matchKind, item.origin === "inferred" ? "inferred" : "", match ? `score ${match.score}` : ""]
      .filter(Boolean)
      .join(", ");
    return compactEntry(item, `**${item.fullName}**${label ? ` (${label})` : ""} at \`${item.file}:${item.line}\``);
  }

  /** The exact matches of a name. A full name comes first, else a suffix, as in the bundled indexes. A bare name matches the last segment. */
  function exactIn<T extends Decl>(items: T[], query: string): T[] {
    if (!query.includes(".")) return items.filter((it) => it.name === query);
    const full = items.filter((it) => it.fullName === query);
    return full.length > 0 ? full : items.filter((it) => it.fullName.endsWith("." + query));
  }

  /** The note on a project miss when `search_symbols` has `count` matches. */
  function bundledNote(count: number, query: string): string {
    if (count === 0) return "";
    return `\n\n\`search_symbols\` has ${count} ${count === 1 ? "match" : "matches"} for \`${query}\` in the bundled indexes.`;
  }

  /**
   * `search_symbols` over the project, with the same grammar and the same
   * order. The project is one corpus, so the reply has no scope footer. A miss
   * says if the bundled indexes have the symbol.
   */
  function searchProject(query: string, items: ProjectSignature[], where: string, max: number): string {
    const q = parseSymbolQuery(query);
    if (q.kind === "error") return `${q.message} Indexed ${items.length} declarations in ${where}.`;
    // A type query reads only the values that have a type. A type body is not a
    // function signature, and an unannotated value has only its lambda head.
    const values = items.filter((it) => it.kind === "value" && !it.unannotated);
    if (q.kind === "name") {
      const exact = exactIn(items, q.name);
      if (exact.length > 0) {
        return (
          exact
            .map(
              (it) =>
                `## ${it.fullName}${it.origin === "inferred" ? " (inferred)" : ""} at \`${it.file}:${it.line}\`\n` +
                "```roc\n" + declLine(it, it.signature) + "\n```" + (it.docs ? `\n${it.docs}` : "")
            )
            .join("\n\n") + countLine(exact, values)
        );
      }
      // A project has no module page, and `Keys.` lists what a module holds.
      const module = moduleNamed(new Set(items.map((it) => it.modulePath).filter(Boolean)), q.name);
      if (module) {
        const n = items.filter((it) => it.modulePath === module).length;
        return `\`${q.name}\` is a module. \`${q.name}.\` lists its ${n} ${n === 1 ? "symbol" : "symbols"}.`;
      }
      const close = nameList(q.name, lastSegment(q.name), items, max, (it) => projectEntry(it));
      if (close) return close.text;
      const hint = shapeHint(q.name, items);
      return (
        (hint ? `${hint}\n\n` : "") +
        `Nothing in ${where} is named \`${q.name}\`.` +
        bundledNote(nameMatchCount(getMergedIndex(undefined), q.name), q.name)
      );
    }
    if (q.kind === "words") {
      const list = nameList(q.name.raw, q.name, items, max, (it) => projectEntry(it));
      if (list) return list.text;
      const bundled = getMergedIndex(undefined).items.filter((it) => nameQuality(it, q.name) >= 0).length;
      return `No name in ${where} contains ${andList(q.name.parts)}.` + bundledNote(bundled, q.name.raw);
    }
    if (q.kind === "type") {
      const all = searchBySig(values, q.type, Number.MAX_SAFE_INTEGER);
      if (all.length === 0) {
        return (
          `No matches for \`${q.type}\` in ${where}.\n\n${TYPE_TIP}` +
          bundledNote(searchBySig(workingValues(undefined), q.type, 1000).length, q.type)
        );
      }
      return all.slice(0, max).map((m) => projectEntry(m.item, m)).join("\n\n") + moreLine(all.length, max, "narrow the type");
    }
    const pattern = q.name;
    const named = values.filter((it) => nameQuality(it, pattern) >= 0);
    const bundled = () =>
      bundledNote(typedHits(workingValues(undefined).filter((it) => nameQuality(it, pattern) >= 0), pattern, q.type).length, query.trim());
    if (named.length === 0) return `No annotated value in ${where} has a name that matches \`${pattern.raw}\`.` + bundled();
    const reply = nameAndType(pattern, q.type, named, max, projectEntry);
    return reply.text + (reply.shown === 0 ? bundled() : "");
  }

  server.registerTool(
    "search_project_symbols",
    {
      annotations: READ_ONLY_FETCHES,
      title: "Search in Codebase by Name or Type",
      description:
        "`search_symbols` over the `.roc` files of your project or other codebase.",
      inputSchema: z.object({
        query: QUERY_LIST.describe("As for `search_symbols`."),
        root: z.string().optional().describe("Root of the codebase, absolute. The workspace by default."),
        limit: z.number().int().positive().optional().describe("As for `search_symbols`."),
      }),
    },
    async ({ query, root, limit }) => {
      await ensureDetection();
      const searchRoot = root ?? (await detectionRoot().catch(() => process.cwd()));

      let snap;
      try {
        snap = await projectIndex.get(searchRoot);
      } catch (err) {
        return {
          content: [{ type: "text", text: `Failed to discover .roc files under ${searchRoot}: ${err}` }],
        };
      }
      // Report each source that could not run, because its declarations are missing.
      const notes = snap.notes.length ? `\n\nNot indexed: ${snap.notes.join("; ")}` : "";
      const where = `${snap.files} .roc ${snap.files === 1 ? "file" : "files"} under \`${searchRoot}\``;
      const max = listMax(query, limit);
      const text = joinReplies(query, (one) => searchProject(one, snap.items, where, max), notes ? [notes] : []);
      return { content: [{ type: "text", text }] };
    }
  );

  // -----------------------------------------------------------------------------
  // MCP resources
  // -----------------------------------------------------------------------------

  function readUtf8(filePath: string): string {
    return fs.readFileSync(filePath, "utf-8");
  }

  // The overview, first because it is what a client should read first.
  server.registerResource(
    "roc-overview",
    "roc-syntax://overview",
    {
      title: "Roc Overview (start here)",
      description:
        "The whole Roc language and its builtins in two compact pages (~3k tokens). Read this before any other resource in this server. The other resources give the details that it names.",
      mimeType: "text/markdown",
    },
    async (uri) => ({
      contents: [
        { uri: uri.href, mimeType: "text/markdown", text: loadOverview(ROOT, DEFAULT_OVERVIEW_PAGES) },
      ],
    })
  );

  // Full syntax reference as a single resource.
  server.registerResource(
    "roc-syntax-reference",
    "roc-syntax://reference",
    {
      title: "Roc Syntax Reference",
      description:
        "Mirror of roc-lang/roc's all_syntax_test.roc. It demonstrates every Roc language construct in the new compiler.",
      mimeType: "text/x-roc",
    },
    async (uri) => ({
      contents: [
        { uri: uri.href, mimeType: "text/x-roc", text: readUtf8(FULL_SYNTAX_FILE) },
      ],
    })
  );

  /**
   * Builtin.roc is ~800 KB (23k lines, roughly 228k tokens), so serving it whole
   * would fill a client's context in one read. This index costs ~1 KB and names
   * the tools that fetch the parts.
   */
  function builtinIndexMarkdown(): string {
    const idx = getBuiltinIndex();
    const values = idx.items.filter((it) => it.kind === "value");
    const types = idx.items.length - values.length;
    const counts = new Map<string, number>();
    for (const item of values) counts.set(item.modulePath, (counts.get(item.modulePath) ?? 0) + 1);

    const rows = [...counts.entries()]
      .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
      .map(([mod, n]) => `| \`${mod || "(top level)"}\` | ${n} |`)
      .join("\n");

    const lines = readUtf8(BUILTIN_FILE).split("\n").length;

    return [
      "# Roc builtins",
      "",
      `${values.length} methods and ${types} types across ${counts.size} modules, parsed from \`Builtin.roc\` (${lines} lines).`,
      "",
      "The file itself is too large to serve in full. Use these tools:",
      "",
      "- `get_roc_module`: every method in one module, with signatures and docs.",
      "- `search_symbols`: one method by name (`concat`, `Str.concat`), a Hoogle-style search by type (`-> Bool`), or both (`ceil : -> Dec`).",
      "",
      "| Module | Methods |",
      "| --- | --- |",
      rows,
    ].join("\n");
  }

  server.registerResource(
    "roc-builtin",
    "roc-syntax://builtin",
    {
      title: "Roc Builtin Index",
      description:
        "Index of every builtin module and its method count. Builtin.roc itself is hundreds of thousands of tokens, so use get_roc_module or search_symbols, and do not read it whole.",
      mimeType: "text/markdown",
    },
    async (uri) => ({
      contents: [
        { uri: uri.href, mimeType: "text/markdown", text: builtinIndexMarkdown() },
      ],
    })
  );

  // Per-topic example files exposed via a URI template.
  server.registerResource(
    "roc-topic",
    new ResourceTemplate("roc-syntax://topic/{name}", {
      list: async () => ({
        resources: Object.entries(TOPICS).map(([name, meta]) => ({
          uri: `roc-syntax://topic/${name}`,
          name: `roc-topic-${name}`,
          title: name,
          description: meta.description,
          mimeType: "text/x-roc",
        })),
      }),
      complete: {
        name: async (value) =>
          Object.keys(TOPICS).filter((t) => t.startsWith(value.toLowerCase())),
      },
    }),
    {
      title: "Roc Syntax Topic",
      description:
        "Per-topic Roc syntax snippet. Use the URI roc-syntax://topic/<name> with one of the registered topic names.",
      mimeType: "text/x-roc",
    },
    async (uri, { name }) => {
      const topic = Array.isArray(name) ? name[0] : name;
      const text = loadTopic(topic, TOPICS);
      if (text === null) {
        throw new Error(`Unknown topic: ${topic}. Call list_roc_index with kind='topics' to see available topics.`);
      }
      return {
        contents: [{ uri: uri.href, mimeType: "text/x-roc", text }],
      };
    }
  );

  // A platform's worked programs, exposed via a URI template. Resources cost
  // nothing on `tools/list`, so an 82k-character corpus can be here in full.
  server.registerResource(
    "roc-platform-example",
    new ResourceTemplate("roc-syntax://platform/{platform}/example/{name}", {
      list: async () => ({
        resources: SCOPES.flatMap((sc) =>
          registry.examples(sc).map((ex) => ({
            uri: `roc-syntax://platform/${sc}/example/${ex.name}`,
            name: `roc-example-${sc}-${ex.name}`,
            title: ex.name,
            description: ex.title,
            mimeType: "text/x-roc",
          }))
        ),
      }),
      complete: {
        platform: async (value) =>
          SCOPES.filter((sc) => registry.examples(sc).length > 0 && sc.startsWith(value)),
        name: async (value) =>
          SCOPES.flatMap((sc) => registry.examples(sc).map((ex) => ex.name)).filter((n) =>
            n.startsWith(value.toLowerCase())
          ),
      },
    }),
    {
      title: "Platform Example Program",
      description:
        `One complete, compiling program from a platform's example set. Every bundled example passes \`roc check\` against the pinned platform. Use roc-syntax://platform/{${PLATFORM_SCOPES.join("|")}}/example/<name>, and list_roc_index with kind='examples' for the names.`,
      mimeType: "text/x-roc",
    },
    async (uri, { platform, name }) => {
      const scope = (Array.isArray(platform) ? platform[0] : platform) as ScopeName;
      const wanted = Array.isArray(name) ? name[0] : name;
      const ex = (SCOPES as readonly string[]).includes(scope)
        ? registry.examples(scope).find((e) => e.name === wanted)
        : undefined;
      if (!ex) {
        throw new Error(
          `Unknown example: ${platform}/${wanted}. Call list_roc_index with kind='examples' to see available programs.`
        );
      }
      return {
        contents: [{ uri: uri.href, mimeType: "text/x-roc", text: fs.readFileSync(ex.path, "utf-8") }],
      };
    }
  );

  // A documented package's page, the same text `get_roc_syntax(topic: <name>)` returns.
  server.registerResource(
    "roc-package-page",
    new ResourceTemplate("roc-syntax://package/{package}", {
      list: async () => ({
        resources: PACKAGE_DOCS.map((d) => ({
          uri: `roc-syntax://package/${d.name}`,
          name: `roc-package-${d.name}`,
          title: `${d.name} ${d.version}`,
          description: d.purpose,
          mimeType: "text/markdown",
        })),
      }),
      complete: {
        package: async (value) => PACKAGE_DOCS.map((d) => d.name).filter((n) => n.startsWith(value)),
      },
    }),
    {
      title: "Package Page",
      description: "What a documented package is for, its topics and examples, and whether this app pins it.",
      mimeType: "text/markdown",
    },
    async (uri, { package: pkg }) => {
      await ensureDetection();
      const doc = packageNamed(Array.isArray(pkg) ? pkg[0] : pkg);
      if (!doc) throw new Error(`Unknown package: ${pkg}. list_roc_index(kind: "scopes") lists them.`);
      return { contents: [{ uri: uri.href, mimeType: "text/markdown", text: packagePage(doc) }] };
    }
  );

  // A documented package's worked programs, filed apart from any platform's
  // because a package is not a scope.
  server.registerResource(
    "roc-package-example",
    new ResourceTemplate("roc-syntax://package/{package}/example/{name}", {
      list: async () => ({
        resources: PACKAGE_DOCS.flatMap((d) =>
          registry.packageExamples(d).map((ex) => ({
            uri: `roc-syntax://package/${d.name}/example/${ex.name}`,
            name: `roc-package-example-${d.name}-${ex.name}`,
            title: ex.name,
            description: ex.title,
            mimeType: "text/x-roc",
          }))
        ),
      }),
      complete: {
        package: async (value) =>
          PACKAGE_DOCS.filter((d) => registry.packageExamples(d).length > 0 && d.name.startsWith(value)).map(
            (d) => d.name
          ),
        name: async (value) =>
          PACKAGE_DOCS.flatMap((d) => registry.packageExamples(d).map((ex) => ex.name)).filter((n) =>
            n.startsWith(value.toLowerCase())
          ),
      },
    }),
    {
      title: "Package Example Program",
      description:
        "One complete, compiling program from a documented package's example set. list_roc_index with kind='examples' names them.",
      mimeType: "text/x-roc",
    },
    async (uri, { package: pkg, name }) => {
      const wanted = Array.isArray(name) ? name[0] : name;
      const doc = PACKAGE_DOCS.find((d) => d.name === (Array.isArray(pkg) ? pkg[0] : pkg));
      const ex = doc ? registry.packageExamples(doc).find((e) => e.name === wanted) : undefined;
      if (!ex) {
        throw new Error(
          `Unknown example: ${pkg}/${wanted}. Call list_roc_index with kind='examples' to see available programs.`
        );
      }
      return {
        contents: [{ uri: uri.href, mimeType: "text/x-roc", text: fs.readFileSync(ex.path, "utf-8") }],
      };
    }
  );

  // Upstream prose that a platform ships, bundled unchanged. The two
  // basic-webserver pages are the SSE contract and the benchmark method. Both
  // state facts that no signature states.
  server.registerResource(
    "roc-platform-doc",
    new ResourceTemplate("roc-syntax://platform/{platform}/doc/{name}", {
      list: async () => ({
        resources: SCOPES.flatMap((sc) =>
          registry.docs(sc).map((d) => ({
            uri: `roc-syntax://platform/${sc}/doc/${d.name}`,
            name: `roc-doc-${sc}-${d.name}`,
            title: d.name,
            description: d.title,
            mimeType: "text/markdown",
          }))
        ),
      }),
      complete: {
        platform: async (value) =>
          SCOPES.filter((sc) => registry.docs(sc).length > 0 && sc.startsWith(value)),
        name: async (value) =>
          SCOPES.flatMap((sc) => registry.docs(sc).map((d) => d.name)).filter((n) =>
            n.startsWith(value.toLowerCase())
          ),
      },
    }),
    {
      title: "Platform Documentation Page",
      description:
        "A prose page shipped by a platform, bundled unchanged from its pinned release. Use roc-syntax://platform/basic-webserver/doc/<name>, e.g. .../doc/sse. basic-cli ships no prose pages.",
      mimeType: "text/markdown",
    },
    async (uri, { platform, name }) => {
      const scope = (Array.isArray(platform) ? platform[0] : platform) as ScopeName;
      const wanted = Array.isArray(name) ? name[0] : name;
      const doc = (SCOPES as readonly string[]).includes(scope)
        ? registry.docs(scope).find((d) => d.name === wanted)
        : undefined;
      if (!doc) throw new Error(`Unknown doc page: ${platform}/${wanted}.`);
      return {
        contents: [
          { uri: uri.href, mimeType: "text/markdown", text: fs.readFileSync(doc.path, "utf-8") },
        ],
      };
    }
  );

  // -----------------------------------------------------------------------------
  // Start
  // -----------------------------------------------------------------------------

  // The client reports when the workspace moves. No other source can report it,
  // which is why detection also has a TTL.
  server.server.setNotificationHandler(
    "notifications/roots/list_changed",
    { params: z.any() },
    () => {
      detections.invalidate();
      detected = null;
      detecting = null;
    }
  );

  return server;
}
