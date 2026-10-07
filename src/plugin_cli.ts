// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The `plugin` subcommands of the CLI, in two groups:
// - The author commands (`init`, `index`, `validate`, `inspect`, `doctor`)
//   scaffold a plugin, index it, run the repo check scripts on it, show what
//   this host would index from it, and explain the plugin set that a configured
//   server would load. These commands open no network connection themselves,
//   but `index` and `validate` run `roc deps`, which can download releases.
//   Only `init` and `index` write, and only to the directory that they get.
// - The user commands `add`, `update`, `remove` and `list` manage the plugin
//   folder of this server. They change it through npm, or through Bun when the
//   CLI runs under Bun. `upgrade` updates the server, then runs `update` in the
//   new server.
//
// See "Authoring a plugin" in `docs/design/plugins.md`.

import * as fs from "node:fs";
import * as path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { LATEST_PROTOCOL_VERSION } from "@modelcontextprotocol/server";
import { INSTALLED, installDir, unresolvedFix, workspaceRoot } from "./plugins.ts";
import * as S from "./scopes.ts";
import type { LoadedPlugin, PackageProvider, PluginManifest } from "./scopes.ts";
import * as R from "./release.ts";
import { findRoc } from "./roc_bin.ts";

const ROOT = path.join(import.meta.dirname, "..");
/**
 * The argv to start the server that is next to this file, in this order:
 * 1. The built `.js` file, if a build made one.
 * 2. Else the `.ts` source under tsx, in a checkout.
 * 3. Else the `.ts` source under the type stripper that the bin uses. An
 *    install from git has only this loader.
 *
 * tsx comes before the stripper, as in scripts/tree.mjs, because the stripper
 * needs Node 22.15 and a checkout runs on Node 20.11.
 */
const SERVER_ARGV: string[] = (() => {
  const entry = import.meta.filename.replace(/plugin_cli\.([tj]s)$/, "index.$1");
  if (!entry.endsWith(".ts")) return [entry];
  let loader: string;
  try {
    loader = import.meta.resolve("tsx/esm");
  } catch {
    loader = new URL("../bin/strip-types.js", import.meta.url).href;
  }
  return ["--import", loader, entry];
})();

const reason = (err: unknown) => (err instanceof Error ? err.message : String(err));

/** The snapshot file that holds the releases of a plugin. */
const indexOf = (dir: string): string => path.join(dir, R.INDEX_FILE);

/** The estimate used throughout this repo: about 3.5 characters per token. */
const tokens = (s: string): number => Math.round(s.length / 3.5);

// -----------------------------------------------------------------------------
// What a command reports
// -----------------------------------------------------------------------------

export type Status = "ok" | "fail" | "skip";

/** The result of one check. A `skip` never fails a run. */
export interface Check {
  name: string;
  status: Status;
  detail?: string;
}

const ok = (name: string, detail?: string): Check => ({ name, status: "ok", detail });
const bad = (name: string, detail: string): Check => ({ name, status: "fail", detail });
const skip = (name: string, detail: string): Check => ({ name, status: "skip", detail });

export function render(checks: readonly Check[]): string {
  const mark = { ok: "ok  ", fail: "FAIL", skip: "skip" };
  return checks
    .map((c) => `${mark[c.status]}  ${c.name}${c.detail ? `\n${c.detail.replace(/^/gm, "      ")}` : ""}`)
    .join("\n");
}

export const failed = (checks: readonly Check[]): boolean => checks.some((c) => c.status === "fail");

// -----------------------------------------------------------------------------
// init
// -----------------------------------------------------------------------------

/**
 * A platform that this host bundles, so that the apps of a package skeleton pin
 * a release that exists. An author who writes for a different platform passes
 * `--platform=`, or replaces this URL in each app header of the skeleton.
 */
export const SKELETON_PLATFORM =
  "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/" +
  "AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst";

/**
 * The files that `init` writes for a package: the namespace that the package
 * serves, and the page and topics that document it. A package is not a scope.
 * An app gets the package when it pins the package, and search then returns
 * the package items together with the builtins.
 *
 * The manifest has the same shape as the manifest of a platform. The difference
 * is in the header of the release, which `plugin index` reads. A package has no
 * scaffold, because `roc_check` wraps code in a platform. The apps of a package
 * pin a platform for I/O, and pin the package next to it.
 */
export function packageSkeleton(
  name: string,
  repo: string,
  version: string,
  url: string,
  platform: string,
  pkg?: string
): Record<string, string> {
  const Mod = name
    .split(/[-_]/)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join("");
  const header = `app [main!] {\n\tpf: platform "${platform}",\n\t${name}: "${url}",\n}`;
  const manifest: PluginManifest = {
    schema: S.SCHEMA_VERSION,
    maintainer: repo.split("/")[0],
    compiler: S.BUNDLED_COMPILER,
    corpora: [
      {
        ...namedUnlessRepo(name, repo),
        // `search_roc_syntax` returns the overview for this name.
        release: url,
        description: `The ${name} package: one line, and it is what list_roc_index(kind: "scopes") shows.`,
        purpose: `what ${name} is for, in a few words`,
        overview: "overview.md",
        examples: "examples",
        checks: ["topics", "verify"],
        topics: [
          {
            name: `${name.replace(/-/g, "_")}_hello`,
            file: "topics/hello.roc",
            description: `What ${name} looks like: replace this with the first thing a reader has to know.`,
            keywords: [name, "hello", "start"],
          },
        ],
      },
    ],
  };
  return {
    "plugin.json": JSON.stringify(manifest, null, 2) + "\n",
    "package.json": packageJson(manifest, name, repo, pkg),
    "overview.md": `# ${name} ${version}\n\nWhat a model has to know before writing a line of ${name}, and nothing else.\nEvery fenced snippet here also lives in \`verify/overview-snippets.roc\`, so the\npage cannot drift from what compiles.\n\n## Hello\n\n\`\`\`roc\ngreeting = ${Mod}.greet("world")\n\`\`\`\n`,
    "examples/hello.roc": `## Hello, with ${name}.\n${header}\n\nimport pf.Stdout\nimport ${name}.${Mod}\n\nmain! = |_args| Stdout.line!(${Mod}.greet("world"))\n`,
    "topics/hello.roc": `## One subject, as a program that compiles. Its comments carry what the\n## compiler rejected while it was written.\n${header}\n\nimport pf.Stdout\nimport ${name}.${Mod}\n\nmain! = |_args| Stdout.line!(${Mod}.greet("world"))\n`,
    "verify/overview-snippets.roc": `## Every snippet the overview page shows, in one app, so the page cannot drift.\n${header}\n\nimport pf.Stdout\nimport ${name}.${Mod}\n\ngreeting = ${Mod}.greet("world")\n\nmain! = |_args| Stdout.line!(greeting)\n`,
  };
}

/** The name of a corpus defaults to the name of its repo, so the manifest has a `name` only when the two differ. */
const namedUnlessRepo = (name: string, repo: string): { name?: string } =>
  repo.split("/")[1] === name ? {} : { name };

/** What `init` writes, keyed by path relative to the plugin directory. */
export function skeleton(
  name: string,
  repo: string,
  version: string,
  url: string,
  pkg?: string
): Record<string, string> {
  const Mod = name
    .split(/[-_]/)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join("");
  const manifest: PluginManifest = {
    schema: S.SCHEMA_VERSION,
    // The repo owner, because a reader would contact the owner anyway. The
    // scope listing shows this value exactly as written, so a fork must change it.
    maintainer: repo.split("/")[0],
    compiler: S.BUNDLED_COMPILER,
    corpora: [
      {
        ...namedUnlessRepo(name, repo),
        // The version comes from this URL, and repo detection matches against it.
        release: url,
        description: `The ${name} platform: one line, and it is what list_roc_index(kind: "scopes") shows.`,
        // A few words, e.g. "games, graphics and sound", not a sentence. A
        // caller reads only this line when it chooses a platform to write for.
        purpose: `what a ${name} program is, in a few words`,
        overview: "overview.md",
        examples: "examples",
        scaffold: "scaffold.roc",
        sample: "sample.roc",
        checks: ["topics", "verify"],
        // The check scripts compile each program under `checks`, but the server
        // does not serve it. A `topics` entry makes the server serve one by name.
        topics: [
          {
            name: `${name.replace(/-/g, "_")}_hello`,
            file: "topics/hello.roc",
            description: `What ${name} looks like: replace this with the first thing a reader has to know.`,
            keywords: [name, "hello", "start"],
          },
        ],
      },
    ],
  };
  return {
    "plugin.json": JSON.stringify(manifest, null, 2) + "\n",
    "package.json": packageJson(manifest, name, repo, pkg),
    "overview.md": `# ${name}\n\nWhat a model has to know before writing a line of ${name}, and nothing else.\nEvery fenced snippet here also lives in \`verify/overview-snippets.roc\`, so the\npage cannot drift from what compiles.\n\n## Hello\n\n\`\`\`roc\n${Mod}.greet!("world")\n\`\`\`\n`,
    "examples/hello.roc": `## Hello, in ${name}.\napp [main!] { pf: platform "${url}" }\n\nimport pf.${Mod}\n\nmain! = |_args| Ok(${Mod}.greet!("world"))\n`,
    // `roc_check` reads only these two markers. Everything above `@user-code`
    // is the prelude. `roc_check` adds each `@default` definition only if the
    // submitted source does not declare that name.
    "scaffold.roc": `## The app roc_check wraps bare ${name} source in.\napp [main!] { pf: platform "${url}" }\n\nimport pf.${Mod}\n\n# @user-code\n\n# @default main!\nmain! = |_args| Ok({})\n`,
    "sample.roc": `main! : List(Str) => Try({}, _)\nmain! = |_args| Ok(${Mod}.greet!("world"))\n`,
    "topics/hello.roc": `## One subject, as a program that compiles. Its comments carry what the\n## compiler rejected while it was written.\napp [main!] { pf: platform "${url}" }\n\nimport pf.${Mod}\n\nmain! = |_args| Ok(${Mod}.greet!("world"))\n`,
    "verify/overview-snippets.roc": `## Every snippet the overview page shows, in one app, so the page cannot drift.\napp [main!] { pf: platform "${url}" }\n\nimport pf.${Mod}\n\nmain! = |_args|\n    ${Mod}.greet!("world")\n    Ok({})\n`,
  };
}

