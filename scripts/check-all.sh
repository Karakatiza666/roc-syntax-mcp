#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
# SPDX-License-Identifier: MPL-2.0

# Runs every gate of this repo (the build, the tests and the `check:*` scripts)
# in one run. Run it by hand. `build` and `prepare` do not call it, because four
# of the gates need a Roc toolchain, and `prepare` runs on the user's machine
# when they install the package from git.
#
# The script does not stop at the first failure, so that one failed gate does
# not hide the result of the others. The summary marks each gate that it
# skipped because no compiler is installed.
#
# Usage: ROC=/path/to/roc bun run check
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

names=(); codes=()

run() {
  local name="$1"; shift
  echo
  echo "=== $name ==="
  "$@"
  local code=$?
  names+=("$name"); codes+=("$code")
}

run "build"           npx tsc --noEmit
run "test"            node --import tsx/esm --import ./src/testdata/isolate.ts --test src/*.test.ts
run "check:index"     node --import tsx/esm scripts/build-index.ts --check
run "check:roc"       scripts/check-roc.sh
run "check:platforms" scripts/check-platform-examples.sh
run "check:detection" scripts/check-detection.sh
run "check:roc-check" node scripts/check-roc-check.mjs

echo
echo "=== summary ==="
fail=0
for i in "${!names[@]}"; do
  case "${codes[$i]}" in
    # A script that needs roc exits with 2 when no compiler is on PATH. Report
    # that gate as skipped, not as passed.
    0) printf 'ok      %s\n' "${names[$i]}" ;;
    2) printf 'skipped %s (no roc, set ROC=/path/to/roc)\n' "${names[$i]}" ;;
    *) printf 'FAIL    %s (exit %s)\n' "${names[$i]}" "${codes[$i]}"; fail=1 ;;
  esac
done
exit "$fail"
