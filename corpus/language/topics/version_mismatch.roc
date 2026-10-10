# What to do when a platform release or a package release does not compile.
#
# Each release was built and tested with one Roc nightly. Another nightly can
# reject it, and then the build fails in code that you did not write. Do the
# steps below in order, and do each step once. Do not try nightlies one by
# one. The repo of each release records its nightly, so read it there.
#
# Measured on nightly-2026-10-09-258ab27, basic-webserver 0.17.0, basic-cli
# 0.25.0 and roc-parser 2.0.0.

# ---------------------------------------------------------------------------
# 1. Find the file of the error
# ---------------------------------------------------------------------------
#
# The first line of each report names the file:
#
#   ── ✗ type mismatch ─ ../../.cache/roc/packages/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT/Path.roc:661:9
#
#   The path holds              The error is in       Next
#   a file of your project      your code             fix the code. Stop here
#   roc/packages/<hash>/        a release             step 2
#
# The <hash> is the last part of a release URL, before `.tar.zst`. `roc deps
# app.roc` prints the URL of each release in the build, under the header that
# pins it.
#
# - Only an error (✗) needs these steps. A warning (●) in a release does not
#   stop the build. Ignore it.
# - An error in a release stays an error when `roc run` starts or `roc build`
#   writes a binary. The code with the error crashes or hangs when it runs.
#   basic-webserver 0.17.0 on 258ab27 builds with 3 errors, and a request that
#   interpolates a `Path` hangs.
# - The compiler checks only the modules that the build imports. So one app
#   that uses a package can build, and another app that uses it can fail.
#
# If the app header pins a nightly (`roc: "nightly-..."`) and you run another
# one, the compiler warns "roc version mismatch" and names the pinned nightly.
# Switch to the pinned nightly (step 3) before you do anything else.

# ---------------------------------------------------------------------------
# 2. Read the nightly of a release
# ---------------------------------------------------------------------------
#
# The release URL names the repo and the tag:
#
#   https://github.com/<owner>/<repo>/releases/download/<tag>/<hash>.tar.zst
#
# The tarball holds no nightly pin. Read the pin from the repo at <tag>. Do not
# read the default branch, because it changes after the release.
#
#   git clone -q --depth 1 --branch <tag> https://github.com/<owner>/<repo> rel
#   cd rel
#   cat .roc-version                                                    # 1
#   grep -rhoE 'nightly-tag: *nightly-[^ ]+' .github/workflows | sort | uniq -c   # 2
#   grep -rhoE '^\s*roc: *"nightly-[^"]+"' --include=*.roc examples | sort | uniq -c  # 3
#
# Use the first source that names a nightly:
#   1. `.roc-version`. The whole file is one nightly tag.
#   2. `nightly-tag:` in the workflows, the input of roc-lang/setup-roc.
#   3. The `roc:` entry in the headers of the examples. If they disagree, use
#      the nightly that most examples pin.
#   4. None of the above. The CI then installs the newest nightly, so use the
#      newest nightly published before the release:
#
#        gh release view <tag> --repo <owner>/<repo> --json publishedAt --jq .publishedAt
#        gh release list --repo roc-lang/nightlies --limit 1000 --json tagName,publishedAt \
#          --jq '[.[] | select(.publishedAt < "<publishedAt>")] | max_by(.publishedAt) | .tagName'
#
#      This nightly is an estimate. If the release fails on it, go to step 5.
#      Do not try the nightlies before and after it.
#
#   Release                  Source           Nightly
#   basic-webserver 0.17.0   .roc-version     nightly-2026-10-04-130536d
#   basic-cli 0.25.0         nightly-tag:     nightly-2026-10-09-258ab27
#   roc-parser 2.0.0         .roc-version     nightly-2026-09-29-7f11a82
#   http 1.0.0               none, rule 4     nightly-2026-July-05-c0cae66
#
# Old tags spell the month (`nightly-2026-July-05-...`). Copy a tag exactly.