/**
 * The `package.json` of a plugin. It holds what a registry needs, and nothing
 * that this host reads.
 *
 * The function derives `files` from the manifest, so that no author writes it
 * by hand. If the tarball leaves out a corpus path, the plugin validates in the
 * checkout of the author but serves nothing after an install. The file never
 * has scripts. npm and bun block the install scripts of a package until the
 * user opts in, so a plugin that needs a script is incomplete for each user who
 * did not opt in.
 *
 * `pkg` names the package when the author is not the publisher of the
 * platform, which is the usual case. `repo` must be the repository that the app
 * header pins. If the npm scope defaulted to the owner of that repo, a curator
 * would publish under the npm name of a different person.
 */
export function packageJson(manifest: PluginManifest, name: string, repo: string, pkg?: string): string {
  const owner = repo.split("/")[0];
  return (
    JSON.stringify(
      {
        name: pkg ?? `@${owner}/${name}`,
        version: "0.1.0",
        description: manifest.corpora[0]?.description ?? `Roc corpus for ${name}, for roc-syntax-mcp`,
        license: "MIT",
        files: ["plugin.json", ...new Set(S.manifestPaths(manifest))].sort(),
        keywords: ["roc", "roc-syntax-mcp", "roc-syntax-mcp-plugin", name],
        // npm publishes a scoped package as private by default, and nobody can
        // install a private corpus.
        publishConfig: { access: "public" },
      },
      null,
      2
    ) + "\n"
  );
}

export function init(
  dir: string,
  opts: {
    name?: string;
    repo?: string;
    version?: string;
    url?: string;
    package?: string;
    kind?: string;
    platform?: string;
  }
): Check[] {
  const name = opts.name ?? path.basename(path.resolve(dir));
  const repo = opts.repo ?? `you/${name}`;
  const version = opts.version ?? "0.1.0";
  const kind = opts.kind ?? "platform";
  if (kind !== "platform" && kind !== "package") {
    return [bad("init", `--kind must be platform or package, got ${kind}`)];
  }
  // A placeholder, not a guess. The tarball name is a content hash, so this
  // code cannot derive it. `validate` fails while the placeholder is in place.
  const url =
    opts.url ?? `https://github.com/${repo}/releases/download/${version}/REPLACE_WITH_THE_TARBALL.tar.zst`;
  if (fs.existsSync(path.join(dir, "plugin.json"))) {
    return [bad("init", `${dir} already holds a plugin.json`)];
  }
  const files =
    kind === "package"
      ? packageSkeleton(name, repo, version, url, opts.platform ?? SKELETON_PLATFORM, opts.package)
      : skeleton(name, repo, version, url, opts.package);
  for (const [rel, content] of Object.entries(files)) {
    const file = path.join(dir, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content);
  }
  // `init` writes no Roc source of the release. After the author sets the real
  // URL, `plugin index` reads the modules from the release.
  const where = kind === "package" ? "examples/, topics/ and verify/" : "scaffold.roc, examples/, topics/ and verify/";
  const next =
    `Put the release's real tarball URL in plugin.json and in ${where}, then run\n` +
    `  roc-syntax-mcp plugin index ${dir}\n` +
    `  roc-syntax-mcp plugin validate ${dir}`;
  return [ok("init", Object.keys(files).sort().join("\n")), ok("next", next)];
}

// -----------------------------------------------------------------------------
// validate
// -----------------------------------------------------------------------------

/**
 * The token ceiling for one overview page. The pages of this host are 1500 to
 * 2000 tokens, and `roc_overview` returns a page whole. A page above this
 * ceiling is a full document.
 *
 * A platform page holds more than a package page. It tells how to start and
 * run a project, and what shape its programs have. A reader needs this before
 * the first line and cannot get it from the index. The roc-ray page is 3700
 * tokens with this content and 2100 tokens without it, and the extra tokens
 * were worth their cost.
 */
export const OVERVIEW_CEILING = 4000;

/**
 * The manifest, read and resolved, or the reason that the read failed.
 * `loaded` is null while a release that the manifest names is not in the
 * index. The kind of each corpus comes from the header of its release, so no
 * check that depends on the kind can run yet.
 */
function load(dir: string): { loaded: LoadedPlugin | null; manifest: PluginManifest } | string {
  let raw: unknown;
  try {
    raw = JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8"));
    return { loaded: S.fromManifest(dir, raw), manifest: raw as PluginManifest };
  } catch (err) {
    if (err instanceof S.UnindexedRelease) return { loaded: null, manifest: raw as PluginManifest };
    return reason(err);
  }
}

/** Every program under the `checks` directories of a manifest, by absolute path. */
function checkedPrograms(dir: string, manifest: PluginManifest): string[] {
  const dirs = new Set(manifest.corpora.flatMap((c) => c.checks ?? []).map((sub) => path.resolve(dir, sub)));
  return [...dirs].flatMap((abs) => {
    try {
      return fs.readdirSync(abs).filter((f) => f.endsWith(".roc")).map((f) => path.join(abs, f));
    } catch {
      return [];
    }
  });
}

/**
 * Which programs of a plugin the server serves by name, and whether a check
 * script compiles each one.
 *
 * The check scripts compile each `checks` directory, but the server serves none
 * of those programs. A topic declaration makes one of those programs available
 * by name. A served topic that no check script compiles is a defect, because
 * no check finds out when that program stops compiling.
 */
function topicChecks(dir: string, manifest: PluginManifest): Check[] {
  const compiled = new Set(checkedPrograms(dir, manifest));
  const topics = manifest.corpora.flatMap((c) => c.topics ?? []);
  if (topics.length === 0 && compiled.size === 0) return [];
  const ungated = topics.filter((t) => !compiled.has(path.resolve(dir, t.file)));
  if (ungated.length > 0) {
    return [
      bad("topics", `served and compiled by no gate: ${ungated.map((t) => t.name).join(", ")}`),
    ];
  }
  const unserved = compiled.size - topics.length;
  return [
    ok(
      "topics",
      `${topics.length} served by name` +
        (unserved > 0 ? `, ${unserved} more compiled and reachable only as a file` : "")
    ),
  ];
}

