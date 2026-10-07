## The app `roc_check` wraps bare code in when the caller names a scope and the
## code carries no header of its own.
##
## Everything above `@user-code` is the prelude. `roc_check` appends each
## `@default` block below it only when the submitted code does not define that
## name. src/roc_check.ts reads both markers, and
## scripts/check-platform-examples.sh compiles the whole file, so the scaffold
## always matches the pinned platform.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

# The compiler does not warn about an unused import. The scaffold imports every
# exposed module, so a snippet that uses Sqlite or Sse compiles as submitted.
import pf.Attribute
import pf.Cmd
import pf.Env
import pf.File
import pf.Html
import pf.Http
import pf.IOErr
import pf.MultipartFormData
import pf.OsStr
import pf.Path
import pf.Server
import pf.Sleep
import pf.Sqlite
import pf.Sse
import pf.Stderr
import pf.Stdout
import pf.Tcp
import pf.UnixTime
import pf.Url
import http.Header
import http.Method
import http.Request
import http.Response

# @user-code

# @default Context
Context : {}

# @default program
program = { init!, respond!, shutdown! }

# @default init!
# `crash` has the bottom type, so this type-checks against the Context that the
# submitted code declares. `roc check` stops at types, so nothing here runs.
init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || Ok({ config: Server.default_config, context: crash("scaffolded init!: define your own to build a Context") })

# @default respond!
respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |_request, _context| Ok(Server.respond(Response.from_status(200)))

# @default shutdown!
shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})
