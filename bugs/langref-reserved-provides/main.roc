# The `provides` example of langref modules.md:479 and :526 uses a reserved
# symbol.
#
# Run:      roc check langref-reserved-provides/main.roc
# Expected: No errors. The page shows `provides { "roc__entrypoint": main }`.
# Actual:   "invalid hosted section": the roc__ prefix is reserved for symbols
#           that the compiler generates. With "roc_main", the same platform
#           checks clean.
#
# Nightly: nightly-2026-10-06-c34079d.

platform "mini"
    requires {} { main! : List(Str) => Try({}, [Exit(I32), ..]) }
    exposes [Out]
    packages {}
    provides { "roc__entrypoint": main_for_host! }
    hosted { "roc_out_line": Out.line! }
    targets : {
        x64glibc: { inputs: [app] },
    }

import Out

main_for_host! : List(Str) => I32
main_for_host! = |args|
    match main!(args) {
        Ok({}) => 0
        Err(Exit(code)) => code
        Err(_) => 1
    }
