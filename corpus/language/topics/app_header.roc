# Application file structure.
#
# A Roc `.roc` file can be:
#   1. A headerless app: only a `main!` function and no header. It gets the
#      built-in Echo platform, so `echo!` is in scope unqualified and needs no
#      import. Run it with `roc main.roc`.
#   2. An `app` header naming no platform, which also gets the Echo platform.
#      The header exists only to declare packages. `app [main!] {}` is exactly
#      the same as writing no header at all. (This needs the 2026-08-23 nightly
#      or newer. The 2026-08-22 nightly rejects it as `missing platform`.)
#   3. A full `app` header naming a platform and entrypoint(s).

# --- 1. Headerless app (simplest possible Roc program) ---
# (Put this in a file by itself and run `roc main.roc`.)
#
# main! = |_args| {
#     echo!("Hello, World!\n")
#     Ok({})
# }
#
# `echo!` writes its string unchanged and appends no newline, so the `\n` is
# explicit. See the `effects` topic.
#
# The trailing `Ok({})` is required because `echo!` evaluates to `{}`, but the Echo
# platform requires `main!` to return `Try(_, [Exit(I8), ..])`. Upstream's
# langref shows `main! = |_args| echo!("Hello, World!")` as a one-liner, which
# does not type-check for this reason.
#
# The Echo platform's `main!` receives command-line arguments as a `List(Str)`
# and returns `Try(_, [Exit(I8), ..])`:
#
#   requires { main! : List(Str) => Try(_, [Exit(I8), ..]) }
#
# So `Err(Exit(2))` sets the process exit code to 2. The platform prints any
# other `Err` with `Str.inspect` and exits with code 1. The Echo platform has
# only one effect by design, because it is for teaching and not for production.

# --- 2. App header with packages but no platform ---
# This app also gets the Echo platform and an unqualified `echo!`.
#
# app [main!] {
#     unicode: "https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst",
# }
#
# import unicode.Grapheme
#
# main! = |_| {
#     echo!(Grapheme.owned("café") |> Str.inspect)
#     Ok({})
# }

# --- 3. App with a platform header ---
# Tell Roc which platform provides I/O and what the entrypoint is.
#
# app [main!] { pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-zig/releases/download/1.0.0/AnZoxzoGPtSGQ15EQh6pBeeaHJ7aizP9MQhK81dES3Uq.tar.zst" }
#
# import pf.Stdout
#
# main! = |_args| {
#     Stdout.line!("Hello from a platformed app!")
#     Ok({})
# }

# Notes:
#   - `app [main!]` lists the entrypoint(s) the platform expects, usually `main!`.
#   - `{ pf: platform "<url>" }` gives the platform URL. Other packages can be
#     listed alongside: `{ pf: platform "...", json: "..." }`. A header can
#     name only one platform. A second one is a "multiple platforms" error.
#   - The platform provides every effectful function. The standard library
#     (Builtin.roc) is pure.
#   - The entrypoint's exact signature is set by the platform's `requires`
#     clause. See the `platforms` topic.
#   - A `package [...]` header may name a platform the same way, and then the
#     package can call that platform's API. Every platform declaration in the
#     dependency graph has to be the identical URL, version and content hash,
#     or a path to the same root file ("platform dependency mismatch"). The
#     app is still the only module that satisfies `requires`. See `packages`.
