## The app that roc_check wraps bare cloudflare-workers source in, when the
## caller names the scope and the code has no header.
##
## Everything above `@user-code` is the prelude. roc_check adds each
## `@default` block below it only when the submitted code does not define
## that name. So a bare `fetch!` gets a Worker and an `event!`, and code that
## defines its own `worker` or `event!` keeps them.
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

# The compiler does not warn about an unused import. The scaffold imports each
# exposed module, so a snippet that uses D1 or Object compiles as submitted.
import pf.Ai
import pf.Analytics
import pf.Assets
import pf.Body
import pf.Cache
import pf.Cbor
import pf.Ctx
import pf.D1
import pf.Email
import pf.Env
import pf.Http
import pf.Hyperdrive
import pf.Id64
import pf.Io
import pf.Js
import pf.Kv
import pf.Log
import pf.Memo
import pf.Native
import pf.Object
import pf.Queue
import pf.R2
import pf.RateLimit
import pf.Request
import pf.Response
import pf.Rpc
import pf.Secret
import pf.SecretsStore
import pf.Service
import pf.Sql
import pf.Tcp
import pf.Time
import pf.Vectorize
import pf.Version
import pf.WebCrypto
import pf.WebSocket
import pf.Worker
import pf.Workflows

# @user-code

# @default fetch!
# The annotation is optional, because the methods wait for the type. It keeps
# the errors near their cause.
fetch! : Request => Try(Response, _)
fetch! = |_req| Ok(Response.from_status(404))

# @default worker
worker = Worker.new({ fetch!: fetch! })

# @default event!
event! = |e| worker.event!(e)