/** Every check that reads only the plugin directory. These checks run no compiler and spawn no process. */
export function staticChecks(dir: string): Check[] {
  const read = load(dir);
  if (typeof read === "string") return [bad("manifest", read)];
  const { loaded, manifest } = read;
  const rows = loaded ? corpusRows(loaded) : [`${manifest.corpora.length} corpora, not indexed yet`];
  const out: Check[] = [ok("manifest", `v${manifest.schema}\n${rows.join("\n")}`)];
  // A missing maintainer fails, but a missing value in every other optional
  // field is only reported. The loader serves a corpus with no maintainer. But
  // a published corpus makes claims that this server cannot check, and those
  // claims must carry the name of a person.
  out.push(
    manifest.maintainer
      ? ok("maintainer", manifest.maintainer)
      : bad("maintainer", "nobody is named, and the scope listing will say so")
  );

  const declared = [...new Set(S.manifestPaths(manifest))];
  const escaping: string[] = [];
  const missing: string[] = [];
  for (const rel of declared) {
    if (path.relative(dir, path.resolve(dir, rel)).startsWith("..")) escaping.push(rel);
    // The `index` check reports a missing index file, with the command to fix it.
    else if (!fs.existsSync(path.resolve(dir, rel)) && rel !== R.INDEX_FILE) missing.push(rel);
  }
  if (escaping.length > 0) {
    out.push(bad("paths", `outside the plugin, so this host will not read it: ${escaping.join(", ")}`));
  } else if (missing.length > 0) {
    out.push(bad("paths", `declared and not there: ${missing.join(", ")}`));
  } else {
    out.push(ok("paths", `${declared.length} declared, all inside the plugin`));
  }

  out.push(...packagingChecks(dir, manifest));
  out.push(...indexChecks(dir, manifest));
  // The kind of each corpus comes from the header of its release. Thus these
  // checks run only when the index exists. The `index` check above names the
  // command that writes the index.
  if (loaded) {
    out.push(...nameChecks(loaded, manifest));
    out.push(...corpusChecks(dir, loaded));
    out.push(...packageChecks(loaded));
  }
  out.push(...topicChecks(dir, manifest));
  for (const c of manifest.corpora) out.push(...overviewChecks(dir, manifest, c));
  if (manifest.compiler && manifest.compiler !== S.BUNDLED_COMPILER) {
    // Reported, never failed. The end user decides if a plugin is stale, and a
    // host update must not make an install invalid.
    out.push(ok("compiler", `built against ${manifest.compiler}, this host bundles ${S.BUNDLED_COMPILER}`));
  }
  return out;
}

/** Checks each name that a plugin claims, and the `purpose` of each platform. */
function nameChecks(loaded: LoadedPlugin, manifest: PluginManifest): Check[] {
  const out: Check[] = [];
  const names = S.loadedNames(loaded);
  for (const name of names) {
    if (S.RESERVED_SCOPES.has(name)) {
      out.push(bad("name", `${name} is reserved: it names the language reference or the standard library`));
    } else if (S.CORE.scopes.includes(name) || S.CORE.packageDocs.some((d) => d.name === name)) {
      out.push(bad("name", `${name} is already a name this server ships, and the host's copy wins`));
    } else {
      out.push(ok("name", name));
    }
  }
  if (names.length === 0) out.push(ok("name", "nothing to address: this plugin serves package namespaces only"));

  // Only a platform needs a `purpose`. Nobody writes a program on a package, so
  // a package is not in the list of platforms that a caller chooses from.
  for (const def of loaded.defs) {
    const declared = manifest.corpora.find((c) => c.release === def.modules[0]?.release)?.purpose;
    out.push(
      declared
        ? ok("purpose", `${def.name}: ${declared}`)
        : bad(
            "purpose",
            `${def.name}: not declared, so the list a caller picks a platform from prints its ` +
              "whole description where every other line is a few words"
          )
    );
  }
  return out;
}

/**
 * Whether `index.json` holds every release that the manifest names. This check
 * reads only local files. The online `index current` check compares each
 * snapshot with its release.
 */
function indexChecks(dir: string, manifest: PluginManifest): Check[] {
  const releases = R.manifestReleases(manifest);
  if (releases.length === 0) return [];
  const held = S.readIndexFiles([indexOf(dir)]);
  const absent = releases.filter((url) => !held.has(R.releaseHash(url) ?? ""));
  return [
    absent.length > 0
      ? bad("index", `no snapshot of ${absent.join(", ")}. Run: roc-syntax-mcp plugin index ${dir}`)
      : ok("index", `${releases.length} release(s) indexed`),
  ];
}

/**
 * Whether each snapshot matches what its release parses to today. Needs the
 * compiler only if a release is not in the cache.
 */
async function indexGate(dir: string): Promise<Check> {
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, "plugin.json"), "utf-8"));
  const roc = process.env.ROC || "roc";
  const uncached = R.manifestReleases(manifest).filter((url) => !R.cachedReleaseDir(url));
  if (uncached.length > 0 && !R.rocRuns(roc)) return skip("index current", "no roc to fetch the releases with");
  const { status, missing } = await R.indexManifestDir(dir, { check: true, roc });
  if (missing.length > 0) return bad("index current", `roc deps could not fetch ${missing.join(", ")}`);
  if (status === "stale") return bad("index current", `differs from its release. Run: roc-syntax-mcp plugin index ${dir}`);
  return ok("index current", status === "none" ? "no release named" : "matches every release");
}

/** The npm scripts that run at install. npm and Bun run them only if the user allows it, so a plugin must not need one. */
const INSTALL_HOOKS = ["preinstall", "install", "postinstall", "prepare"];

/**
 * Checks the `package.json` of a plugin, if it has one. Nobody packs a plugin
 * that is declared by path, so a directory with no package.json passes.
 *
 * These checks find a failure that shows only after publishing. A corpus path
 * outside `files` validates in the checkout of the author, but is missing from
 * the tarball that the user installs.
 */
