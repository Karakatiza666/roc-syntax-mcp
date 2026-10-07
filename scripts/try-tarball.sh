#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
# SPDX-License-Identifier: MPL-2.0

# Installs the tarballs that `npm publish` would upload, as a user would: the
# server globally with npm, and the plugins with `plugin add`. It removes every
# installed server and plugin first. It publishes nothing, and it downloads only
# the dependencies of the server from the registry.
#
# Usage:
#   scripts/try-tarball.sh [--claude] [plugin...]   install (a plugin is a dir under plugins/, default all)
#   scripts/try-tarball.sh --no-plugins [--claude]  install the server only
#   scripts/try-tarball.sh --cleanup                remove what the last install added
#
# --claude also registers `roc-syntax` in Claude Code at user scope. It stops
# with an error if an entry with that name exists. --cleanup removes the entry
# only if this script added it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="${XDG_CACHE_HOME:-$HOME/.cache}/roc-syntax-mcp-try-tarball"
# The tarballs stay here until --cleanup, because `plugin add` records each plugin by its path.

# Must match pluginHome in src/plugins.ts.
if [[ -n "${ROC_MCP_HOME:-}" ]]; then
  MCP_HOME="$ROC_MCP_HOME"
elif [[ "$(uname)" == Darwin ]]; then
  MCP_HOME="$HOME/Library/Application Support/roc-syntax-mcp"
else
  MCP_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/roc-syntax-mcp"
fi

say() { printf '\n== %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Removes the server from each global package manager that has it, and removes
# every plugin that `plugin add` installed. It keeps a compiler that
# `roc install` downloaded.
clear_installs() {
  if npm ls -g --depth=0 roc-syntax-mcp >/dev/null 2>&1; then npm uninstall -g roc-syntax-mcp; fi
  if command -v pnpm >/dev/null && pnpm ls -g --depth=0 2>/dev/null | grep -q '^roc-syntax-mcp '; then pnpm remove -g roc-syntax-mcp; fi
  if command -v bun >/dev/null && [[ -e "$HOME/.bun/install/global/node_modules/roc-syntax-mcp" ]]; then bun remove -g roc-syntax-mcp; fi
  rm -rf "$MCP_HOME/plugins"
  hash -r
  if command -v roc-syntax-mcp >/dev/null; then
    die "roc-syntax-mcp is still on PATH at $(command -v roc-syntax-mcp). Remove it by hand"
  fi
}

cleanup() {
  say "Removing the server and its plugins"
  local claude_added=false
  [[ -f "$STAGE/claude-added" ]] && claude_added=true
  clear_installs
  rmdir "$MCP_HOME" 2>/dev/null || true
  rm -rf "$STAGE"
  if $claude_added; then
    say "Removing roc-syntax from Claude Code"
    claude mcp remove --scope user roc-syntax
  fi
  echo "Done."
}

claude=false
no_plugins=false
plugins=()
for arg in "$@"; do
  case "$arg" in
    --cleanup) cleanup; exit 0 ;;
    --claude) claude=true ;;
    --no-plugins) no_plugins=true ;;
    -h | --help) sed -n '5,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option $arg" ;;
    *) [[ -f "$ROOT/plugins/$arg/plugin.json" ]] || die "no plugin at plugins/$arg"; plugins+=("$arg") ;;
  esac
done
if $no_plugins; then
  ((${#plugins[@]} == 0)) || die "--no-plugins and a plugin name were both given"
elif ((${#plugins[@]} == 0)); then
  for d in "$ROOT"/plugins/*/plugin.json; do plugins+=("$(basename "$(dirname "$d")")"); done
fi
if $claude && claude mcp get roc-syntax >/dev/null 2>&1; then
  die "Claude Code already has an entry named roc-syntax. Remove it first: claude mcp remove roc-syntax"
fi

say "Removing installed versions"
clear_installs
rm -rf "$STAGE"
mkdir -p "$STAGE"

say "Packing the server as publish-server.yml does"
(cd "$ROOT" && npm run build:ts)
# registry-files.mjs edits package.json in place, so the trap restores the original on any exit.
cp "$ROOT/package.json" "$STAGE/package.json.orig"
trap 'cp "$STAGE/package.json.orig" "$ROOT/package.json"' EXIT
node "$ROOT/scripts/registry-files.mjs"
server_tgz="$STAGE/$(cd "$ROOT" && npm pack --silent --pack-destination "$STAGE")"
cp "$STAGE/package.json.orig" "$ROOT/package.json"
trap - EXIT
if tar -tzf "$server_tgz" | grep -q '^package/src/'; then die "$server_tgz ships src/"; fi
echo "$server_tgz"

plugin_tgzs=()
for p in "${plugins[@]}"; do
  say "Packing plugins/$p"
  plugin_tgzs+=("$STAGE/$(cd "$ROOT/plugins/$p" && npm pack --silent --pack-destination "$STAGE")")
  echo "${plugin_tgzs[-1]}"
done

say "Installing the server"
npm install -g "$server_tgz"
hash -r
command -v roc-syntax-mcp >/dev/null || die "npm installed the server, but roc-syntax-mcp is not on PATH"

# Run from the stage directory, so that no command reads a project config of this repo.
cd "$STAGE"
if ((${#plugin_tgzs[@]} > 0)); then
  say "Adding plugins"
  roc-syntax-mcp plugin add "${plugin_tgzs[@]}"
  roc-syntax-mcp plugin list
fi

say "Starting the server"
out="$(timeout 30 roc-syntax-mcp </dev/null 2>&1)" || true
echo "$out"
grep -qF "roc-syntax-mcp: serving MCP over stdio" <<<"$out" || die "the server did not start"

if $claude; then
  say "Registering roc-syntax in Claude Code"
  claude mcp add --scope user roc-syntax -- roc-syntax-mcp
  touch "$STAGE/claude-added"
fi

say "Installed"
echo "Server: $(command -v roc-syntax-mcp)"
echo "Plugins: $MCP_HOME/plugins"
echo "Remove it all with: scripts/try-tarball.sh --cleanup"
