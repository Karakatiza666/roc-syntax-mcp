# The `roc` command line: which command to use when, and the pitfalls that
# `roc help` does not show. For every flag, run `roc <command> --help`. Flags
# you recall from the old compiler (`--optimize`, `--linker`, `roc dev`) do not
# exist here.
#
# Measured on nightly-2026-10-04-130536d.

# ---------------------------------------------------------------------------
# The loop: check, test, run, build
# ---------------------------------------------------------------------------
#
#   roc check app.roc         type-check only. Fastest. Use after each edit
#   roc test app.roc          run the top-level `expect`s, as below
#   roc run app.roc -- a b    compile and run, passing `a b` to the app
#   roc build app.roc         write an optimized binary, `app`, to the current
#                             directory. `--output=<path>` puts it elsewhere
#
# A bare `roc app.roc` runs the app, the same as `roc run`. It does more than
# compile. Use `roc check` when you only want the errors.
#
# Each command defaults to `main.roc` when you give no file.

expect [1, 2, 3].len() == 3

# ---------------------------------------------------------------------------
# Exit codes
# ---------------------------------------------------------------------------
#
#   command          0       1                         2
#   roc check        clean   errors                    warnings only
#   roc test         passed  errors, or an `expect`    -
#                            failed
#   roc build        clean   errors                    warnings. The binary
#                                                      is still written
#   roc run          clean   errors, or a `dbg` ran    warnings, even if the
#                            even if the app succeeded app succeeded
#
# So a non-zero `roc run` does not mean the app failed. Read the output. Remove
# every `dbg` and fix every warning, and the exit code is the app's own.

# ---------------------------------------------------------------------------
# Optimization: --opt
# ---------------------------------------------------------------------------
#
#   dev           native dev backend, fast compile. Default for run, test, repl
#   speed         LLVM, optimized. Default for build
#   size          LLVM, optimized for binary size
#   interpreter   embedded interpreter
#
# So by default `roc run` and `roc build` use different backends. A bug that
# shows only under `--opt=speed` does not show in `roc run`. Reproduce it with
# `roc run --opt=speed app.roc`.
#
# `dbg` still prints in an optimized build. `roc build` warns once for each
# `dbg` (exit 2), so remove them before you ship.

# ---------------------------------------------------------------------------
# Targets: --target (build)
# ---------------------------------------------------------------------------
#
#   x64musl, x64glibc, arm64musl, ...   a `v1` in the name (x64v1musl) targets
#                                       the oldest CPUs of that architecture
#
# Default: the native architecture, with musl for static linking. The platform
# header's `targets` section lists what a platform supports, and without
# `--target` the build uses its first compatible entry. See the `platforms`
# topic.

# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------
#
#   roc fmt app.roc            rewrites the file in place
#   roc fmt                    rewrites every .roc file in the current directory
#   roc fmt --check app.roc    exit 1 if a file needs formatting. Writes nothing
#   roc fmt --stdin            formats stdin to stdout
#
# `roc fmt` also rewrites a header's nightly pin to the running nightly when
# that one is newer. `--check` reports a stale pin as needing formatting.

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------
#
#   roc deps app.roc     print every declared package source, in full
#   --replace-dep OLD NEW
#                        load NEW wherever a dependency declares exactly OLD,
#                        for this one command. NEW is a package URL or a path
#                        to a root .roc file. Works on check, test, run, build
#                        and docs, and you can repeat it.
#
# To try a local fork of a platform without editing the header:
#
#   roc deps app.roc     copy the platform URL it prints, then
#   roc check app.roc --replace-dep "<that URL>" ../basic-cli/platform/main.roc

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------
#
#   roc docs main.roc          HTML docs into ./generated-docs
#                              (--output=<dir>, --serve to view them)
#   roc bundle main.roc A.roc  a .tar.zst named by its content hash: the URL
#                              others put in their headers
#   roc bump main.roc --old <previous URL, bundle or dir>
#                              the semver bump the public API change needs.
#                              --expect X.Y.Z fails in CI if a release under-bumps
#   roc install <name> <URL>   build a bundled app once with --opt=speed, then
#                              run it with `roc run <name>`

# ---------------------------------------------------------------------------
# Glue: bindings for a platform host
# ---------------------------------------------------------------------------
#
#   roc glue --no-cache <spec.roc> <out-dir>/ <platform/main.roc>
#
# A glue spec is a Roc app that writes host-language bindings for a platform's
# types, layouts and ownership rules. Upstream ships three, in roc-lang/roc at
# src/glue/src/: ZigGlue.roc, RustGlue.roc and CGlue.roc. They are in the
# nightly's source archive (roc_nightly-source-*), not in the binary one. Each
# writes one file, roc_platform_abi.zig, .rs or .h.
#
# Pass --no-cache. Without it, a second spec returns the first spec's output:
# RustGlue.roc after ZigGlue.roc writes roc_platform_abi.zig again.
#
# Use generated glue rather than hand-written structs. The ABI carries field
# order, padding, discriminants and refcounting that the Roc source does not
# show. See the `platforms` topic.

# ---------------------------------------------------------------------------
# Commands that an agent must not use
# ---------------------------------------------------------------------------
#
#   roc repl                  interactive. It waits for input. Write an
#                             `expect` and run `roc test` instead
#   --watch                   on check, test and build. It never exits
#   roc experimental-lsp      a language server for an editor