function packagingChecks(dir: string, manifest: PluginManifest): Check[] {
  const file = path.join(dir, "package.json");
  if (!fs.existsSync(file)) {
    return [ok("package", "none, so this plugin is declared by path rather than installed")];
  }
  let pkg: { name?: string; version?: string; files?: string[]; scripts?: Record<string, string> };
  try {
    pkg = JSON.parse(fs.readFileSync(file, "utf-8"));
  } catch (err) {
    return [bad("package", reason(err))];
  }
  const out: Check[] = [
    pkg.name && pkg.version
      ? ok("package", `${pkg.name} ${pkg.version}`)
      : bad("package", "a registry needs both a name and a version"),
  ];

  const hooks = INSTALL_HOOKS.filter((h) => pkg.scripts?.[h]);
  out.push(
    hooks.length > 0
      ? bad("install", `${hooks.join(", ")} would have to run, and both npm and bun block install scripts`)
      : ok("install", "nothing runs on install")
  );

  const needed = ["plugin.json", ...S.manifestPaths(manifest)];
  if (!Array.isArray(pkg.files)) {
    out.push(ok("tarball", "no files list, so everything not ignored is packed"));
  } else {
    const packed = pkg.files.map((f) => f.replace(/^\.\//, "").replace(/\/+$/, ""));
    const absent = needed.filter(
      (rel) => !packed.some((f) => f === rel || rel.startsWith(`${f}/`))
    );
    out.push(
      absent.length > 0
        ? bad("tarball", `declared by the manifest and not packed: ${absent.join(", ")}`)
        : ok("tarball", `${needed.length} declared paths, all packed`)
    );
  }
  return out;
}

/** One line per corpus that tells its kind, in the same words that `inspect` uses. */
function corpusRows(loaded: LoadedPlugin): string[] {
  // A package with a description has a page and topics, not only a namespace.
  // The row says "documented package", so the author can see that the server
  // uses their prose.
  return [
    ...loaded.defs.map((d) => `${d.name}${d.version ? ` ${d.version}, platform` : ""}`),
    ...loaded.providers.map((p) => {
      const doc = loaded.docs.find((d) => d.id === p.id);
      return doc ? `${doc.name} ${p.version}, documented package` : `${p.id} ${p.version}, signatures only`;
    }),
  ];
}

function corpusChecks(dir: string, loaded: LoadedPlugin): Check[] {
  const out: Check[] = [];
  for (const def of loaded.defs) out.push(...corpusCheck(dir, loaded, def.name, (reg) => reg.index(def.name)));
  for (const doc of loaded.docs) out.push(...corpusCheck(dir, loaded, doc.name, (reg) => reg.packageIndex(doc)));
  return out;
}

/** What one scope or documented package parses to, and whether a namespace claims a name twice. */
function corpusCheck(
  dir: string,
  loaded: LoadedPlugin,
  name: string,
  read: (reg: InstanceType<typeof S.ScopeRegistry>) => ReturnType<InstanceType<typeof S.ScopeRegistry>["index"]>
): Check[] {
  const reg = new S.ScopeRegistry(dir, {
    providers: loaded.providers,
    defs: Object.fromEntries(loaded.defs.map((d) => [d.name, d])),
    indexFiles: [indexOf(dir)],
  });
  let idx;
  try {
    idx = read(reg);
  } catch (err) {
    return [bad("corpus", `${name}: ${reason(err)}`)];
  }
  if (idx.items.length === 0) return [bad("corpus", `${name} parsed to no items at all`)];
  const byTier = new Map<string, number>();
  for (const i of idx.items) byTier.set(i.tier, (byTier.get(i.tier) ?? 0) + 1);
  const out: Check[] = [
    ok(
      "corpus",
      `${name}: ${idx.items.length} items in ${idx.modulePaths.size} modules: ` +
        [...byTier].sort().map(([t, n]) => `${n} ${t}`).join(", ")
    ),
  ];

  // If one namespace claims a name twice, the parser has a gap. This is not a
  // valid collision, because an app cannot write which of the two items it means.
  const claims = new Map<string, number>();
  for (const i of idx.items) {
    const key = `${i.ns} ${i.fullName}`;
    claims.set(key, (claims.get(key) ?? 0) + 1);
  }
  const doubled = [...claims].filter(([, n]) => n > 1).map(([k]) => k.split(" ")[1]);
  out.push(
    doubled.length > 0
      ? bad("duplicates", `${name}: claimed twice inside one namespace: ${doubled.slice(0, 10).join(", ")}`)
      : ok("duplicates", `${name}: no name is claimed twice inside one namespace`)
  );

  // Across namespaces, a collision is valid. `http.Request` and `pf.Request`
  // both exist, and the alias in the app selects one. The check reports the
  // count, because one lookup returns both items.
  const nonPlatform = S.CORE.scopes.filter((s) => !S.CORE.scopeDefs[s].version);
  const host = new S.ScopeRegistry(ROOT);
  const hostNames = new Set(nonPlatform.flatMap((s) => host.index(s).items.map((i) => i.fullName)));
  const shared = new Set(idx.items.filter((i) => hostNames.has(i.fullName)).map((i) => i.fullName));
  out.push(
    ok(
      "collisions",
      `${name}: ${idx.collisions.size} across this plugin's own namespaces, ` +
        `${shared.size} also claimed by ${nonPlatform.join(" or ")}`
    )
  );
  return out;
}

/**
 * Which packages of this plugin cross the exposed API of a bundled platform.
 * For such a package, a release other than the pin of the platform would
 * describe an app that nobody can write.
 */
function packageChecks(loaded: LoadedPlugin): Check[] {
  if (loaded.providers.length === 0) return [];
  const reg = new S.ScopeRegistry(ROOT, { providers: loaded.providers, indexFiles: [indexOf(loaded.dir)] });
  const lines: string[] = [];
  let refused = 0;
  for (const provider of loaded.providers) {
    let declared = false;
    for (const platform of S.CORE.platformScopes) {
      const r = reg.packages(platform).find((res) => res.id === provider.id);
      if (!r) continue;
      declared = true;
      const won = r.provider?.from === provider.from && r.provider?.version === provider.version;
      if (!won) refused++;
      const why = won
        ? "this plugin serves it"
        : `refused: ${platform} requires ${r.required}, and ${r.crossing.join(", ")} carry it across the API`;
      lines.push(`${provider.id} ${provider.version} under ${platform}: ${why}`);
    }
    if (!declared) {
      lines.push(`${provider.id} ${provider.version}: no bundled platform declares it, so none refuses it`);
    }
  }
  // Reported, not failed. A release that no bundled platform accepts is still
  // correct for the platform that its author targets.
  return [ok(refused > 0 ? "packages (refused here)" : "packages", lines.join("\n"))];
}

/** Fenced Roc blocks on a page, trimmed, in the order they appear. */
export function snippets(markdown: string): string[] {
  return [...markdown.matchAll(/```roc\n([\s\S]*?)```/g)].map((m) => m[1].trim()).filter(Boolean);
}

/**
 * Checks the overview page of one corpus: its size, and whether every snippet
 * on it compiles. Any program that the plugin compiles counts. Thus one app can
 * verify the snippets of a platform and of the package that its examples use.
 */
function overviewChecks(dir: string, manifest: PluginManifest, corpus: PluginManifest["corpora"][number]): Check[] {
  if (!corpus.overview) return [];
  const name = corpus.name ?? corpus.release?.match(/github\.com\/[^/]+\/([^/]+)\//)?.[1] ?? corpus.overview;
  let page: string;
  try {
    page = fs.readFileSync(path.resolve(dir, corpus.overview), "utf-8");
  } catch (err) {
    return [bad("overview", `${name}: ${reason(err)}`)];
  }
  const cost = tokens(page);
  const out: Check[] = [
    cost > OVERVIEW_CEILING
      ? bad("overview", `${name}: ~${cost} tokens, ceiling is ${OVERVIEW_CEILING}. roc_overview returns it whole`)
      : ok("overview", `${name}: ~${cost} tokens, ceiling is ${OVERVIEW_CEILING}`),
  ];

  const blocks = snippets(page);
  if (blocks.length === 0) return out;
  const apps = checkedPrograms(dir, manifest).map((f) => fs.readFileSync(f, "utf-8"));
  if (apps.length === 0) {
    return [
      ...out,
      bad("snippets", `${name}: ${blocks.length} on the page, and no app under checks: to compile them in`),
    ];
  }
  // Compare line by line, not block by block. A page can show a fragment, and
  // the app shows the same lines in a context that compiles.

  const body = apps.join("\n");
  const absent = blocks.filter((b) => !b.split("\n").every((l) => body.includes(l.trim())));
  return [
    ...out,
    absent.length > 0
      ? bad(
          "snippets",
          `${name}: ${absent.length} of ${blocks.length} are in no app the gate compiles:\n${absent.join("\n\n")}`
        )
      : ok("snippets", `${name}: all ${blocks.length} appear in an app the gate compiles`),
  ];
}

// -----------------------------------------------------------------------------
// What a spawned server says
// -----------------------------------------------------------------------------

/** One `tools/list` from a server launched with `argv`. */
function toolsList(argv: readonly string[]): Promise<unknown[]> {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [...SERVER_ARGV, ...argv], {
      cwd: ROOT,
      // Clear the workspace and plugin settings of the environment, so that the
      // measurement includes only the declared plugin.
      env: { ...process.env, ROC_MCP_PLUGINS: "", ROC_MCP_HOME: path.join(ROOT, "no-plugin-home"), CLAUDE_PROJECT_DIR: "" },
      stdio: ["pipe", "pipe", "ignore"],
    });
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error("the server did not answer tools/list within 30s"));
    }, 30_000);
    const send = (m: unknown) => child.stdin.write(JSON.stringify(m) + "\n");
    send({
      jsonrpc: "2.0",
      id: 0,
      method: "initialize",
      params: {
        protocolVersion: LATEST_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: { name: "plugin-validate", version: "1.0.0" },
      },
    });
    let buf = "";
    child.stdout.on("data", (chunk) => {
      buf += chunk;
      const lines = buf.split("\n");
      buf = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.trim()) continue;
        const msg = JSON.parse(line);
        if (msg.id === 0) {
          send({ jsonrpc: "2.0", method: "notifications/initialized" });
          send({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} });
        } else if (msg.id === 1) {
          clearTimeout(timer);
          child.kill();
          resolve(msg.result.tools);
        }
      }
    });
    child.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
    // Reject if the server exits before it answers, so that a crash does not
    // count as zero growth.
    child.on("close", (code) => {
      clearTimeout(timer);
      reject(new Error(`the server exited (${code}) before answering tools/list`));
    });
  });
}

interface ListedTool {
  name: string;
  description: string;
  inputSchema: { properties?: { scope?: { enum?: unknown } } };
}

/**
 * The tokens that this plugin adds to each tool in `tools/list`, for each user
 * who installs it.
 *
 * The check compares two servers, one with the plugin and one without it. It
 * does not derive the cost from the manifest, so it also shows growth that
 * nobody predicted. The server limits the growth of each tool to
 * `PLUGIN_TOOL_GROWTH` tokens for all plugins together. Thus this check fails
 * only if this plugin alone does not fit. In that case, a tool replaces part of
 * the plugin with a pointer to `list_roc_index`, even with no other plugin
 * installed.
 */
export async function budgetCheck(dir: string): Promise<Check> {
  let before: ListedTool[];
  let after: ListedTool[];
  try {
    [before, after] = (await Promise.all([toolsList([]), toolsList([`--plugin=${dir}`])])) as ListedTool[][];
  } catch (err) {
    return skip("budget", reason(err));
  }
  const rows = after.map((tool) => {
    const was = before.find((t) => t.name === tool.name)!;
    const cut =
      (/ more topics: list_roc_index/.test(tool.description) && !/ more topics: list_roc_index/.test(was.description)) ||
      (was.inputSchema.properties?.scope?.enum !== undefined && tool.inputSchema.properties?.scope?.enum === undefined);
    return { name: tool.name, delta: tokens(JSON.stringify(tool)) - tokens(JSON.stringify(was)), cut };
  });
  const grown = rows.filter((r) => r.delta !== 0 || r.cut).sort((a, b) => b.delta - a.delta);
  // A delta can be negative, because a declared platform removes the pointer that a server with no plugins prints.
  const signed = (n: number) => (n > 0 ? `+${n}` : `${n}`);
  const lines = grown.map((r) => `${r.name.padEnd(26)} ${signed(r.delta)}${r.cut ? ", over the ceiling" : ""}`);
  const detail = `${lines.length > 0 ? lines.join("\n") : "no tool grows"}\nceiling is ${S.PLUGIN_TOOL_GROWTH} tokens per tool, for every plugin together`;
  return grown.some((r) => r.cut) ? bad("budget", detail) : ok("budget", detail);
}

