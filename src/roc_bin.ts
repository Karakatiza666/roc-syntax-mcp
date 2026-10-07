// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Which `roc` the server runs, and the `roc` command that installs one.
//
// The server chooses the compiler again on every call, so the next call uses a
// compiler installed while the server runs, with no restart. The client fixes
// the server's PATH when it starts the server. A compiler that the agent
// installs later is found through the record that `roc install` and `roc use`
// write.
//
// This module must not import the server, because the bin runs the `roc`
// command without a server.

import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { pluginHome } from "./plugins.ts";

const ROOT = path.join(import.meta.dirname, "..");
const NIGHTLIES = "roc-lang/nightlies";
const EXE = process.platform === "win32" ? "roc.exe" : "roc";

/** The nightly every bundled corpus was checked against, from `corpus/language/UPSTREAM`. */
export function bundledNightly(): string {
  const upstream = fs.readFileSync(path.join(ROOT, "corpus", "language", "UPSTREAM"), "utf-8");
  return upstream.match(/^compiler\s+(\S+)/m)?.[1] ?? "";
}

/** The folder `roc install` unpacks into, and the record of the chosen binary. */
export const rocHome = (env: Record<string, string | undefined>) => path.join(pluginHome(env), "roc");
const recordOf = (env: Record<string, string | undefined>) => path.join(rocHome(env), "use");

export interface RocChoice {
  /** What to spawn: a path, or `roc` for a PATH lookup. */
  command: string;
  /** Where the choice came from, for `roc-syntax-mcp roc` and the error text. */
  source: "--roc=" | "ROC" | "roc use" | "PATH";
}

/**
 * The compiler to run. An explicit flag or variable wins, then the binary that
 * `roc install` or `roc use` recorded, then whatever `roc` the PATH holds. A
 * recorded binary that was deleted is skipped.
 */
export function findRoc(argv: readonly string[], env: Record<string, string | undefined>): RocChoice {
  let flag: string | null = null;
  for (const arg of argv) {
    const m = arg.match(/^--roc=(.+)$/);
    if (m) flag = m[1].trim();
  }
  if (flag) return { command: flag, source: "--roc=" };
  if (env.ROC) return { command: env.ROC, source: "ROC" };
  try {
    const recorded = fs.readFileSync(recordOf(env), "utf-8").trim();
    if (recorded && fs.existsSync(recorded)) return { command: recorded, source: "roc use" };
  } catch {
    // No record, which is the common case.
  }
  return { command: "roc", source: "PATH" };
}

/** The compiler a server started with `argv` and `env` runs now. */
export const rocCommand = (
  argv: readonly string[] = process.argv.slice(2),
  env: Record<string, string | undefined> = process.env
): string => findRoc(argv, env).command;

/** The exact command that runs this binary again, whatever installed it. */
export function selfCommand(): string {
  const q = (s: string) => (/^[\w./:@+-]+$/.test(s) ? s : JSON.stringify(s));
  return `${q(process.execPath)} ${q(process.argv[1] ?? path.join(ROOT, "bin", "roc-syntax-mcp.js"))}`;
}

/** The tool message when no compiler runs, with the command that fixes this in the session. */
export function rocMissing(
  argv: readonly string[] = process.argv.slice(2),
  env: Record<string, string | undefined> = process.env
): string {
  const choice = findRoc(argv, env);
  const where =
    choice.source === "PATH" ? "`roc` is not on the PATH this server started with" : `${choice.command} (from ${choice.source}) does not run`;
  return (
    `No Roc compiler: ${where}. To install the nightly this server was checked against, ` +
    `run \`${selfCommand()} roc install\` in a shell. It downloads about 70 MB, so allow it a few minutes. ` +
    `To use a compiler you already have, ` +
    `run \`${selfCommand()} roc use /path/to/roc\`. Either one takes effect on the next call, ` +
    `with no restart.`
  );
}

/** The release asset name for this machine, or null where no nightly is built. */
export function nightlyAsset(tag: string, platform = process.platform, arch = process.arch): string | null {
  const stamp = tag.replace(/^nightly-/, "");
  const target =
    platform === "linux" && arch === "x64"
      ? "linux_x86_64"
      : platform === "linux" && arch === "arm64"
        ? "linux_arm64"
        : platform === "darwin" && arch === "arm64"
          ? "macos_apple_silicon"
          : platform === "darwin" && arch === "x64"
            ? "macos_x86_64"
            : platform === "win32" && arch === "x64"
              ? "windows_x86_64"
              : null;
  if (!target) return null;
  return `roc_nightly-${target}-${stamp}.${platform === "win32" ? "zip" : "tar.gz"}`;
}

/** The `roc version` line of a binary, or null when it does not run. */
export function rocVersion(command: string): string | null {
  const r = spawnSync(command, ["version"], { encoding: "utf-8", timeout: 30_000 });
  return r.status === 0 ? r.stdout.trim().split("\n")[0] : null;
}

/** The first file named `roc` (or `roc.exe`) under `dir`, a few levels down. */
function findBinary(dir: string, depth = 3): string | null {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isFile() && entry.name === EXE) return path.join(dir, entry.name);
  }
  if (depth === 0) return null;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const found = findBinary(path.join(dir, entry.name), depth - 1);
    if (found) return found;
  }
  return null;
}

