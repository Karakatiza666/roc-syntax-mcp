#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
# SPDX-License-Identifier: MPL-2.0

# Type-checks every program that a platform or package plugin ships, with a
# real Roc compiler.
#
# Each app here pins its platform by tarball URL, so the compiler gets the
# released platform. Thus this gate checks the bundled nightly and the pinned
# releases as a set. The first run downloads about 50MB of packages and takes
# about 30s. Later runs take tens of milliseconds per file.
#
# With no arguments, the script checks the plugins that this server ships. With
# plugin directories as arguments, it checks only those. `plugin validate` uses
# the second form.
#
# Usage: ROC=/path/to/roc scripts/check-platform-examples.sh [plugin-dir ...]
set -uo pipefail

ROC="${ROC:-roc}"
command -v "$ROC" >/dev/null 2>&1 || { echo "roc not found. Set ROC=/path/to/roc" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
shopt -s nullglob

# Find every platform and package corpus on disk. With a fixed list, a corpus
# that someone added to corpus/ and not to the list would look checked, but
# nothing would check it.
PLUGINS=()
if [ "$#" -gt 0 ]; then
  for d in "$@"; do PLUGINS+=("$(cd "$d" && pwd)"); done
else
  for p in "$ROOT"/corpus/platforms/*/ "$ROOT"/corpus/packages/*/; do
    [ -f "${p}plugin.json" ] && PLUGINS+=("${p%/}")
  done
fi

# Prints one line for each corpus that the manifest of this plugin declares. It
# uses the server's loader, because the loader derives the name, kind and
# version of a corpus from its release. A `|` separates the fields, because
# `read` merges adjacent whitespace separators. With a whitespace separator, the
# two empty fields of a package would move its directories into the scaffold
# field.
manifest() {
  ( cd "$ROOT" && node --input-type=module -e '
const S = await (await import("./scripts/tree.mjs")).load("scopes");
const fs = await import("node:fs");
const dir = process.argv[1];
const p = S.fromManifest(dir, JSON.parse(fs.readFileSync(dir + "/plugin.json", "utf-8")));
// Each def comes from the loaded scope. An empty scaffold field means nothing to wrap.
for (const d of p.defs) {
  console.log([d.name, d.scaffold ?? "", d.sample ?? "", [d.examples, ...(d.checks ?? [])].filter(Boolean).join(" ")].join("|"));
}
for (const d of p.docs) {
  console.log([d.name, "", "", [d.examples, ...(d.checks ?? [])].filter(Boolean).join(" ")].join("|"));
}
' "$1" )
}

WRAPPED="$(mktemp -d)"
trap 'rm -rf "$WRAPPED"' EXIT

pass=0
fail=0
files=()
for dir in "${PLUGINS[@]}"; do
  rows="$(manifest "$dir")" || { echo "FAIL  $dir: the manifest does not load" >&2; fail=$((fail + 1)); continue; }
  while IFS='|' read -r name scaffold sample dirs; do
    [ -n "$name" ] || continue
    # Compile every directory that a plugin declares, for every kind of plugin.
    # A check that depends on the kind would skip package and prose plugins,
    # and no gate would compile the examples of a corpus with no upstream
    # release to pin. The loader resolves every path, and two corpora may share
    # a directory.
    for sub in $dirs; do
      [ -d "$sub" ] && files+=("$sub"/*.roc)
    done
    # The scaffold that roc_check wraps bare code in. This script checks it,
    # because src/roc_check.test.ts must run without a compiler.
    [ -z "$scaffold" ] && continue
    [ -f "$scaffold" ] && files+=("$scaffold")

    # Fail if a platform has a scaffold and no sample. Without a sample, no gate
    # checks the wrapped code that roc_check sends to the compiler.
    if [ -z "$sample" ] || [ ! -f "$sample" ]; then
      echo "FAIL  scaffolded_$name: no sample in $dir/plugin.json for $name" >&2
      fail=$((fail + 1))
      continue
    fi
    # Run from the repo root, where `scripts/tree.mjs` finds the server's modules
    # for any install. `--plugin=` adds a plugin from outside this repo to the
    # catalog, so its scaffold goes through the loader that the server uses.
    out="$WRAPPED/scaffolded_$name.roc"
    ( cd "$ROOT" && SAMPLE_FILE="$sample" SCOPE="$name" node --input-type=module -e '
const { load } = await import("./scripts/tree.mjs");
const [m, S] = [await load("roc_check"), await load("scopes")];
const { writeFileSync, readFileSync } = await import("node:fs");
const code = readFileSync(process.env.SAMPLE_FILE, "utf-8");
const catalog = S.loadCatalog(process.argv.slice(2), process.env);
writeFileSync(process.argv[1], m.scaffold(code, process.env.SCOPE, catalog).source);
' "$out" "--plugin=$dir" )
    # Fail here, because an empty or missing file would reach the compiler as
    # "file not found", which looks like a broken scaffold.
    if [ ! -s "$out" ]; then
      echo "FAIL  scaffolded_$name: the scaffold produced no source" >&2
      fail=$((fail + 1))
      continue
    fi
    files+=("$out")
  done <<<"$rows"
done

# Each agentic eval run starts from the eval fixture and edits it. If the
# fixture does not compile, no model can pass the task.
[ "$#" -eq 0 ] && files+=("$ROOT/eval/fixture/main.roc")

# A nightly can make `roc check` hang (nightly 2026-10-04 did, on an old
# basic-cli topic), so each file has a deadline. The first run downloads the
# platforms, so the deadline is minutes, not seconds.
deadline=${ROC_CHECK_TIMEOUT:-300}

# Each program is checked with the nightly it was written for, so a platform
# with no release for the bundled nightly does not fail the gate. The nightly is
# the `roc:` pin of the program, else the `compiler` line in the UPSTREAM file
# of the platform release it pins, else the running compiler. Unpack each such
# nightly at the repo root, as roc_nightly-<target>-<date>-<commit>/.
RUNNING="$("$ROC" version 2>/dev/null)"
NIGHTLIES="$(node "$ROOT/scripts/nightlies.mjs" "$@")" || { echo "FAIL  the UPSTREAM nightlies do not load" >&2; exit 1; }

# Prints the compiler for file $1. Prints the reason and fails when the nightly
# is not at the repo root.
compiler_for() {
  local pin release nightly dir
  pin=$(grep -m1 -oE '^\s*roc:\s*"nightly-[^"]+"' "$1" | grep -oE 'nightly-[^"]+')
  if [ -z "$pin" ]; then
    while IFS='|' read -r release nightly; do
      [ -n "$release" ] && grep -qF "\"$release\"" "$1" && { pin="$nightly"; break; }
    done <<<"$NIGHTLIES"
  fi
  if [ -z "$pin" ] || [[ "$RUNNING" == *"$pin"* ]]; then printf '%s' "$ROC"; return; fi
  for dir in "$ROOT"/roc_nightly-*-"${pin#nightly-}"/; do
    [ -x "${dir}roc" ] && { printf '%s' "${dir}roc"; return; }
  done
  printf 'needs %s. Unpack that nightly at the repo root' "$pin"
  return 1
}

check() {
  local out code roc
  roc=$(compiler_for "$1") || { printf '%s' "$roc"; return; }
  out=$(timeout "$deadline" "$roc" check --no-color "$1" 2>&1)
  code=$?
  [ "$code" -eq 124 ] && out="roc check did not finish in ${deadline}s (set ROC_CHECK_TIMEOUT)"
  [ "$code" -ge 128 ] && [ "$code" -ne 124 ] && out="roc check died with signal $((code - 128))"$'\n'"$out"
  printf '%s' "$out"
}

# Each override names a release that does not build on the pinned nightly, and
# a patch with the upstream fix that is not released yet. The script first
# compiles each file as written. If that fails and the file pins an overridden
# release, the script compiles a copy of the file against a patched copy of the
# release. The served files do not change, and each file names the release
# that a user gets. npm does not ship this list, so `plugin validate` in an
# install checks every plugin against the published release.
OVERRIDES="$ROOT/scripts/gate-overrides.json"

# Writes the copy of $1 at $2, pinned to patched releases under $3. Prints the
# patches it used, and nothing when no override applies.
override() {
  [ -f "$OVERRIDES" ] || return 0
  ( cd "$ROOT" && node --input-type=module -e '
const { load } = await import("./scripts/tree.mjs");
const R = await load("release");
const fs = await import("node:fs");
const path = await import("node:path");
const { execFileSync } = await import("node:child_process");
const [file, copy, work, overrides] = process.argv.slice(1);
let text = fs.readFileSync(file, "utf-8");
const used = [];
for (const o of JSON.parse(fs.readFileSync(overrides, "utf-8"))) {
  if (!text.includes(`"${o.release}"`)) continue;
  const cached = R.cachedReleaseDir(o.release);
  if (!cached) throw new Error(`${o.release} is not in the package cache`);
  const pkg = path.join(work, R.releaseHash(o.release));
  if (!fs.existsSync(pkg)) {
    fs.cpSync(cached, pkg, { recursive: true });
    execFileSync("patch", ["-p1", "--forward", "--silent", "-d", pkg, "-i", path.resolve(o.patch)]);
  }
  // Roc rejects an absolute path for a platform, so the pin is relative to the copy.
  text = text.replaceAll(`"${o.release}"`, JSON.stringify(path.relative(path.dirname(copy), path.join(pkg, "main.roc"))));
  used.push(path.basename(o.patch));
}
if (used.length > 0) {
  // Copy the files next to the app too, because an app can import a sibling
  // file such as `todos.html`. Do not copy directories. The scaffolded apps are
  // in the work tree that holds the copy, so a recursive copy copies the tree
  // into itself.
  fs.mkdirSync(path.dirname(copy), { recursive: true });
  for (const e of fs.readdirSync(path.dirname(file), { withFileTypes: true })) {
    if (e.isFile()) fs.copyFileSync(path.join(path.dirname(file), e.name), path.join(path.dirname(copy), e.name));
  }
  fs.writeFileSync(copy, text);
  console.log(used.join(", "));
}
' "$1" "$2" "$3" "$OVERRIDES" )
}

overridden=0
# Two corpora of one plugin may share a directory, and one check is enough.
declare -A seen=()
for f in "${files[@]}"; do
  [ -n "${seen[$f]:-}" ] && continue
  seen[$f]=1
  b=$(basename "$f" .roc)
  out=$(check "$f")
  if ! grep -qE '^No errors found' <<<"$out"; then
    copy="$WRAPPED/override/${#seen[@]}/$b.roc"
    if ! used=$(override "$f" "$copy" "$WRAPPED/releases" 2>"$WRAPPED/override.err"); then
      out="$out"$'\n'"the override did not apply: $(tail -n 3 "$WRAPPED/override.err")"
    elif [ -n "$used" ]; then
      out=$(check "$copy")
      # The compiler prints the path of the copy as absolute and as relative.
      # Replace both with the path of the original file.
      out="${out//"$(realpath --relative-to=. "$copy" 2>/dev/null)"/"$(realpath --relative-to=. "$f" 2>/dev/null)"}"
      out="${out//"$copy"/"$f"}"
      if grep -qE '^No errors found' <<<"$out"; then
        echo "ok    $b (override: $used)"; pass=$((pass + 1)); overridden=$((overridden + 1))
        continue
      fi
      b="$b (override: $used)"
    fi
  fi
  if grep -qE '^No errors found' <<<"$out"; then
    echo "ok    $b"; pass=$((pass + 1))
  else
    echo "FAIL  $b"; sed 's/^/      /' <<<"$out"; fail=$((fail + 1))
  fi
done

echo
echo "pass=$pass fail=$fail"
# Report the overrides, because each of these files passed only against a
# patched release.
[ "$overridden" -eq 0 ] || echo "override=$overridden (see scripts/gate-overrides.json)"
[ "$fail" -eq 0 ] || exit 1