/** Runs one repo check script on the plugin. Returns `skip` if no compiler is installed. */
function gate(name: string, argv: readonly string[]): Check {
  const run = spawnSync(argv[0], argv.slice(1), {
    cwd: ROOT,
    encoding: "utf-8",
    maxBuffer: 32 * 1024 * 1024,
  });
  if (run.error) return skip(name, reason(run.error));
  // Both scripts that use roc exit with 2 if no compiler is on PATH. Report a
  // skip, because the check did not run.
  if (run.status === 2) return skip(name, `${run.stderr || run.stdout}`.trim());
  // On a pass, the last line of the script output is the summary. On a
  // failure, the author must read all of stdout and stderr.
  const summary = `${run.stdout ?? ""}`.trim().split("\n").filter(Boolean).at(-1);
  return run.status === 0 ? ok(name, summary) : bad(name, `${run.stdout ?? ""}${run.stderr ?? ""}`.trim());
}

export async function validate(dir: string, opts: { offline?: boolean } = {}): Promise<Check[]> {
  const out = staticChecks(dir);
  if (opts.offline) return out;
  out.push(await indexGate(dir));
  out.push(await budgetCheck(dir));
  out.push(gate("roc check", [path.join(ROOT, "scripts", "check-platform-examples.sh"), dir]));
  out.push(
    gate("roc_check", [process.execPath, path.join(ROOT, "scripts", "check-roc-check.mjs"), `--plugin=${dir}`])
  );
  return out;
}

// -----------------------------------------------------------------------------
// inspect
// -----------------------------------------------------------------------------

const providerRow = (p: PackageProvider): string => `${p.id} ${p.version} (tier ${p.tier}, from ${p.from})`;

/** What this host would index from a plugin, without installing it. */
export function inspect(dir: string): string {
  const read = load(dir);
  if (typeof read === "string") return `${dir}: ${read}\n`;
  const { loaded, manifest } = read;
  if (!loaded) return `${dir}: not indexed yet. Run: roc-syntax-mcp plugin index ${dir}\n`;
  const lines: string[] = [dir, ""];
  lines.push(`manifest   v${manifest.schema}`);
  lines.push(`maintainer ${manifest.maintainer ?? "not named, and the scope listing will say so"}`);
  lines.push(`compiler   ${manifest.compiler ?? "unstated"} (this host bundles ${S.BUNDLED_COMPILER})`);
  lines.push("corpora", ...corpusRows(loaded).map((r) => `  ${r}`));
  const reg = new S.ScopeRegistry(dir, {
    providers: loaded.providers,
    defs: Object.fromEntries(loaded.defs.map((d) => [d.name, d])),
    indexFiles: [indexOf(dir)],
  });

  for (const doc of loaded.docs) {
    const idx = reg.packageIndex(doc);
    lines.push("", `package ${doc.name}, ${doc.id} ${doc.version}`);
    lines.push(`  ${"modules".padEnd(26)} ${idx.modulePaths.size}`);
    const byTier = new Map<string, number>();
    for (const i of idx.items) byTier.set(i.tier, (byTier.get(i.tier) ?? 0) + 1);
    for (const [tier, n] of [...byTier].sort()) lines.push(`  ${tier.padEnd(26)} ${n} items`);
    lines.push("", `page       search_roc_syntax("${doc.name}")${doc.overview ? "" : ", from the description alone"}`);
    if (doc.topics?.length) {
      lines.push("", "topics served by name");
      for (const t of doc.topics) lines.push(`  ${t.name.padEnd(26)} ${t.description}`);
    }
  }

  for (const def of loaded.defs) {
    const idx = reg.index(def.name);
    lines.push("", `scope ${def.name}`);
    const byNs = new Map<string, number>();
    for (const i of idx.items) byNs.set(i.ns, (byNs.get(i.ns) ?? 0) + 1);
    for (const [ns, n] of byNs) lines.push(`  ${ns.padEnd(26)} ${n} items`);
    lines.push(`  ${"modules".padEnd(26)} ${idx.modulePaths.size}`);
    const byTier = new Map<string, number>();
    for (const i of idx.items) byTier.set(i.tier, (byTier.get(i.tier) ?? 0) + 1);
    for (const [tier, n] of [...byTier].sort()) lines.push(`  ${tier.padEnd(26)} ${n} items`);

    // List the names, not a count. A caller gets a topic by its name, so the
    // author must see the names.
    if (def.topics?.length) {
      lines.push("", "topics served by name");
      for (const t of def.topics) lines.push(`  ${t.name.padEnd(26)} ${t.description}`);
    }

    // The pins in the header of the platform. An app must match them.
    const pins = reg.packages(def.name);
    if (pins.length > 0) {
      lines.push("", "pinned by its own header");
      for (const r of pins) {
        const who = r.provider ? `served by ${r.provider.from} ${r.provider.version}` : "no provider";
        const cross = r.crossing.length > 0 ? `crosses ${r.crossing.join(", ")}` : "crosses nothing";
        lines.push(`  ${r.id.padEnd(26)} ${r.required}, ${cross}, ${who}`);
      }
    }
  }

  if (loaded.providers.length > 0) {
    lines.push("", "provides");
    for (const p of loaded.providers) lines.push(`  ${providerRow(p)}`);
    lines.push("", "against the platforms this host ships");
    const reg = new S.ScopeRegistry(ROOT, { providers: loaded.providers, indexFiles: [indexOf(dir)] });
    for (const platform of S.CORE.platformScopes) {
      for (const r of reg.packages(platform)) {
        const mine = loaded.providers.find((p) => p.id === r.id);
        if (!mine) continue;
        const won = r.provider?.from === mine.from && r.provider?.version === mine.version;
        lines.push(
          `  ${platform.padEnd(18)} ${r.id} needs ${r.required}, ` +
            (won
              ? "this plugin serves it"
              : `refused: ${r.refused.map((f) => `${f.from} ${f.version}`).join(", ")}`)
        );
      }
    }
  }
  return lines.join("\n") + "\n";
}

// -----------------------------------------------------------------------------
// doctor
// -----------------------------------------------------------------------------

/** What a loaded plugin serves, one line for each item. */
function served(loaded: LoadedPlugin): string[] {
  const out = [
    ...loaded.defs.map((def) => `scope ${def.name}`),
    ...loaded.docs.map((doc) => `package ${doc.name}, read as search_roc_syntax("${doc.name}")`),
  ];
  const bare = loaded.providers.length - loaded.docs.length;
  if (bare > 0) out.push(`${bare} package namespace(s), signatures only`);
  return out;
}

/**
 * The plugin set that a server started here would load, and the result for
 * each declaration.
 *
 * This function reads the declarations through the same function that server
 * startup calls. Thus the output always matches what startup does.
 */
export function doctor(
  argv: readonly string[],
  env: NodeJS.ProcessEnv,
  workspace: string
): Check[] {
  const outcomes = S.inspectDeclarations(argv, env, workspace);
  const out: Check[] = [];
  if (outcomes.length === 0) {
    out.push(ok("declared", "nothing. This server serves only what it ships"));
  }
  for (const d of outcomes) {
    const where = `${d.spec} (${d.source})`;
    if (d.loaded) {
      out.push(ok(where, `${d.dir}\n${served(d.loaded).join("\n")}`));
    } else if (d.dir === null) {
      out.push(bad(where, `resolves to nothing: ${d.problem}\nThe server serves everything else. ${unresolvedFix(d)}`));
    } else {
      out.push(bad(where, `${d.dir}\nnot served: ${d.problem}`));
    }
  }

  // Only the configuration sets a force, so this code reads the flag and the
  // environment, not a manifest. The check fails for an id that names no
  // namespace. The operator wrote the id to change a resolution, and a typo
  // would otherwise change nothing and show no cause.
  const forced = S.inspectForced(argv, env);
  if (forced.length > 0) {
    const rows = forced.map((f) => `${f.spec} (${f.source})${f.problem ? `: ${f.problem}` : ""}`).join("\n");
    const broken = forced.filter((f) => f.problem);
    out.push(
      broken.length > 0
        ? bad("forced", `${rows}\n\n${broken.length} that name no namespace, and are ignored`)
        : ok("forced", `${rows}\n\nThese namespaces accept a release that differs from the platform's pin`)
    );
  }

  // The resolution table: the registry chooses one provider for each namespace
  // in each space, one time.
  const providers = outcomes.flatMap((d) => d.loaded?.providers ?? []);
  const defs = Object.fromEntries(
    outcomes.flatMap((d) => (d.loaded?.defs ?? []).map((def) => [def.name, def] as const))
  );
  const reg = new S.ScopeRegistry(ROOT, {
    providers,
    defs,
    force: forced.filter((f) => !f.problem).map((f) => f.spec),
    indexFiles: outcomes.flatMap((d) => (d.loaded ? [indexOf(d.loaded.dir)] : [])),
  });
  const platforms = [...S.CORE.platformScopes, ...Object.keys(defs).filter((n) => defs[n].version)];
  const rows: string[] = [];
  let empty = 0;
  for (const platform of platforms) {
    for (const r of reg.packages(platform)) {
      if (!r.provider) empty++;
      const who = r.provider
        ? `${r.provider.from} ${r.provider.version} (tier ${r.provider.tier})` +
          (r.forced && r.provider.version !== r.required ? " FORCED" : "")
        : "NOTHING";
      rows.push(`${platform.padEnd(18)} ${r.ns.padEnd(22)} ${r.required.padEnd(10)} ${who}`);
    }
  }
  if (rows.length === 0) {
    out.push(ok("resolution", "no platform in this configuration pins a package"));
    return out;
  }
  const table = `${"space".padEnd(18)} ${"namespace".padEnd(22)} ${"required".padEnd(10)} served by\n${rows.join("\n")}`;
  // A namespace with no provider is the conflict that an operator runs `doctor`
  // to find. Every lookup into that namespace returns no items, only a note.
  out.push(
    empty > 0
      ? bad("resolution", `${table}\n\n${empty} namespace(s) with no compatible provider`)
      : ok("resolution", table)
  );
  return out;
}

