platform ""
    requires {} { main! : List(Str) => Try({}, [Exit(I32), ..]) }
    exposes [Console, Ledger]
    packages {}
    provides { "roc_main": main_for_host! }
    hosted {
        "roc_console_read": Host.console_read!,
        "roc_console_write": Host.console_write!,
    }
    targets: {
        inputs_dir: "targets/",
        x64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a"] },
        arm64mac: { inputs: ["libhost.a", app] },
    }

import Console
import Ledger
import Host

main_for_host! : List(Str) => I32
main_for_host! = |args| {
    match main!(args) {
        Ok({}) => 0
        Err(Exit(code)) => code
        Err(_) => 1
    }
}
