#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
# SPDX-License-Identifier: MPL-2.0

# Type-checks every bundled .roc file with a real Roc compiler.
#
# Usage: ROC=/path/to/roc scripts/check-roc.sh
set -uo pipefail

ROC="${ROC:-roc}"
command -v "$ROC" >/dev/null 2>&1 || { echo "roc not found. Set ROC=/path/to/roc" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0

# all_roc_syntax.roc imports `../../README.md` relative to upstream's test/echo/,
# so check it in a copy of that directory layout.
mkdir -p "$WORK/ref/test/echo"
cp "$ROOT/README.md" "$WORK/ref/README.md"
cp "$ROOT/corpus/language/examples/all_roc_syntax.roc" "$WORK/ref/test/echo/all_syntax_test.roc"
out=$("$ROC" check --no-color "$WORK/ref/test/echo/all_syntax_test.roc" 2>&1)
if grep -qE '^No errors found' <<<"$out"; then
  echo "ok    all_roc_syntax.roc"
else
  echo "FAIL  all_roc_syntax.roc"; sed 's/^/      /' <<<"$out"; fail=1
fi

# The repo's own Roc scripts must type-check and pass their `expect`s before
# one of them checks the topics.
for f in "$ROOT"/scripts/*.roc; do
  b=$(basename "$f")
  out=$("$ROC" test --no-color "$f" 2>&1)
  if grep -qE '^All \([0-9]+\) tests passed' <<<"$out"; then
    echo "ok    scripts/$b"
  else
    echo "FAIL  scripts/$b"; sed 's/^/      /' <<<"$out"; fail=1
  fi
done

# check-topics.roc runs `roc check` and `roc test` on every language topic, and
# checks the `@rejects` and `@warns` claims in its comments.
mkdir -p "$WORK/topics"
"$ROC" "$ROOT/scripts/check-topics.roc" -- "$ROC" "$ROOT/corpus/language/topics" "$WORK/topics" || fail=1

# A `.md` topic shows the files of a package repo as snippets. Each snippet is
# a line with the path in backticks, then a fenced block. This step writes the
# snippets of all `.md` topics into one repo and runs its scripts. bundle.sh
# runs before test_bundle.sh, because test_bundle.sh reads dist/*.tar.zst.
materialize() { # $1 = topic file, $2 = repo dir
  local path="" file="" line
  while IFS= read -r line; do
    if [ -n "$file" ]; then
      if [ "$line" = '```' ]; then file=""; else printf '%s\n' "$line" >>"$file"; fi
    elif [[ $line =~ ^\`([^\`]+)\`$ ]]; then
      path="${BASH_REMATCH[1]}"
    elif [ -n "$path" ] && [[ $line == '```'* ]]; then
      file="$2/$path"; mkdir -p "$(dirname "$file")"; : >"$file"; path=""
    else
      path=""
    fi
  done <"$1"
}
mkdir -p "$WORK/repo"
for f in "$ROOT"/corpus/language/topics/*.md; do materialize "$f" "$WORK/repo"; done
for s in all_tests.sh bundle.sh test_bundle.sh; do
  [ -f "$WORK/repo/scripts/$s" ] || continue
  if out=$(cd "$WORK/repo" && ROC="$ROC" bash "scripts/$s" 2>&1); then
    echo "ok    topic repo scripts/$s"
  else
    echo "FAIL  topic repo scripts/$s"; sed 's/^/      /' <<<"$out"; fail=1
  fi
done

# The section map must have one line for each langref section. src/langref.test.ts
# checks the same map against the parser in src/langref.ts.
"$ROC" "$ROOT/scripts/langref-diff.roc" -- --check-map || fail=1

if [ "$fail" -eq 0 ]; then echo; echo "all bundled .roc files check clean"; fi
exit "$fail"
