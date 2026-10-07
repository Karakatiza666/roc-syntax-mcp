#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
# SPDX-License-Identifier: MPL-2.0

# Adds the CLA.md line (the `Contribution-License` trailer) to every commit on
# this branch that does not have it, then tells you to force-push.
#
# Usage: scripts/sign-branch.sh [base]
# The default base is upstream/main if it exists, else origin/main.
set -euo pipefail

TRAILER="Contribution-License: UPL-1.0 (CLA.md v1)"

base="${1:-}"
if [[ -z "$base" ]]; then
  if git rev-parse -q --verify upstream/main >/dev/null; then base=upstream/main; else base=origin/main; fi
fi
fork_point="$(git merge-base "$base" HEAD)"

if [[ -z "$(git rev-list "$fork_point..HEAD")" ]]; then
  echo "No commits after $base. Nothing to sign."
  exit 0
fi

# A commit that has the CLA.md line anywhere in its message stays unchanged.
git rebase --quiet \
  --exec "git log -1 --format=%B | tr -d '\\r' | grep -qxF '$TRAILER' || git commit --quiet --amend --no-edit --trailer '$TRAILER'" \
  "$fork_point"

echo "Every commit after $base now has the CLA.md line."
echo "Push with: git push --force-with-lease"
