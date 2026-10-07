// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Reads the plugin declarations and resolves each one to a directory. This
// module reads no corpus and does not use scopes. It turns a spec that an
// operator wrote into a path, and `src/scopes.ts` turns that path into a scope.

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { createRequire } from "node:module";

/**
 * The folder that `--workspace=<dir>` names, or null. The function logs and
 * ignores a folder that does not exist. Such a folder is usually a
 * `${workspaceFolder}` that the client did not substitute.
 */
export function workspaceFlag(argv: readonly string[]): string | null {
  let flag: string | null = null;
  for (const arg of argv) {
    const m = arg.match(/^--workspace=(.+)$/);
    if (m) flag = m[1].trim();
  }
  if (flag === null) return null;
  if (fs.statSync(flag, { throwIfNoEntry: false })?.isDirectory()) return path.resolve(flag);
  console.error(`roc-syntax: --workspace=${flag} is not a folder, so it is ignored`);
  return null;
}

/**
 * The root of the project that this server serves. The first source that is
 * set wins: `--workspace=`, then Claude Code's `CLAUDE_PROJECT_DIR`, then the cwd.
 *
 * The `roots` handshake of the client gives a better answer, but it arrives too
 * late. Startup loads the plugins before it creates the server, so the scope of
 * each plugin must exist before the first request. At that time, only the
 * command line and the environment are available.
 */
export function workspaceRoot(
  env: Record<string, string | undefined> = process.env,
  argv: readonly string[] = []
): string {
  return workspaceFlag(argv) ?? (env.CLAUDE_PROJECT_DIR || process.cwd());
}

/** One plugin that an operator declared, and where they declared it. */
export interface Declaration {
  /** A package name or a path, exactly as written. */
  spec: string;
  /** Where the spec was written. Every diagnostic names it, because the operator fixes the spec there. */
  source: string;
}

function fromEnv(value: string | undefined): string[] {
  // Accepts `,` and both path separators, the POSIX `:` and the Windows `;`. A
  // client that passes env easily rarely knows which OS the server runs on.
  return (value ?? "")
    .split(/[,:;]/)
    .map((s) => s.trim())
    .filter(Boolean);
}

/**
 * The data folder of this server, where `plugin add` installs plugins.
 * `ROC_MCP_HOME` overrides the default. A folder that does not exist holds no
 * plugins.
 */
export function pluginHome(env: Record<string, string | undefined>): string {
  if (env.ROC_MCP_HOME) return path.resolve(env.ROC_MCP_HOME);
  const home = os.homedir();
  const base =
    process.platform === "win32"
      ? env.LOCALAPPDATA || path.join(home, "AppData", "Local")
      : process.platform === "darwin"
        ? path.join(home, "Library", "Application Support")
        : env.XDG_DATA_HOME || path.join(home, ".local", "share");
  return path.join(base, "roc-syntax-mcp");
}

/** The npm project that `plugin add` installs into. Its dependencies are the installed plugins. */
export const installDir = (env: Record<string, string | undefined>): string => path.join(pluginHome(env), "plugins");

/** The name of each package that `plugin add` installed. */
export function installedPlugins(env: Record<string, string | undefined>): string[] {
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(installDir(env), "package.json"), "utf-8"));
    return Object.keys(pkg?.dependencies ?? {});
  } catch {
    return [];
  }
}

/** The places to look up a package name, in order: the `plugin add` folder, then the install of this server. */
export function lookupPlaces(env: Record<string, string | undefined>): string[] {
  return [path.join(installDir(env), "package.json"), import.meta.filename];
}

/** The `Declaration.source` of each plugin that `plugin add` installed. */
export const INSTALLED = "plugin add";

/**
 * Every declared plugin, in the order that the function reads the sources. If
 * two sources declare the same spec, the first one wins.
 *
 * The three sources add together, because each one has a different purpose:
 * - `--plugin=` adds plugins for one client entry. A project can commit that
 *   entry in its client config.
 * - `ROC_MCP_PLUGINS` does the same as the flag, for a client that passes env
 *   more easily than arguments.
 * - `plugin add` lists the plugins that this user installed for every project.
 *
 * Only `plugin add` installs packages, and only when the user runs it.
 */