# ---------------------------------------------------------------------------
# 3. Switch the compiler
# ---------------------------------------------------------------------------
#
#   roc-syntax-mcp roc install <nightly>
#
# This command downloads the nightly, and from the next call `roc_check` and
# `roc_fmt` use it. It prints the path of the binary. Use that path in the
# shell, because the `roc` on PATH does not change. `roc-syntax-mcp roc
# install` with no nightly installs the nightly that this server documents.
#
# Without this server, download the asset for the machine (linux_x86_64,
# linux_arm64, macos_apple_silicon, macos_x86_64, or windows_x86_64 as a .zip):
#
#   gh release download <nightly> --repo roc-lang/nightlies --pattern 'roc_nightly-linux_x86_64-*'
#   tar -xzf roc_nightly-linux_x86_64-*.tar.gz     # the binary is ./roc_nightly-*/roc
#
# Then pin the nightly in the app header, so that the code records the choice:
#
#   app [main!] { pf: platform "<URL>", roc: "nightly-2026-10-04-130536d" }
#
# Another compiler then warns "roc version mismatch" and names this nightly.
# Run `roc fmt` only with the pinned compiler. A newer `roc fmt` rewrites the
# pin to its own nightly.

# ---------------------------------------------------------------------------
# 4. Choose the nightly
# ---------------------------------------------------------------------------
#
# One build uses one compiler. So every release with an error must accept the
# nightly that you choose. Keep the platform release, and change a package
# release first. The platform release sets the API of the whole app, and a
# package release changes only the modules of that package.
#
#   The error is in                             Do this
#   the platform                                use the nightly of the platform
#   a package that the platform header also     put the URL that the platform pins in the
#     pins (`roc deps` shows it under the       app header, and use the nightly of the
#     platform)                                 platform
#   another package, with the same nightly      the release fails on its own nightly.
#     as the platform                           Go to step 5
#   another package, with another nightly       keep the nightly of the platform. Use the
#                                               package release that has the same nightly,
#                                               else the newest release with an older
#                                               nightly. Read each one with step 2. Try
#                                               2 releases at most
#   a package, and no release of it accepts     use the platform release that has the
#     the nightly of the platform               nightly of the package, if the app needs
#                                               nothing from a newer platform release
#   your code, after the switch                 your code uses syntax or builtins of a
#                                               newer nightly. Fix the code for this
#                                               compiler
#
# - A package URL in the app with a higher version of the same major makes the
#   whole build use it, the platform included. See the `packages` topic. So do
#   not move a package that the platform pins to a newer release than the
#   platform pins.
# - This server documents the nightly that `roc-syntax-mcp roc` prints as
#   "bundled nightly". On another nightly, a few names and types can be
#   different. Where the compiler and these docs do not agree, the compiler is
#   correct. Do not switch the nightly again because of an error in your own
#   code.

# ---------------------------------------------------------------------------
# 5. Stop and report
# ---------------------------------------------------------------------------
#
# Stop, and tell the user, when one of these is true:
#   - A release fails on its own nightly.
#   - Two releases need different nightlies, and no other pair of releases
#     shares a nightly.
#   - You did the steps above, and the error is still in a release.
#
# For each release with an error, give the URL, its nightly, the source of
# that nightly, and the first error. Then give these options:
#   - Wait for a new release, or ask upstream for one. An open pull request
#     that updates the nightly is not a release.
#   - For a package, use the source of the upstream default branch, if it has
#     the fix. `--replace-dep` loads it for one command and edits no file:
#
#       git clone -q --depth 1 https://github.com/<owner>/<repo> dep
#       roc check app.roc --replace-dep "<release URL>" ./dep/<dir>/main.roc
#
#     <dir> is the directory of the root module, often `package` or `src`.
#     A platform from source needs its host built first. See `platforms`.
#   - Remove the package, or use another package for the same job.
#
# At every step, do not:
#   - Edit a file in roc/packages/. Every project on this machine uses that
#     copy, and no other machine gets the edit.
#   - Change the hash of a release URL by hand. The hash is the content, so a
#     wrong hash fails the download.
#   - Ignore an error in a release because the program runs.