// -----------------------------------------------------------------------------
// Installing, for every workspace
// -----------------------------------------------------------------------------

/** The files that an install changes. `add` saves them, so that it can undo a refused install. */
const INSTALL_STATE = ["package.json", "package-lock.json", "bun.lock", "bun.lockb"];

/**
 * The command that changes the install folder. The command uses npm under Node
 * and Bun under Bun. Thus the machine needs no other tool, and the registry,
 * login and proxy settings of the user apply. No install script runs, because
 * a plugin ships no code. A package that needs an install script is not a
 * plugin.
 */
function installer(dir: string, verb: "add" | "remove" | "sync", specs: readonly string[]): string[] {
  if (process.versions.bun) {
    // Bun reuses a cached version list. Without `--no-cache`, a second `add`
    // keeps the first installed version and does not find a newer release.
    const fresh = verb === "add" ? ["--no-cache"] : [];
    return [process.execPath, { add: "add", remove: "remove", sync: "install" }[verb], "--cwd", dir, "--ignore-scripts", ...fresh, ...specs];
  }
  const npm = { add: "install", remove: "uninstall", sync: "install" }[verb];
  return ["npm", npm, "--prefix", dir, "--ignore-scripts", "--no-audit", "--no-fund", ...specs];
}

/**
 * Quotes one argument for cmd.exe. The shell joins its arguments with spaces,
 * and the plugin folder is in the user profile, which often has a space in its
 * path.
 */
export const quoteForCmd = (arg: string): string => (/[\s"&|<>^()]/.test(arg) ? `"${arg.replace(/"/g, '""')}"` : arg);

/** Runs a command. Returns null if it passed, else an error message with its output. */
function run(cmd: readonly string[], env: NodeJS.ProcessEnv): string | null {
  // npm is `npm.cmd` on Windows, which only a shell finds.
  const win = process.platform === "win32";
  const args = win ? cmd.map(quoteForCmd) : cmd;
  const r = spawnSync(args[0], args.slice(1), { encoding: "utf-8", shell: win, env });
  if (r.error) return `${cmd[0]} could not run: ${reason(r.error)}`;
  return r.status === 0 ? null : `${cmd.join(" ")} failed:\n${`${r.stderr ?? ""}${r.stdout ?? ""}`.trim()}`;
}

/** The installed plugins, by package name, as the package.json of the folder records them. */
function installedVersions(dir: string): Record<string, string> {
  try {
    return JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf-8")).dependencies ?? {};
  } catch {
    return {};
  }
}

/**
 * Installs plugins for every workspace, and keeps them only if a server would
 * serve them.
 *
 * The function checks each plugin with the same rules as server startup,
 * together with every plugin that is already installed. Thus `add` refuses a
 * name that another plugin holds, before the next start of the server. One
 * refusal undoes the whole command.
 */
export function add(specs: readonly string[], env: NodeJS.ProcessEnv): Check[] {
  const dir = installDir(env);
  fs.mkdirSync(dir, { recursive: true });
  const manifest = path.join(dir, "package.json");
  if (!fs.existsSync(manifest)) {
    const pkg = { private: true, description: "Plugins installed by roc-syntax-mcp plugin add", dependencies: {} };
    fs.writeFileSync(manifest, `${JSON.stringify(pkg, null, 2)}\n`);
  }
  const saved = new Map(
    INSTALL_STATE.map((f) => path.join(dir, f))
      .filter((f) => fs.existsSync(f))
      .map((f) => [f, fs.readFileSync(f)] as const)
  );
  // npm does not prune a linked directory that it does not need. Thus `undo`
  // deletes the packages that this command added, then restores the old set.
  const undo = (names: Iterable<string> = []) => {
    for (const name of names) fs.rmSync(path.join(dir, "node_modules", name), { recursive: true, force: true });
    for (const f of INSTALL_STATE.map((n) => path.join(dir, n))) {
      const before = saved.get(f);
      if (before) fs.writeFileSync(f, before);
      else fs.rmSync(f, { force: true });
    }
    run(installer(dir, "sync", []), env);
  };

  const before = installedVersions(dir);
  const was = new Map(Object.keys(before).map((name) => [name, installedVersion(dir, name)]));
  // The server loads the installed plugins in name order. Thus a new plugin can
  // take a name from a plugin that the server serves at this time. `add`
  // refuses that case too.
  const judge = () => S.inspectDeclarations([], { ...env, ROC_MCP_PLUGINS: "" }, dir).filter((d) => d.source === INSTALLED);
  const servedBefore = new Set(judge().filter((d) => d.loaded).map((d) => d.spec));
  const failure = run(installer(dir, "add", specs.map(newestOf)), env);
  if (failure) {
    undo();
    return [bad("install", failure)];
  }
  const after = installedVersions(dir);
  const changed = new Set(Object.keys(after).filter((name) => after[name] !== before[name]));
  if (changed.size === 0) return [ok("install", "already installed, at the version asked for")];

  const judged = judge();
  const outcomes = judged.filter((d) => changed.has(d.spec));
  const refused = judged.filter((d) => !d.loaded && (changed.has(d.spec) || servedBefore.has(d.spec)));
  if (refused.length > 0) {
    undo(changed);
    return refused.map((d) =>
      bad(d.spec, changed.has(d.spec) ? `${d.problem}\nNothing was installed` : `would no longer be served next to ${[...changed].join(", ")}: ${d.problem}\nNothing was installed`)
    );
  }
  return [
    ...outcomes.map((d) => {
      const now = installedVersion(dir, d.spec) ?? after[d.spec];
      const from = was.get(d.spec);
      const upgraded = from && from !== now ? `upgraded from ${from}\n` : "";
      return ok(`${d.spec} ${now}`, `${upgraded}${d.dir}\n${served(d.loaded!).join("\n")}`);
    }),
    ok("served", "in every workspace, from the next start of the server. Restart your AI harness"),
  ];
}

/** Uninstalls plugins that `add` installed. A name that `add` did not install is an error. */
export function remove(names: readonly string[], env: NodeJS.ProcessEnv): Check[] {
  const dir = installDir(env);
  const installed = installedVersions(dir);
  const unknown = names.filter((n) => !(n in installed));
  if (unknown.length > 0) {
    return unknown.map((n) => bad(n, `not installed by plugin add. \`plugin list\` shows what is`));
  }
  const failure = run(installer(dir, "remove", names), env);
  if (failure) return [bad("remove", failure)];
  return [...names.map((n) => ok(n, "removed")), ok("served", "no longer, from the next start of the server")];
}

/** The version in node_modules, or null when the package is not there. */
function installedVersion(dir: string, name: string): string | null {
  try {
    return JSON.parse(fs.readFileSync(path.join(dir, "node_modules", name, "package.json"), "utf-8")).version ?? "";
  } catch {
    return null;
  }
}

/**
 * The releases that an installed plugin documents, e.g. ` (joy 0.34.0,
 * joy-html 0.17.0)`. The version of the plugin changes with each curation, so
 * only its manifest tells which release the curation is for.
 */
function documents(dir: string, name: string): string {
  let manifest: PluginManifest;
  try {
    manifest = JSON.parse(fs.readFileSync(path.join(dir, "node_modules", name, "plugin.json"), "utf-8"));
  } catch {
    return "";
  }
  const releases = (Array.isArray(manifest?.corpora) ? manifest.corpora : []).flatMap((c) => {
    const pin = typeof c?.release === "string" ? S.pinFromUrl(c.release) : null;
    return pin ? [`${c.name ?? pin.id.split("/").at(-1)} ${pin.version}`] : [];
  });
  return releases.length > 0 ? ` (${releases.join(", ")})` : "";
}

