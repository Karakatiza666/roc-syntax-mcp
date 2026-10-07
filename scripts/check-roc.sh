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

# Topic files are fragments, so append a minimal `main!` to each one.
for f in "$ROOT"/corpus/language/topics/*.roc; do
  b=$(basename "$f" .roc)
  { cat "$f"; printf '\nmain! = |_args| Ok({})\n'; } > "$WORK/$b.roc"
  out=$("$ROC" check --no-color "$WORK/$b.roc" 2>&1)
  if grep -qE '^No errors found' <<<"$out"; then
    echo "ok    $b"
  else
    echo "FAIL  $b"; sed 's/^/      /' <<<"$out"; fail=1
  fi
done

# The langref overlay pages fill the sections that upstream left as TODO. This
# repo wrote their snippets, so this repo keeps them compiling. The awk script
# puts every ```roc block of a page into one module, as each platform's
# verify/overview-snippets.roc does for its overview page.
#
# The awk script skips a block that starts with a module header. That block is
# a full module, and its dependencies are not on disk here.
for f in "$ROOT"/corpus/language/langref/local/*.md; do
  [ -e "$f" ] || break
  b=$(basename "$f" .md)
  awk '
    /^```roc$/ { inside=1; n=0; next }
    /^```/     { if (inside && n > 0 && buf[1] !~ /^(app|package|platform|module|hosted) /)
                   for (i = 1; i <= n; i++) print buf[i]
                 inside=0; next }
    inside     { buf[++n]=$0 }
  ' "$f" > "$WORK/langref_$b.roc"
  printf '\nmain! = |_args| Ok({})\n' >> "$WORK/langref_$b.roc"
  out=$("$ROC" check --no-color "$WORK/langref_$b.roc" 2>&1)
  if grep -qE '^No errors found' <<<"$out"; then
    echo "ok    langref/local/$b.md"
  else
    echo "FAIL  langref/local/$b.md"; sed 's/^/      /' <<<"$out"; fail=1
  fi
done

if [ "$fail" -eq 0 ]; then echo; echo "all bundled .roc files check clean"; fi
exit "$fail"