/** Record `binary` as the compiler the server runs. */
export function useRoc(binary: string, env: Record<string, string | undefined>): { ok: boolean; message: string } {
  const abs = path.resolve(binary);
  const version = rocVersion(abs);
  if (!version) return { ok: false, message: `${abs} does not run \`roc version\`. Nothing was recorded` };
  fs.mkdirSync(rocHome(env), { recursive: true });
  fs.writeFileSync(recordOf(env), abs + "\n");
  return { ok: true, message: `the server now runs ${abs} (${version}), from its next call` };
}

export interface InstallOptions {
  /** The GitHub API base, for tests. */
  api?: string;
  /** The release download base, for tests. */
  downloads?: string;
}

/**
 * Download a nightly into the server's folder, check its digest, unpack it and
 * record it. The digest comes from the GitHub release, so a download that was
 * cut short or altered is refused.
 */
export async function installRoc(
  tag: string,
  env: Record<string, string | undefined>,
  opts: InstallOptions = {}
): Promise<{ ok: boolean; message: string }> {
  const asset = nightlyAsset(tag);
  if (!asset) return { ok: false, message: `no Roc nightly is built for ${process.platform} ${process.arch}` };
  const api = opts.api ?? "https://api.github.com";
  const downloads = opts.downloads ?? "https://github.com";
  let url = `${downloads}/${NIGHTLIES}/releases/download/${tag}/${asset}`;
  let digest: string | null = null;
  try {
    const res = await fetch(`${api}/repos/${NIGHTLIES}/releases/tags/${tag}`, {
      headers: { accept: "application/vnd.github+json" },
    });
    if (res.status === 404) return { ok: false, message: `${NIGHTLIES} has no release ${tag}` };
    if (res.ok) {
      const found = ((await res.json()).assets ?? []).find((a: { name: string }) => a.name === asset);
      if (!found) return { ok: false, message: `${tag} has no ${asset}` };
      url = found.browser_download_url ?? url;
      digest = typeof found.digest === "string" ? found.digest.replace(/^sha256:/, "") : null;
    }
  } catch {
    // The API is rate limited for anonymous callers. The download URL is
    // known without it, and only the digest check is lost.
  }

  const home = rocHome(env);
  fs.mkdirSync(home, { recursive: true });
  const work = fs.mkdtempSync(path.join(home, ".install-"));
  try {
    const res = await fetch(url);
    if (!res.ok || !res.body) return { ok: false, message: `${url}: HTTP ${res.status}` };
    const archive = path.join(work, asset);
    const hash = crypto.createHash("sha256");
    const out = fs.createWriteStream(archive);
    for await (const chunk of res.body as unknown as AsyncIterable<Uint8Array>) {
      hash.update(chunk);
      if (!out.write(chunk)) await new Promise<void>((r) => out.once("drain", () => r()));
    }
    await new Promise<void>((resolve, reject) => out.end((err?: Error | null) => (err ? reject(err) : resolve())));
    const actual = hash.digest("hex");
    if (digest && actual !== digest) {
      return { ok: false, message: `${asset}: sha256 ${actual}, the release says ${digest}. Nothing was installed` };
    }

    // bsdtar, which Windows 10 and later ship as tar.exe, unpacks a zip too.
    const unpacked = path.join(work, "unpacked");
    fs.mkdirSync(unpacked);
    const tar = spawnSync("tar", ["-xf", archive, "-C", unpacked], { encoding: "utf-8" });
    if (tar.status !== 0) return { ok: false, message: `tar could not unpack ${asset}: ${tar.stderr || tar.error}` };

    const dest = path.join(home, tag);
    fs.rmSync(dest, { recursive: true, force: true });
    fs.renameSync(unpacked, dest);
    const binary = findBinary(dest);
    if (!binary) return { ok: false, message: `${asset} holds no ${EXE}` };
    const used = useRoc(binary, env);
    const checked = digest ? `sha256 checked against the release` : `no digest to check, the GitHub API did not answer`;
    return used.ok ? { ok: true, message: `installed ${tag} (${checked}), and ${used.message}` } : used;
  } catch (err) {
    return { ok: false, message: `${url}: ${err instanceof Error ? err.message : String(err)}` };
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

const USAGE = `usage: roc-syntax-mcp roc [install [nightly] | use <path>]

  roc                 show which compiler the server runs, and where that choice came from
  install [nightly]   download a nightly from ${NIGHTLIES} and use it. Defaults to the one
                      this server was checked against, such as nightly-2026-10-06-c34079d
  use <path>          use a compiler you already have

The server looks again on every call, so neither needs a restart. --roc=<path> and
the ROC variable, when set, win over both.`;

export async function main(args: readonly string[], env = process.env): Promise<number> {
  const [cmd, ...rest] = args;
  if (cmd === "--help" || cmd === "-h") {
    console.log(USAGE);
    return 0;
  }
  if (cmd === undefined) {
    const choice = findRoc([], env);
    const version = rocVersion(choice.command);
    console.log(`${choice.command} (from ${choice.source}): ${version ?? "does not run"}`);
    console.log(`bundled nightly: ${bundledNightly()}`);
    return version ? 0 : 1;
  }
  let result: { ok: boolean; message: string };
  if (cmd === "install" && rest.length <= 1) {
    const tag = rest[0] ?? bundledNightly();
    console.log(`Installing ${tag} from ${NIGHTLIES} into ${rocHome(env)}`);
    result = await installRoc(tag, env);
  } else if (cmd === "use" && rest.length === 1) {
    result = useRoc(rest[0], env);
  } else {
    console.error(USAGE);
    return 2;
  }
  (result.ok ? console.log : console.error)(result.message);
  return result.ok ? 0 : 1;
}