export function declarations(argv: readonly string[], env: Record<string, string | undefined>): Declaration[] {
  const out: Declaration[] = [];
  const seen = new Set<string>();
  const add = (spec: string, source: string) => {
    if (seen.has(spec)) return;
    seen.add(spec);
    out.push({ spec, source });
  };
  for (const arg of argv) {
    const m = arg.match(/^--plugin=(.+)$/);
    if (m) add(m[1].trim(), "--plugin=");
  }
  for (const spec of fromEnv(env.ROC_MCP_PLUGINS)) add(spec, "ROC_MCP_PLUGINS");
  for (const spec of installedPlugins(env)) add(spec, INSTALLED);
  return out;
}

/**
 * Every package namespace where the end user accepts a release that differs from
 * the release the platform pins.
 *
 * The host infers from the corpus that a package crosses the exposed API of the
 * platform. Then it refuses a package release that differs from the release
 * that the platform pins. That test can report a crossing that is not real, so
 * the end user can confirm that they checked.
 *
 * Only the end user sets this override, not a plugin author. No manifest field
 * sets it. For this reason, the function reads only the flag and the variable,
 * which a plugin cannot change.
 */
export function forcedNamespaces(argv: readonly string[], env: Record<string, string | undefined>): Declaration[] {
  const out: Declaration[] = [];
  const seen = new Set<string>();
  const add = (spec: string, source: string) => {
    if (seen.has(spec)) return;
    seen.add(spec);
    out.push({ spec, source });
  };
  for (const arg of argv) {
    const m = arg.match(/^--force=(.+)$/);
    if (m) for (const id of fromEnv(m[1])) add(id, "--force=");
  }
  for (const id of fromEnv(env.ROC_MCP_FORCE)) add(id, "ROC_MCP_FORCE");
  return out;
}

/**
 * The directory that a declaration names, as a path or as an installed package.
 *
 * The function resolves the `plugin.json` of a package, not its entry point,
 * because a plugin ships no JavaScript and does not have to declare a `main`.
 *
 * A relative path resolves against `workspace`. The function looks for a
 * package in each of `places`. By default, these are the `plugin add` folder,
 * then the install of this server. A global install puts the plugin next to the
 * server, and only the second place finds it.
 *
 * Throws if nothing resolves. The server then serves everything else.
 */
export function resolvePluginDir(
  spec: string,
  workspace: string,
  places: readonly string[] = lookupPlaces(process.env)
): string {
  if (spec.startsWith(".") || path.isAbsolute(spec)) {
    const dir = path.resolve(workspace, spec);
    if (!fs.existsSync(path.join(dir, "plugin.json"))) {
      throw new Error(`${dir} has no plugin.json`);
    }
    return dir;
  }
  const froms = places;
  for (const from of froms) {
    try {
      return path.dirname(createRequire(from).resolve(`${spec}/plugin.json`));
    } catch {
      // Not installed there.
    }
  }
  // A package that has no plugin.json needs a different fix than a package that is not installed.
  for (const from of froms) {
    let dir: string;
    try {
      dir = path.dirname(createRequire(from).resolve(`${spec}/package.json`));
    } catch {
      continue;
    }
    throw new Error(`${spec} at ${dir} has no plugin.json, so it is not a plugin`);
  }
  throw new Error(`${spec} is installed neither by plugin add nor beside this server`);
}

/** The fix to tell the operator when a declaration resolves to no directory. */
export function unresolvedFix(d: Declaration): string {
  if (d.source === INSTALLED) {
    return `Run \`roc-syntax-mcp plugin remove ${d.spec}\`, or \`plugin add\` it again`;
  }
  return `Install it, or remove it from ${d.source}`;
}
