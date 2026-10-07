## The app `roc_check` wraps bare code in when the caller names a scope and the
## code carries no header of its own.
##
## Everything above `@user-code` is the prelude. `roc_check` appends each
## `@default` block below it only when the submitted code does not define that
## name. src/roc_check.ts reads both markers, and
## scripts/check-platform-examples.sh compiles the whole file, so the scaffold
## always matches the pinned platform.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

# The compiler does not warn about an unused import. The scaffold imports every
# exposed module, so a snippet that uses Sqlite or Tty compiles as submitted.
import pf.Cmd
import pf.Env
import pf.File
import pf.Http
import pf.IOErr
import pf.Locale
import pf.OsStr
import pf.Path
import pf.Random
import pf.Sleep
import pf.Sqlite
import pf.Stderr
import pf.Stdin
import pf.Stdout
import pf.Tcp
import pf.Tty
import pf.Url
import pf.Utc
import http.Header
import http.Method
import http.Request
import http.Response

# @user-code

# @default main!
# The platform's `requires` clause fixes this signature. Submitted code that
# defines its own `main!` replaces the whole block, annotation included.
main! : List(OsStr.OsStr) => Try({}, [Exit(I32)])
main! = |_args| Ok({})
