# Writing and maintaining Roc platforms.
#
# A Roc program is split between an application (pure Roc the user writes)
# and a platform (the I/O primitives, memory allocator, and entry point).
# Every app picks exactly one platform. This topic covers what the platform
# author writes. See https://www.roc-lang.org/platforms for background.
#
# A platform has two parts:
#   1. The host (Zig, Rust, C, and so on) implements `main()`, `malloc`/`free`,
#      and every I/O primitive the platform exposes. The platform ships it as a
#      pre-compiled binary (`libhost.a`, plus `.o` files per target).
#   2. The Roc API is the `.roc` modules that wrap the host's FFI functions in
#      idiomatic Roc types. App authors see this part.
#
# The host starts first. The app is like a C library that the host calls any
# number of times, or never. The standard library has no I/O and Roc has no
# FFI of its own. So every effect, and every call into another language, goes
# through a function that the platform exposes. A platform can leave out an
# effect that does not fit its domain (file I/O in a browser), and a package
# that needs it does not build there. A platform can also guard each effect,
# e.g. with a prompt before a file write. A platform can wrap one existing
# codebase, to embed Roc in it. Concurrent I/O scheduled by the platform is
# planned.
#
# A host can see the address of any value it receives. Whether a platform API
# depends on addresses is the choice of the platform author. The optimizer
# assumes that allocation has no observable effect, so effects in a host
# allocator may run differently between compiler releases.
#
# The sections below show the patterns that the basic-cli platform uses, taken
# from https://github.com/roc-lang/basic-cli (new-compiler branch).
#
#
# 1. The platform header (platform/main.roc)
#
# platform "my-platform"
#     requires {} { main! : List(Str) => Try({}, [Exit(I32), ..]) }
#     exposes [Cmd, Dir, Env, File, IOErr, Path, Stdin, Stdout, Stderr]
#     packages {}
#     provides { "roc_main": main_for_host! }
#     hosted { "roc_read_file": File.read_bytes! }
#     targets : {
#         inputs_dir: "targets/",
#         x64linux:  { inputs: ["crt1.o", "libhost.a", app] },
#         arm64mac:  { inputs: ["libhost.a", app] },
#         wasm32:    { inputs: ["host.wasm", app], output: Shared, exports: [] },
#     }
#
# Field by field:
#   `requires {} { main! : ... }` is the shape an application must provide.
#     `requires { main! : ... }`, with one record, also compiles, and basic-cli
#     uses it. The Try's error type is left open (`..`) so apps can return any
#     platform-defined error and still satisfy the constraint.
#   `exposes [...]` lists the Roc modules the app can `import pf.X`.
#   `packages { json: "../json/main.roc" }` declares package dependencies and
#     their qualifiers.
#   `provides { "symbol": roc_function }` maps each link symbol the host
#     resolves to the Roc function exposed under it. The string comes first.
#     The `roc__` prefix is reserved for the compiler, so `"roc__entrypoint"`
#     is "invalid hosted section".
#   `hosted { "symbol": Module.fn! }` declares functions the host implements
#     and Roc calls, which is the reverse direction from `provides`. A hosted
#     function is an annotation with no body in a `.{ }` block, and it must:
#       - be effectful, `=>` ("hosted function must be effectful"), because
#         compile-time evaluation cannot call the host,
#       - have an entry in `hosted` ("invalid hosted section"),
#       - use a type variable only inside `Box(...)`, which is always a
#         pointer ("hosted type variable must be boxed").
#     `hosted` and `provides` functions are identified by their symbol
#     strings, not by module content (see `packages`).
#   `targets : { ... }` lists link inputs per target. `app` is a placeholder
#     for the compiled Roc application object. The other inputs are host
#     artifacts that the linker combines with it. `inputs_dir` names the directory holding those
#     files inside the package bundle.
#
# A target's `output` field declares the artifact kind:
#   `Exe` (the default) links an executable. On wasm32, a command module with
#     an entry point.
#   `Shared` builds a shared library (`.so`, `.dylib`, `.dll`). On wasm32, a
#     reactor module with no entry point, exporting the `provides` entrypoints.
#   `Archive` builds a static archive (`.a`, `.lib`) holding the host inputs,
#     the compiled app, and the builtins, for linking into another build.
# A linked wasm32 target must list its host-visible functions in `exports`.
# `exports: []` exports none explicitly. Without the field, `roc build` fails
# with "missing wasm exports".
#
# The platform decides what to build. App authors never pass artifact-kind
# flags to `roc build`. Without `--target`, `roc build` uses the first
# compatible entry in `targets`. Input order matters for linking.
#
# An app can also provide a type to the platform, using a `for` clause. The
# `[Context : context]` syntax maps an uppercase alias the app defines to a
# lowercase rigid type variable, so the type stays opaque to the platform.
# basic-webserver's real header, which is bundled with this server under
# `scope: "basic-webserver"`:
#
# platform "webserver"
#     requires {
#         [Context : context] for program : {
#             init! : () => Try({ config : Server.Config, context : context }, [Exit(I64), ..]),
#             respond! : Server.Request, context => Try(Server.Outcome, [ServerErr(Str), ..]),
#             shutdown! : Server.ShutdownReason, context => Try({}, [Exit(I64), ..]),
#         }
#     }
#
# Three things to copy from it. The app names the alias (`Context : {}`) and
# the record of functions (`program = { init!, respond!, shutdown! }`), and
# annotates neither the record nor the alias against the platform's own shape.
# Every error type is open (`..`), so an app can return its own errors. The
# rigid variable appears in all three signatures, so the whole application must
# use one context type.
#
# 2. The entry-point glue: main_for_host!
#
#
# The host expects a function returning a plain `I32` exit code. The app
# returns `Try({}, [Exit(I32), ..])`. `main_for_host!` converts between them:
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
#   Effectful → `=>` arrow, name ends in `!`.
#   The host-facing signature must be representable in the host's ABI:
#     primitive `I32` here. No tag unions, no open types.
#   Inspect any unhandled error for diagnostics, then return a non-zero code.
#
#
# 3. Anatomy of a platform module (basic-cli 0.24.0)
#
#
# basic-cli declares every hosted effect in one module, Host.roc, and each
# public module wraps the ones it needs:
#
#   ## Host.roc: the raw FFI surface, linked by `hosted { ... }` in main.roc.
#   Host :: [].{
#       stdout_line!  : Str => Try({}, [StdoutErr(IOErr)])
#       stdout_write! : Str => Try({}, [StdoutErr(IOErr)])
#   }
#
#   ## Stdout.roc: the public API.
#   import IOErr
#   import Host
#
#   Stdout :: [].{
#       line! : Str => Try({}, [StdoutErr(IOErr)])
#       line! = |message| widen_stdout_err(Host.stdout_line!(message))
#   }
#
#   ## Rebuild the error union so it is open at call sites.
#   widen_stdout_err : Try(v, [StdoutErr(IOErr)]) -> Try(v, [StdoutErr(IOErr)])
#   widen_stdout_err = |result|
#       match result {
#           Ok(value) => Ok(value)
#           Err(StdoutErr(err)) => Err(StdoutErr(err))
#       }
#
# Conventions:
#   A module is a type with an empty body, `Stdout :: [].{...}`, which gives
#     static-dispatch `Stdout.line!(...)` syntax.
#   The shared `IOErr` type lives in its own module so every I/O module can
#     reuse it. Errors are wrapped per subsystem (`StdoutErr(IOErr)`) so a
#     match can tell which subsystem failed.
#   The type signature looks the same on both sides. Only the body is
#     different. See edge case #4.
#
#
# 3b. Wrapping without a helper
#
#
# A module whose methods take or return platform data can rewrap the error
# inline, with no named `widen_*` helper. basic-cli's File.roc:
#
#   File :: [].{
#       Reader :: { host : Host.FileReader }.{
#           read_line! : Reader => Try(List(U8), _)
#           read_line! = |reader|
#               Host.file_read_line!(reader.host)
#                   .map_err(|FileErr(err)| FileErr(err))
#       }
#   }
#
# `.map_err` with a lambda that looks like the identity still does work. It
# builds a new union, and that new union is open.
#
#
# 4. The ABI between the Roc code and the host
#
#
# A hosted result, a single-tag union, the order of record fields, a
# three-state return, the unit argument, a type with several representations
# (`Path`), and a shared error type each have rules that compile and then fail
# at run time. The `platform_abi` topic covers them.
#
#
# 5. The host side (Rust, Zig, and so on): what it must provide
#
#
# The host is not Roc code, but you need to know what it exposes:
#
#   `main()` (the OS entry point), sets up locale (e.g. UTF-8 code page
#     on Windows), then calls the Roc `main_for_host!` symbol.
#   Memory: `roc_alloc`, `roc_realloc`, `roc_dealloc`, `roc_panic` and
#     `roc_dbg` are the Roc runtime's hook names. The host can implement them
#     as a libc allocator or as anything domain-specific (e.g. a per-request
#     arena, a tracked allocator, or a no-op for WASM).
#   One symbol per hosted function declared on the Roc side (each entry in
#     `hosted { ... }`), with a name matching the lowered Roc symbol.
#   Tag union layouts must follow the Roc ABI, including the single-variant
#     discriminant byte that the `platform_abi` topic describes.
#
#
# 6. App-side usage (what an app author sees)
#
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
# The `?` operator composes because every platform call returns a `Try` with
# an open error union that the app can extend.
#
#
# 7. Reading a real platform end to end
#
#
# The basic-cli fragments above are quotes. This server bundles basic-webserver
# 0.17.0 in full, so you can read all of it:
#
#   get_roc_syntax(scope: "basic-webserver")   the app-facing API in one page
#   get_roc_module("Server")                   one module's methods and types
#   search_symbols("Server.Config.to_host")    one glue method, by name
#   list_roc_index(kind: "examples")           27 programs that all pass roc check
#
# Read it for four things that this topic covers only abstractly:
#
#   The `for` clause above, in production use and not as a sketch.
#   A `packages { http: "..." }` dependency: `Request`, `Response`, `Method`,
#     and `Header` come from roc-lang/http, so app authors import them from
#     `http.` and everything else from `pf.`. Two platforms stay compatible
#     when both re-export the same package's types.
#   The `to_host` / `from_host` glue in full. `Server.Config.to_host` flattens
#     a config record into the shape that the Zig host reads.
#     `Server.Request.from_host` does the reverse. There are 138 such items.
#     This server hides them from app-facing search because they are the ABI,
#     which the `platform_abi` topic describes.
#   The `hosted { ... }` direction, where the platform declares what the host
#     implements, spread across Host.roc and the Internal* modules that
#     `exposes` deliberately leaves out.
#
#
# Checklist when adding a new module to your platform
#
#
#   [ ] Add the module name to `exposes [...]` in platform/main.roc.
#   [ ] Add `import <Name>` at the bottom of platform/main.roc so that the
#       module is linked.
#   [ ] Declare each hosted function in `Host :: [].{ ... }` with the Try
#       error type the host actually writes back.
#   [ ] Wrap each in a public method inside `<Name> :: [].{ ... }` that
#       rebuilds the union (a `widen_*` match or `.map_err`), so that callers
#       get an open union. Never return a hosted result unchanged.
#   [ ] Implement the matching symbol(s) in the host language. Mind the
#       single-variant tag union discriminant byte.
#   [ ] Rebuild the host (`build.sh` / `cargo build`) so libhost.a includes
#       the new symbol. The build picks up the Roc app side automatically.
