# Writing and maintaining Roc platforms.
#
# A Roc program is split between an **application** (pure Roc the user writes)
# and a **platform** (the I/O primitives, memory allocator, and entry point).
# Every app picks exactly one platform. This topic covers what the platform
# author writes — see https://www.roc-lang.org/platforms for background.
#
# A platform has two parts:
#   1. The **host** (Zig/Rust/C/etc.) — implements `main()`, `malloc`/`free`,
#      and every I/O primitive the platform exposes. It is shipped as a
#      pre-compiled binary (`libhost.a`, plus `.o` files per target).
#   2. The **Roc API** — `.roc` modules that wrap the host's FFI surface in
#      idiomatic Roc types. This is what app authors see.
#
# What follows are the patterns the basic-cli platform uses, distilled from
# https://github.com/roc-lang/basic-cli (new-compiler branch).
#
# ─────────────────────────────────────────────────────────────────────────────
# 1. The platform header (platform/main.roc)
# ─────────────────────────────────────────────────────────────────────────────
#
# platform ""
#     requires {} { main! : List(Str) => Try({}, [Exit(I32), ..]) }
#     exposes [Cmd, Dir, Env, File, IOErr, Locale, Path, Random, Sleep, Stdin, Stdout, Stderr, Tty, Utc]
#     packages {}
#     provides { main_for_host! : "main_for_host" }
#     targets: {
#         files: "targets/",
#         exe: {
#             x64mac:   ["libhost.a", app],
#             arm64mac: ["libhost.a", app],
#             x64musl:  ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"],
#             arm64musl:["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"],
#         }
#     }
#
# Field-by-field:
#   • `requires {} { main! : ... }` — the *shape* an application must provide.
#     The Try's error type is left open (`..`) so apps can return any
#     platform-defined error and still satisfy the constraint.
#   • `exposes [...]` — Roc modules the app can `import pf.X`.
#   • `provides { main_for_host! : "main_for_host" }` — the Roc symbol that
#     the host's C/Zig `main()` resolves and calls. The string is the link
#     name; the Roc name lives in this same `platform/main.roc` file.
#   • `targets:` — per-target file lists. `app` is a placeholder for the
#     compiled Roc application object; the rest are host artifacts the linker
#     combines with it.
#
# ─────────────────────────────────────────────────────────────────────────────
# 2. The entry-point glue: main_for_host!
# ─────────────────────────────────────────────────────────────────────────────
#
# The host expects a function returning a plain `I32` exit code. The app
# returns `Try({}, [Exit(I32), ..])`. `main_for_host!` is the glue:
#
# main_for_host! : List(Str) => I32
# main_for_host! = |args|
#     match main!(args) {
#         Ok({}) => 0
#         Err(Exit(code)) => code
#         Err(other) =>
#             match Stderr.line!("Program exited with error: ${Str.inspect(other)}") {
#                 _ => 1
#             }
#     }
#
# Key points:
#   • Effectful → `=>` arrow, name ends in `!`.
#   • The host-facing signature must be representable in the host's ABI —
#     primitive `I32` here. No tag unions, no open types.
#   • Inspect any unhandled error for diagnostics, then return a non-zero code.
#
# ─────────────────────────────────────────────────────────────────────────────
# 3. Anatomy of a platform module (Stdout.roc)
# ─────────────────────────────────────────────────────────────────────────────
#
# import IOErr exposing [IOErr]
#
# ## Hosted FFI declarations. NOTE the closed Try error types.
# host_stdout_line!        : Str       => Try({}, IOErr)
# host_stdout_write!       : Str       => Try({}, IOErr)
# host_stdout_write_bytes! : List(U8) => Try({}, IOErr)
#
# Stdout := [].{
#     ## Public Roc API. Returns an OPEN tag union so the caller's match can
#     ## be extended by other platform errors composing on top of it.
#     line! : Str => Try({}, [StdoutErr(IOErr), ..])
#     line! = |msg|
#         match host_stdout_line!(msg) {
#             Ok(val) => Ok(val)
#             Err(ioerr) => Err(StdoutErr(ioerr))
#         }
#
#     write! : Str => Try({}, [StdoutErr(IOErr), ..])
#     write! = |msg|
#         match host_stdout_write!(msg) {
#             Ok(val) => Ok(val)
#             Err(ioerr) => Err(StdoutErr(ioerr))
#         }
# }
#
# Conventions:
#   • Module is a NOMINAL type with an empty body — `ModuleName := [].{...}`.
#     This gives you static-dispatch `Stdout.line!(...)` syntax.
#   • Module-level (outside the `.{...}` block) is where `host_*!` declarations
#     live. They are the raw FFI surface.
#   • The shared `IOErr` type lives in its own module (`IOErr := [...]`) so
#     every I/O module can reuse it.
#   • User errors are wrapped: `Err(ioerr) => Err(StdoutErr(ioerr))`. This
#     lets pattern matches distinguish which subsystem failed even when all
#     subsystems use the same underlying `IOErr` shape.
#
# ─────────────────────────────────────────────────────────────────────────────
# 3b. Host-direct method declarations (no wrapper)
# ─────────────────────────────────────────────────────────────────────────────
#
# The Stdout/Stdin/Stderr pattern above (`host_*!` declarations + a wrapper
# inside `.{...}` that tags errors) is the most flexible form. But several
# basic-cli modules use a SIMPLER form: declare the method INSIDE the
# `.{...}` block with a type signature but NO `=` body. The compiler links
# that name directly to the host's exported symbol.
#
# Example — basic-cli's File.roc in full:
#
#   import IOErr exposing [IOErr]
#
#   File := [].{
#       read_bytes!  : Str       => Try(List(U8), [FileErr(IOErr)])
#       write_bytes! : Str, List(U8) => Try({}, [FileErr(IOErr)])
#       read_utf8!   : Str       => Try(Str,      [FileErr(IOErr)])
#       write_utf8!  : Str, Str  => Try({}, [FileErr(IOErr)])
#       delete!      : Str       => Try({}, [FileErr(IOErr)])
#   }
#
# Notes:
#   • No `host_*!` declaration, no wrapper. Each method's RETURN TYPE is
#     literally the ABI shape the host writes back. The error union here is
#     CLOSED (`[FileErr(IOErr)]`, no `..`) — same rule as `host_*!` in the
#     wrapper pattern. See edge case #4.
#   • You give up the ability to translate the host's error tag into a
#     platform-specific tag (the wrapper pattern's `Err(ioerr) =>
#     Err(FileErr(ioerr))`), so the host must emit exactly the tag the Roc
#     signature declares.
#   • Used by basic-cli for: File, Dir, Env, Locale, Random, Sleep, Tty, Utc.
#     The wrapper pattern is used for: Stdin, Stdout, Stderr (because they
#     need to translate the bare IOErr the host emits into a wrapped
#     `StdoutErr(IOErr)`, etc.).
#
# Pick the host-direct form when the host can produce the EXACT tag the Roc
# side wants to expose. Pick the wrapper form when you want a per-subsystem
# error tag layered over a shared IOErr.
#
# ─────────────────────────────────────────────────────────────────────────────
# 4. EDGE CASE — closed vs open Try in host signatures
# ─────────────────────────────────────────────────────────────────────────────
#
# This is the single most important rule for platform authors. Quoting the
# basic-cli source comment:
#
#   "These hosted functions return Try({}, IOErr) directly — matching the
#    host's ABI. They must NOT use open tag unions ([..]) because the
#    compiler would extend them with error variants from the calling context,
#    changing the memory layout and causing a mismatch with what the host
#    actually writes."
#
# So:
#   ✅ host_stdout_line! : Str => Try({}, IOErr)               # closed — correct
#   ❌ host_stdout_line! : Str => Try({}, [StdoutErr(IOErr), ..])  # open — UB
#
# The PUBLIC wrapper (`Stdout.line!`) is free to use open unions because the
# Roc compiler controls its memory layout end-to-end. Only the FFI boundary
# (`host_*!`) must be locked down.
#
# ─────────────────────────────────────────────────────────────────────────────
# 5. EDGE CASE — single-variant tag union ABI
# ─────────────────────────────────────────────────────────────────────────────
#
# A single-variant tag union like `[PathErr(IOErr)]` still carries a one-byte
# discriminant in the Roc ABI (always 0), even though there is only one tag.
# Host code that constructs or destructures these values must allocate that
# byte. In basic-cli's Rust host this is the `RocSingleTagWrapper<T>` type.
# If you're writing your own host bindings, do NOT assume a single-variant
# union is laid out the same as its payload.
#
# ─────────────────────────────────────────────────────────────────────────────
# 5b. EDGE CASE — record field order is part of the ABI
# ─────────────────────────────────────────────────────────────────────────────
#
# When a host function returns a record, the host writes its fields in a
# fixed memory layout. The Roc compiler reads them in the order they are
# DECLARED in the Roc source. If you reorder the fields in the Roc type
# declaration without also rebuilding the host, you get a SEGFAULT or
# silent corruption — the values land in the wrong slots.
#
# basic-cli's Cmd.roc spells this out explicitly:
#
#   # Do not change the order of the fields! It will lead to a segfault.
#   OutputFromHostSuccess : {
#       stderr_bytes : List(U8),
#       stdout_bytes : List(U8),
#   }
#
# Rule: when a record's type is shared with the host, the field-declaration
# order is load-bearing. Add new fields at the END, never re-sort.
#
# ─────────────────────────────────────────────────────────────────────────────
# 5c. EDGE CASE — nested Try as a three-state return
# ─────────────────────────────────────────────────────────────────────────────
#
# A `Try(a, b)` has two states (Ok / Err). When the host needs to distinguish
# THREE states without inventing a new tag union, basic-cli's Cmd uses a
# nested Try:
#
#   host_exec_output! : Cmd => Try(
#       OutputFromHostSuccess,                    # exit code 0
#       Try(OutputFromHostFailure, IOErr),        # nonzero exit OR IO error
#   )
#
# Decoded:
#   Ok(success)                 — program ran and exited with code 0
#   Err(Ok(failure_with_code))  — program ran but exit code != 0
#   Err(Err(ioerr))             — couldn't even run the program
#
# This is purely an ABI convenience — the SAME shape could be expressed as
# `Try(Success, [NonZero(Failure), IOErr(IOErr)])`, but the nested-Try form
# lets the host hand back layouts it already produces without constructing
# extra tags. Wrap it in a friendly Roc-side API before exposing it to apps.
#
# ─────────────────────────────────────────────────────────────────────────────
# 5d. EDGE CASE — `()` vs `{}` for the unit argument
# ─────────────────────────────────────────────────────────────────────────────
#
# An effectful function that takes "no real argument" can use either:
#
#   line! : Str         => Try({}, ...)   # explicit-arg form
#   now!  : {}          => U128           # empty record (common)
#   get!  : ()          => Try(Str, ...)  # unit tuple (also accepted)
#
# Both `{}` (empty record) and `()` (unit tuple) compile, and basic-cli
# mixes them: `Utc.now!` uses `{}`, `Locale.get!` and `Tty.enable_raw_mode!`
# use `()`. Functionally they're interchangeable for "no input."
#
# Convention: PREFER `{}` for consistency with the rest of the platform —
# it composes more cleanly with record patterns and is what the majority
# of basic-cli modules use. Only deviate if the host already expects a
# unit-tuple in its calling convention.
#
# ─────────────────────────────────────────────────────────────────────────────
# 6. Opaque types with multiple internal representations (Path)
# ─────────────────────────────────────────────────────────────────────────────
#
# Some platform types need to remember provenance. basic-cli's `Path` is a
# good template — it's an opaque alias (`::`) with a tag union body, plus a
# methods block that hides every construction path:
#
# Path :: [
#     FromOperatingSystem(List(U8)),   # nul-terminated, OS-charset bytes
#     ArbitraryBytes(List(U8)),        # user bytes — must validate before FFI
#     FromStr(Str),                    # UTF-8 from a RocStr
# ].{
#     from_str : Str -> Path
#     from_str = |s| FromStr(s)
#
#     display : Path -> Str
#     display = |p| match p {
#         FromStr(s) => s
#         FromOperatingSystem(b) | ArbitraryBytes(b) =>
#             match Str.from_utf8(b) {
#                 Ok(s) => s
#                 Err(_) => Str.from_utf8_lossy(b)
#             }
#     }
# }
#
# Why this pattern is useful for platforms:
#   • The host can hand you bytes whose encoding you can't recover later
#     (POSIX paths aren't required to be UTF-8). Storing provenance lets the
#     public `display` / `to_str_using_charset` methods make the right choice.
#   • Bytes from userspace may contain interior nul bytes — passing them to
#     a C API would silently truncate. The opaque type forces validation
#     in one place (the bytes accessor / FFI shim) instead of at every call.
#
# ─────────────────────────────────────────────────────────────────────────────
# 7. Shared error type
# ─────────────────────────────────────────────────────────────────────────────
#
# IOErr := [
#     AlreadyExists,
#     BrokenPipe,
#     Interrupted,
#     NotFound,
#     Other(Str),          # escape hatch for OS errors we don't enumerate
#     OutOfMemory,
#     PermissionDenied,
#     Unsupported,
# ]
#
# Pattern: one shared `IOErr` for low-level OS conditions, then per-subsystem
# wrappers (`StdoutErr(IOErr)`, `FileErr(IOErr)`, `PathErr(IOErr)`, …) so
# callers can both write generic handlers (`Err(_)`) and specific ones
# (`Err(FileErr(NotFound))`).
#
# ─────────────────────────────────────────────────────────────────────────────
# 8. The host side (Rust/Zig/etc.) — what it must provide
# ─────────────────────────────────────────────────────────────────────────────
#
# The host is NOT Roc, but you need to know what it exposes:
#
#   • `main()` (the OS entry point) — sets up locale (e.g. UTF-8 code page
#     on Windows), then calls the Roc `main_for_host!` symbol.
#   • Memory: `roc_alloc`, `roc_realloc`, `roc_dealloc`, `roc_panic`,
#     `roc_dbg` — these are the Roc runtime's hook names. The host can
#     implement them as a libc allocator or anything domain-specific (a
#     per-request arena, a tracked allocator, a no-op for WASM, etc.).
#   • One symbol per `host_*!` declared on the Roc side, with a name matching
#     the lowered Roc symbol (look at the linker output if in doubt).
#   • Tag union layouts must follow the Roc ABI — including the single-variant
#     discriminant byte described above.
#
# ─────────────────────────────────────────────────────────────────────────────
# 9. App-side usage (what an app author sees)
# ─────────────────────────────────────────────────────────────────────────────
#
# app [main!] { pf: platform "../platform/main.roc" }
#
# import pf.Stdout
# import pf.File
#
# main! = |_args| {
#     file_result = {
#         File.write_utf8!("greeting.txt", "Hi!")?
#         content = File.read_utf8!("greeting.txt")?
#         _ = Stdout.line!("greeting.txt contains: ${content}")
#         File.delete!("greeting.txt")?
#         Ok({})
#     }
#
#     match file_result {
#         Ok({}) => Ok({})
#         Err(_) => {
#             _ = Stdout.line!("File operations failed")
#             Err(Exit(1))                # surfaces a non-zero exit through main_for_host!
#         }
#     }
# }
#
# The `?` operator composes naturally because every platform call returns a
# `Try` with an open error union the app can extend.
#
# ─────────────────────────────────────────────────────────────────────────────
# Checklist when adding a new module to your platform
# ─────────────────────────────────────────────────────────────────────────────
#
#   [ ] Add the module name to `exposes [...]` in platform/main.roc.
#   [ ] Add `import <Name>` at the bottom of platform/main.roc so it's linked.
#   [ ] Declare `host_<name>_<op>!` functions at module top level with
#       CLOSED Try error types matching the host's actual return layout.
#   [ ] Wrap each in a public method inside `<Name> := [].{ ... }` with an
#       OPEN Try error type that tags the error: `Err(<Name>Err(ioerr))`.
#   [ ] Implement the matching symbol(s) in the host language. Mind the
#       single-variant tag union discriminant byte.
#   [ ] Rebuild the host (`build.sh` / `cargo build`) so libhost.a includes
#       the new symbol; the Roc app side gets picked up automatically.
