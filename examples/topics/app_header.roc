# Application file structure.
#
# A Roc `.roc` file can be either:
#   1. A "headerless app" — just a `main!` function, no header. The new
#      compiler will run it directly with `roc main.roc`. Use this for quick
#      scripts; `echo!` is built-in so you don't even need imports.
#   2. A full `app` declaration that specifies the platform and entrypoint(s).

# --- Headerless app (simplest possible Roc program) ---
# (Put this in a file by itself and run `roc main.roc`.)
#
# main! = |_args| {
#     echo!("Hello, World!")
#     Ok({})
# }

# --- App with platform header ---
# Tell Roc which platform provides I/O and what the entrypoint is.
#
# app [main!] { pf: platform "https://github.com/lukewilliamboswell/roc-platform-template-zig/releases/download/0.6/2BfGn4M9uWJNhDVeMghGeXNVDFijMfPsmmVeo6M4QjKX.tar.zst" }
#
# import pf.Stdout
#
# main! = |_args| {
#     Stdout.line!("Hello from a platformed app!")
#     Ok({})
# }

# Notes:
#   - `app [main!]` — the entrypoint(s) the platform expects (usually `main!`).
#   - `{ pf: platform "<url>" }` — the platform URL. Other deps can be listed
#     alongside: `{ pf: platform "...", pg: "..." }`.
#   - The platform provides every effectful function. The standard library
#     (Builtin.roc) is pure.
