# The ABI between a platform's Roc code and its host: the cases that compile
# and then fail at run time. The `platforms` topic covers the header, the
# hosted functions and the host side. These sections follow basic-cli 0.26.0.
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
# gives the caller a closed `[Interrupted, StdoutErr(IOErr)]`, and `?` cannot
# combine it with any other error. Rebuild the union in Roc first (the
# `widen_*` match of the `platforms` topic, or `.map_err`), so the compiler
# controls its layout and the caller gets an open one.
#
#
# 2. The tag union discriminant
#
#
# A tag union stores its largest payload, then a discriminant that tells which
# tag it holds. A union with one tag has no discriminant, so `[PathErr(IOErr)]`
# has the same layout as `IOErr`. A union with 2 to 256 tags has a one-byte
# discriminant. The discriminant numbers the tags in alphabetical order from 0,
# so in `[Red, Green, Blue]` the number of `Blue` is 0. Generate these numbers
# with `roc glue`.
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
# as `_ : U32` or `_reserved : U32` reserves that many bytes of padding, with
# alignment 1. No code can read it. A structural record cannot have a `_` field.
Header := { tag : U8, _ : {}, value : U32 }

# @rejects unnamed field not allowed in structural record
# BadHeader : { tag : U8, _ : {}, value : U32 }

# basic-cli's Host.roc returns the output of a command as a record:
#
#   CmdOutput : { status : [Exited(I32), Signaled(I32)], stdout_bytes : List(U8), stderr_bytes : List(U8) }
#
# The two lists have the alignment of a pointer, and `status` has the alignment
# of an `I32`. So the host writes `stderr_bytes`, `stdout_bytes`, then
# `status`: the field that comes first in the source comes last in memory.
#
#
# 4. A three-state return
#
#
# When the host must distinguish three outcomes, keep the outcomes that are not
# failures in the success value, and give the error union one tag per failure
# mode. basic-cli's Host.roc:
#
#   cmd_run! : Cmd => Try(CmdOutput, [CmdErr(CmdErr), Interrupted])
#
# A command that ran and exited non-zero is `Ok`, with `Exited(code)` as its
# `status`. `CmdErr` is a command that could not start or did not finish, and
# `Interrupted` is a signal that the program caught. Do not nest a `Try` in the
# error position for the third state. The flat union reads better at every
# match.
#
#
# 5. The unit argument
#
#
# An effectful function that takes no real argument takes `()`:
#
#   now!             : () => Utc
#   get!             : () => Try(Locale, [NotAvailable])
#   enable_raw_mode! : () => Try({}, [TtyErr(IOErr)])
#
# The caller writes `Utc.now!()`. Every such function in basic-cli 0.26.0
# takes `()`, so a platform that follows it matches what its users expect.
#
#
# 6. Types with several internal representations (Path)
#
#
# Some platform types must record where their value came from. basic-cli's
# `Path` is a good template. It is a nominal tag union, and each tag keeps the
# units of one operating system unchanged:
#
# Path := [
#     Utf8(Str),                  # a string literal or a Str
#     UnixBytes(List(U8)),        # Unix bytes, which need not be UTF-8
#     WindowsU16s(List(U16)),     # Windows UTF-16 units, which need not be valid
# ].{
#     display : Path -> Str
#     display = |path|
#         match path {
#             Utf8(str) => str
#             UnixBytes(bytes) => Str.from_utf8_lossy(bytes)
#             WindowsU16s(u16s) => Str.from_utf8_lossy(InternalUtf16.to_utf8_lossy(u16s))
#         }
# }
#
# Why this pattern is useful for platforms:
#   The host can give you bytes whose encoding you cannot recover later
#     (POSIX paths do not have to be UTF-8). If the type keeps the raw units,
#     effects pass them back to the host unchanged, and only `display` loses
#     information. Its `to_inspect` prints the raw units.
#   Bytes from userspace can contain interior nul bytes, and a C API silently
#     truncates them. One type forces validation in one place (the FFI shim)
#     and not at every call.
#
#
# 7. A shared error type
#
#
# IOErr := [
#     AddrInUse,
#     AddrNotAvailable,
#     AlreadyExists,
#     BrokenPipe,
#     ConnectionRefused,
#     ConnectionReset,
#     Interrupted,
#     IsADirectory,
#     NotFound,
#     NotADirectory,
#     Other(Str),          # any OS error that the other tags do not name
#     OutOfMemory,
#     PermissionDenied,
#     TimedOut,
#     Unsupported,
# ]
#
# Pattern: one shared `IOErr` for low-level OS conditions, then per-subsystem
# wrappers (`StdoutErr(IOErr)`, `FileErr(IOErr)`, `PathErr(IOErr)`, …) so
# callers can both write generic handlers (`Err(_)`) and specific ones
# (`Err(FileErr(NotFound))`).
#
#
# 8. A hosted function owns its arguments
#
#
# Roc gives each refcounted argument (`List`, `Str`, `Box`) to the hosted
# function and does not decrement its reference count after the call. A host
# that only reads the argument and returns something else leaks it. The C
# glue (`CGlue.roc`) has no helper to free or make a `RocList`, so let Roc
# allocate and free the lists:
#   - A hosted function that only reads a list returns that list, and Roc
#     frees it:  present! : List(U8) => List(U8)
#   - A host that must return new bytes gets a list from a `provides` entry,
#     and fills it in place:
#       provides { "my_fresh_bytes": fresh_bytes }
#       fresh_bytes : U64 -> List(U8)
#       fresh_bytes = |count| List.repeat(0, count)
