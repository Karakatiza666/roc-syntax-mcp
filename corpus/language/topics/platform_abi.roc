# The ABI between a platform's Roc code and its host: the cases that compile
# and then fail at run time. The `platforms` topic covers the header, the
# hosted functions and the host side. These sections follow basic-cli 0.24.0.
#
#
# 1. A hosted result is a closed union
#
#
# A tag union in a return type is implicitly open, and if you write `..` there,
# the compiler gives a "redundant open tag union" warning. A hosted function is
# the exception. Its result has the exact memory layout that the host writes,
# so the compiler keeps it closed. A wrapper that returns it unchanged
#
#   ❌ line! = |message| Host.stdout_line!(message)
#
# gives the caller a closed `[StdoutErr(IOErr)]`, and `?` cannot combine it
# with any other error. Rebuild the union in Roc first (the `widen_*` match of
# the `platforms` topic, or `.map_err`), so the compiler controls its layout and
# the caller gets an open one.
#
#
# 2. A single-variant tag union
#
#
# A single-variant tag union like `[PathErr(IOErr)]` carries a one-byte
# discriminant in the Roc ABI (always 0), although it has only one tag.
# Host code that constructs or destructures these values must allocate that
# byte. In basic-cli's Rust host, the `RocSingleTagWrapper<T>` type does this.
# If you write your own host bindings, do not assume that a single-variant
# union has the same layout as its payload.
#
#
# 3. Record field order is part of the ABI
#
#
# When a host function returns a record, the host writes its fields in a
# fixed memory layout. That layout does not follow the order of the fields in
# the source. The compiler orders them by decreasing alignment, then by name:
# `{ zed : U8, alpha : U64, mid : Str, beta : U8, big : U128 }` is laid out as
# big, alpha, mid, beta, zed. Generate the host's types with `roc glue`. Do not
# write them by hand from the Roc source.
#
# A new name or a new type can move a field. Rebuild the host after either
# change, or the values go into the wrong slots: a segfault or silent corruption.
#
# A nominal record with a `_ : {}` field keeps the declared order. A field such
# as `_ : U32` reserves that many bytes of padding. A structural record cannot
# have a `_` field.
Header := { tag : U8, _ : {}, value : U32 }

# @rejects unnamed field not allowed in structural record
# BadHeader : { tag : U8, _ : {}, value : U32 }

# basic-cli's Cmd.roc warns about the order:
#
#   # Do not change the order of the fields! It will lead to a segfault.
#   OutputFromHostSuccess : {
#       stderr_bytes : List(U8),
#       stdout_bytes : List(U8),
#   }
#
# Both fields have the same alignment, and their names are already in order.
#
#
# 4. A three-state return
#
#
# When the host must distinguish three outcomes, give the error union one tag
# per failure mode. basic-cli's Cmd:
#
#   cmd_exec_output! : Cmd => Try(
#       CmdOutputSuccess,                          # exit code 0
#       [
#           NonZeroExitCode(CmdOutputFailure),     # ran, exit code != 0
#           FailedToGetExitCode(IOErr),            # could not run it
#       ],
#   )
#
# Older basic-cli releases nested a `Try` in the error position for this. The
# current releases use the flat union, which reads better at every match.
#
#
# 5. `()` vs `{}` for the unit argument
#
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
# Convention: prefer `{}` for consistency with the rest of the platform. It
# composes more cleanly with record patterns, and most basic-cli modules use
# it. Use `()` only if the host already expects a unit tuple in its calling
# convention.
#
#
# 6. Opaque types with several internal representations (Path)
#
#
# Some platform types must record where their value came from. basic-cli's
# `Path` is a good template. It is an opaque alias (`::`) with a tag union
# body, plus a methods block that hides every way to construct it:
#
# Path :: [
#     FromOperatingSystem(List(U8)),   # nul-terminated, OS-charset bytes
#     ArbitraryBytes(List(U8)),        # user bytes, must validate before FFI
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
#   The host can give you bytes whose encoding you cannot recover later
#     (POSIX paths do not have to be UTF-8). If the type records the source,
#     the public `display` / `to_str_using_charset` methods can choose correctly.
#   Bytes from userspace can contain interior nul bytes, and a C API silently
#     truncates them. The opaque type forces validation in one place (the
#     bytes accessor / FFI shim) and not at every call.
#
#
# 7. A shared error type
#
#
# IOErr := [
#     AlreadyExists,
#     BrokenPipe,
#     Interrupted,
#     NotFound,
#     Other(Str),          # any OS error that the other tags do not name
#     OutOfMemory,
#     PermissionDenied,
#     Unsupported,
# ]
#
# Pattern: one shared `IOErr` for low-level OS conditions, then per-subsystem
# wrappers (`StdoutErr(IOErr)`, `FileErr(IOErr)`, `PathErr(IOErr)`, …) so
# callers can both write generic handlers (`Err(_)`) and specific ones
# (`Err(FileErr(NotFound))`).