/** What `add` installed, and where. */
export function list(env: NodeJS.ProcessEnv): Check[] {
  const dir = installDir(env);
  const installed = Object.entries(installedVersions(dir));
  return [
    ok("folder", dir),
    ...(installed.length === 0
      ? [ok("installed", "nothing. `plugin add <package>` installs a plugin for every workspace")]
      : installed.map(([name, spec]) => {
          const version = installedVersion(dir, name);
          return version === null
            ? bad(name, `${spec}\nnot in ${path.join(dir, "node_modules")}. \`plugin add\` it again, or \`plugin remove\` it`)
            : ok(`${name} ${version}${documents(dir, name)}`, spec);
        })),
  ];
}

/**
 * Whether npm reads a dependency spec as a release from a registry. Only that
 * kind of spec can have a newer release to fetch. A path, a git source and an
 * alias contain a `:` or a `/`, and a tarball ends in `.tgz` or `.tar.gz`. A
 * range or a tag has none of these.
 */
export const isRegistrySpec = (spec: string): boolean => !/[:/\\]/.test(spec) && !/\.(tgz|tar\.gz)$/.test(spec);

/**
 * Adds `@latest` to a bare package name. Without it, npm keeps the range that
 * the first install saved, and `^0.0.1` matches only 0.0.1.
 */
export const newestOf = (spec: string): string =>
  /^(@[\w.-]+\/)?[\w.-]+$/.test(spec) && !/^\.|\.(tgz|tar\.gz)$/.test(spec) ? `${spec}@latest` : spec;

/**
 * Installs the newest release of each plugin that `add` installed, or of each
 * named plugin. The function updates one plugin at a time. If the server
 * refuses a release, only that plugin stays at its old version, and the other
 * plugins update.
 */
export function update(names: readonly string[], env: NodeJS.ProcessEnv): Check[] {
  const dir = installDir(env);
  const installed = installedVersions(dir);
  const unknown = names.filter((n) => !(n in installed));
  if (unknown.length > 0) {
    return unknown.map((n) => bad(n, `not installed by plugin add. \`plugin list\` shows what is`));
  }
  const wanted = names.length > 0 ? names : Object.keys(installed);
  if (wanted.length === 0) return [ok("installed", "nothing. `plugin add <package>` installs a plugin for every workspace")];

  const out: Check[] = [];
  let upgraded = false;
  for (const name of wanted) {
    const spec = installed[name];
    if (!isRegistrySpec(spec)) {
      const folder = /^(file|link):/.test(spec) && !/\.(tgz|tar\.gz)$/.test(spec);
      out.push(
        ok(
          name,
          folder
            ? `linked to ${path.resolve(dir, spec.replace(/^(file|link):/, ""))}, so it serves what that folder holds now`
            : `installed from ${spec}, not from a registry. \`plugin add\` its newer source to update it`
        )
      );
      continue;
    }
    for (const c of add([name], env)) {
      if (c.name === "served") upgraded = true;
      else if (c.name !== "install") out.push(c);
      else if (c.status === "ok") out.push(ok(`${name} ${installedVersion(dir, name)}`, "already the newest release"));
      else out.push(bad(name, c.detail!));
    }
  }
  if (upgraded) out.push(ok("served", "from the next start of the server. Restart your AI harness"));
  return out;
}

// -----------------------------------------------------------------------------
// Upgrading the server, then its plugins
// -----------------------------------------------------------------------------

/** How this server was installed. The install method decides whether the server can update itself. */
export interface Install {
  /** What installed it, or what runs it. */
  by: string;
  /** The command that updates it in place. Absent when this server cannot update itself. */
  update?: string[];
  /** Where the server is after `update`. pnpm 11 moves it on every install. */
  locate?: () => string | null;
  /** What `update` fetches. A git source has no version that tells two commits apart. */
  spec?: string;
  /** What to do instead, when there is no `update`. */
  fix?: string;
}

/** A package manager's global folder, and the command that installs into it. */
export interface GlobalRoot {
  by: string;
  /** Matches the real path of a server that this manager probably installed. `detectInstall` asks a matching manager first. */
  hint: RegExp;
  /** If true, `detectInstall` asks this manager only when `hint` matches. Yarn under Corepack can download Yarn to answer. */
  onlyHinted?: boolean;
  /** The folder that holds global packages, or null when that manager is not here. */
  root: () => string | null;
  install: (spec: string) => string[];
}

/**
 * The last line of a command output, without terminal escape codes. Yarn 1
 * clears its progress line before the answer, even into a pipe.
 */
export const lastLine = (stdout: string): string =>
  stdout.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").trim().split(/\r?\n/).at(-1)!.trim();

/** The last line that a command printed, or null if it could not run or failed. */
function output(cmd: readonly string[], env: NodeJS.ProcessEnv): string | null {
  const win = process.platform === "win32";
  const args = win ? cmd.map(quoteForCmd) : cmd;
  const r = spawnSync(args[0], args.slice(1), { encoding: "utf-8", shell: win, env, timeout: 30_000 });
  return r.status === 0 ? lastLine(r.stdout) || null : null;
}

/** Every global install this command can update. */
export function globalRoots(env: NodeJS.ProcessEnv): GlobalRoot[] {
  const home = env.HOME ?? env.USERPROFILE ?? "";
  return [
    {
      by: "Bun",
      hint: /[\\/]install[\\/]global[\\/]/,
      root: () => path.join(env.BUN_INSTALL ?? path.join(home, ".bun"), "install", "global", "node_modules"),
      // Without --no-cache, Bun keeps the version list that it read at install, and finds no newer release.
      install: (s) => ["bun", "add", "-g", "--no-cache", s],
    },
    { by: "pnpm", hint: /pnpm/i, root: () => output(["pnpm", "root", "-g"], env), install: (s) => ["pnpm", "add", "-g", s] },
    {
      by: "Yarn 1",
      hint: /yarn/i,
      onlyHinted: true,
      root: () => {
        const dir = output(["yarn", "global", "dir"], env);
        return dir ? path.join(dir, "node_modules") : null;
      },
      install: (s) => ["yarn", "global", "add", s],
    },
    { by: "npm", hint: /$^/, root: () => output(["npm", "root", "-g"], env), install: (s) => ["npm", "install", "-g", s] },
  ];
}

const real = (p: string): string | null => {
  try {
    return fs.realpathSync(p);
  } catch {
    return null;
  }
};

/**
 * Every copy of this server in a global folder: at the top level, or one level
 * down, where pnpm 11 keeps each global package in a separate folder.
 */
export function serversIn(root: string): string[] {
  const top = path.join(root, "roc-syntax-mcp");
  let apart: string[] = [];
  try {
    apart = fs.readdirSync(root).map((d) => path.join(root, d, "node_modules", "roc-syntax-mcp"));
  } catch {}
  return [top, ...apart].filter((p) => fs.existsSync(path.join(p, "package.json")));
}

/** The copy installed last, which after an update is the new one. */
function newest(paths: readonly string[]): string | null {
  const when = (p: string) => fs.lstatSync(p).mtimeMs;
  return [...paths].sort((a, b) => when(b) - when(a))[0] ?? null;
}

/**
 * The spec that a global install fetches to get the newest server. An install
 * from the git repository has no build, so it updates from the repository
 * again. The registry would replace it with the last release.
 */
export function upgradeSpec(root: string): string {
  const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf-8"));
  if (fs.existsSync(path.join(root, "dist", "index.js"))) return `${pkg.name}@latest`;
  const repo = String(pkg.repository?.url ?? "").match(/github\.com[/:]([^/]+\/[^/]+?)(\.git)?$/);
  return repo ? `github:${repo[1]}` : `${pkg.name}@latest`;
}

/**
 * Finds how the server in `root` was installed. The function names a manager
 * only if its global folder holds this copy. Thus `upgrade` never updates a
 * different install on the same machine.
 */
export function detectInstall(root: string, roots: readonly GlobalRoot[]): Install {
  const after = "then run `roc-syntax-mcp plugin update`";
  if (fs.existsSync(path.join(root, ".git"))) {
    return { by: "a git checkout", fix: `Run \`git pull\` in ${root}, ${after}` };
  }
  const runner = [
    { by: "npx", seen: /[\\/]_npx[\\/]/ },
    { by: "bunx", seen: /[\\/]bunx-[^\\/]*[\\/]/ },
    { by: "pnpm dlx", seen: /[\\/]dlx[\\/]/ },
    { by: "yarn dlx", seen: /[\\/]dlx-[^\\/]*[\\/]/ },
  ].find((r) => r.seen.test(root));
  if (runner) {
    return {
      by: runner.by,
      fix:
        `${runner.by} keeps its own copy, and decides which release your client starts. ` +
        `\`${runner.by} roc-syntax-mcp@latest plugin update\` updates the plugins with the newest server. ` +
        `To start the newest server every time, give your client \`roc-syntax-mcp@latest\``,
    };
  }
  const here = real(root);
  if (!here) return { by: "an unknown installer", fix: `Update it the way you installed it, ${after}` };
  const hinted = roots.filter((g) => g.hint.test(here));
  for (const g of [...hinted, ...roots.filter((g) => !g.onlyHinted && !hinted.includes(g))]) {
    const dir = g.root();
    if (!dir || !serversIn(dir).some((p) => real(p) === here)) continue;
    const spec = upgradeSpec(root);
    return { by: g.by, update: g.install(spec), spec, locate: () => newest(serversIn(dir)) };
  }
  return { by: "an unknown installer", fix: `Update it the way you installed it, ${after}` };
}

const packageOf = (dir: string): { version?: string; bin?: string | Record<string, string> } => {
  try {
    return JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf-8"));
  } catch {
    return {};
  }
};

/** The new server's entry, as its own package.json names it. */
export function entryOf(dir: string): string {
  const bin = packageOf(dir).bin;
  return path.join(dir, (typeof bin === "string" ? bin : bin?.["roc-syntax-mcp"]) ?? path.join("bin", "roc-syntax-mcp.js"));
}

/** Updates the server where it is installed, and returns the directory of the new server. The new server updates the plugins. */
export function upgradeServer(install: Install, env: NodeJS.ProcessEnv): { checks: Check[]; dir?: string } {
  if (!install.update || !install.locate) {
    return { checks: [bad("roc-syntax-mcp", `installed by ${install.by}, which this command cannot update. ${install.fix}`)] };
  }
  const was = install.locate();
  const before = was ? packageOf(was).version : undefined;
  const failure = run(install.update, env);
  if (failure) return { checks: [bad("roc-syntax-mcp", `${failure}\nThe plugins were not updated`)] };
  const dir = install.locate();
  if (!dir) return { checks: [bad("roc-syntax-mcp", `${install.by} reported success, and installed no server where it installed this one`)] };
  const now = packageOf(dir).version;
  const said =
    install.spec && !install.spec.endsWith("@latest")
      ? `installed again from ${install.spec}`
      : before === now
        ? "already the newest release"
        : `upgraded from ${before}`;
  return { checks: [ok(`roc-syntax-mcp ${now}`, `${said}, by ${install.by}`)], dir };
}

/**
 * Updates the server, then runs the new server to update every plugin, because
 * the new server decides which plugins it serves. Server startup never calls
 * this function.
 *
 * The old release runs `plugin update` in the new release. Thus `plugin update`
 * must keep its name and its meaning in every release.
 */
export function upgrade(env: NodeJS.ProcessEnv, install: Install = detectInstall(ROOT, globalRoots(env))): number {
  if (install.update) console.log(`Updating roc-syntax-mcp with ${install.by}: ${install.update.join(" ")}`);
  const { checks, dir } = upgradeServer(install, env);
  console.log(render(checks));
  if (!dir) return 1;
  // Bun runs the `node` entry of a package itself, so the current runtime can start the new server.
  const r = spawnSync(process.execPath, [entryOf(dir), "plugin", "update"], { stdio: "inherit", env });
  return r.status ?? 1;
}

// -----------------------------------------------------------------------------
// Entry
// -----------------------------------------------------------------------------

const USAGE = `usage: roc-syntax-mcp plugin <command>

  add <package>... install plugins for every workspace, from npm or a path
  update [name...] install the newest release of every plugin add installed, or of the named ones
  remove <name>... uninstall plugins that add installed
  list             what add installed, and where
  doctor           the plugin set a server launched here would load, and why

  init <dir>       write a plugin skeleton, ready to fill in
  index <dir>      write index.json from the releases plugin.json names
  validate <dir>   run the check scripts of this server on a plugin
  inspect <dir>    what this host would index from a plugin

init options:      --name= --repo=owner/repo --version= --url=<release tarball>
                   --package=@you/name   npm id, when you are not the release's publisher
                   --kind=package        a package corpus rather than a platform
                   --platform=<url>      what a package skeleton's apps pin for I/O
index options:     --check     compare, do not write. Exit 1 if out of date
validate options:  --offline   skip each check that needs a compiler or a spawn

index reads each release from the Roc package cache, and runs \`roc deps\` (from
$ROC, or roc on PATH) to fetch one that is not there.
`;

/** Whether npm reads a spec as a path rather than as a package name. */
export const isPathSpec = (spec: string): boolean =>
  /^(\.{1,2}|~)([\\/]|$)/.test(spec) || path.isAbsolute(spec) || /\.(tgz|tar\.gz)$/.test(spec);

function packageName(dir: string): string | null {
  try {
    return JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf-8")).name ?? null;
  } catch {
    return null;
  }
}

function flags(argv: readonly string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const a of argv) {
    const m = a.match(/^--([\w-]+)(?:=(.*))?$/);
    if (m) out[m[1]] = m[2] ?? "1";
  }
  return out;
}

export async function main(argv: readonly string[]): Promise<number> {
  // Set ROC to a compiler that `roc install` recorded, so that the check
  // scripts use it too. Every script and server that they start reads ROC.
  const choice = findRoc([], process.env);
  if (choice.source === "roc use") process.env.ROC = choice.command;
  const [command, ...rest] = argv;
  const positional = rest.filter((a) => !a.startsWith("--"));
  const opts = flags(rest);
  const target = (): string | null => {
    if (positional.length > 0) return path.resolve(positional[0]);
    console.error(`${command} needs a plugin directory\n\n${USAGE}`);
    return null;
  };

  switch (command) {
    case "init": {
      const dir = target();
      if (!dir) return 2;
      const checks = init(dir, opts);
      console.log(render(checks));
      return failed(checks) ? 1 : 0;
    }
    case "index": {
      const dir = target();
      if (!dir) return 2;
      const roc = process.env.ROC || "roc";
      const { status, missing } = await R.indexManifestDir(dir, { check: Boolean(opts.check), roc });
      if (missing.length > 0) {
        console.error(
          R.rocRuns(roc)
            ? `roc deps could not fetch:\n  ${missing.join("\n  ")}`
            : `No roc to fetch ${missing.length} release(s) with. Run \`roc-syntax-mcp roc install\`, or set ROC=/path/to/roc.`
        );
        return 1;
      }
      const said = {
        none: "plugin.json names no release, so there is nothing to index",
        ok: `${R.INDEX_FILE} is current`,
        wrote: `wrote ${path.join(dir, R.INDEX_FILE)}`,
        stale: `${R.INDEX_FILE} differs from its releases. Run without --check to rewrite it`,
      }[status];
      console.log(said);
      return status === "stale" ? 1 : 0;
    }
    case "validate": {
      const dir = target();
      if (!dir) return 2;
      const checks = await validate(dir, { offline: Boolean(opts.offline) });
      console.log(render(checks));
      return failed(checks) ? 1 : 0;
    }
    case "inspect": {
      const dir = target();
      if (!dir) return 2;
      process.stdout.write(inspect(dir));
      return 0;
    }
    case "doctor": {
      const checks = doctor(rest, process.env, workspaceRoot(process.env, rest));
      console.log(render(checks));
      return failed(checks) ? 1 : 0;
    }
    case "update": {
      const names = positional.map((p) => (isPathSpec(p) && fs.existsSync(p) ? (packageName(p) ?? p) : p));
      const checks = update(names, process.env);
      console.log(render(checks));
      return failed(checks) ? 1 : 0;
    }
    case "add":
    case "remove": {
      if (positional.length === 0) {
        console.error(`${command} needs a package name\n\n${USAGE}`);
        return 2;
      }
      // Resolve a path against the directory where the user ran the command,
      // not the folder where npm runs. Detect a path as npm does, so that a bare
      // name is never a folder. For `remove`, a path names the package in it.
      const specs = positional.map((p) => {
        if (!isPathSpec(p) || !fs.existsSync(p)) return p;
        return command === "add" ? path.resolve(p) : (packageName(p) ?? p);
      });
      const checks = (command === "add" ? add : remove)(specs, process.env);
      console.log(render(checks));
      return failed(checks) ? 1 : 0;
    }
    case "list": {
      const checks = list(process.env);
      console.log(render(checks));
      return failed(checks) ? 1 : 0;
    }
    default:
      console.error(USAGE);
      return command ? 2 : 0;
  }
}

// Run `main` only when this file is the program, so that a test can import the commands without running one.

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename)) {
  process.exit(await main(process.argv.slice(2)));
}
