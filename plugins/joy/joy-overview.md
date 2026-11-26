# Joy in one page

Joy is a Roc platform for single-page web apps. The app compiles to a
WebAssembly module. The platform's `runtime.js` loads that module in the page,
updates the DOM to match what the app renders, and does all of the I/O. The app
follows the Elm architecture: `init` makes the first model from a flags string the
page gives, `update` makes the next model from a model and a message, `view`
makes an HTML tree from the model, and `subscriptions` names the outside events
to listen for. The app does no I/O itself. An HTTP request, a timer or a call to
JavaScript is a value that it returns, and the result comes back as a message.
The HTML tree is `Html(msg)` from the joy-html package, so each app pins
joy-html version too. Joy has no server part yet. A server renders the same views with
basic-webserver and joy-html, and `Html.document` mounts the app in that page.

| To find | Ask |
|---|---|
| The view API, joy-html | `get_roc_syntax(topic: "joy-html")` |
| One module, whole | `get_roc_module Http` |
| One signature | `search_symbols Time.debounce` |
| A name you do not know | `search scope="joy"` |
| Complete programs that compile | `list_roc_index kind="examples"` |
| A worked program on one subject | `get_roc_syntax(topic:)`: `joy_app`, `joy_http`, `joy_subscriptions`, `html_views`, `html_ssr` |

## Starting a project

The only install is Roc 0.1.0-RC2, the release this page was checked with
(0.1.0-rc1, which joy names, works too). The starter writes a project from a template and installs a `./joy` command in it:

```bash
roc run https://github.com/niclas-ahden/joy/releases/download/0.35.0/4ZWtVnGUbEA2PrkhMwW3xHDASMZSmJNV9XmvSFPpzk3S.tar.zst init
./joy dev       # serves http://localhost:8000 and hot-reloads on save
./joy build     # writes what ships into dist/
./joy upgrade   # moves the project to a newer Joy release
```

That URL is Joy's command-line program, not the platform an app pins. A
project is `client/app.roc`, `public/index.html` and `assets/`. The page
mounts the app on an element with `data-joy-bundle`, and `data-joy-flags` is
the string `init` receives, empty when absent:

```html
<div id="app" data-joy-bundle="app" data-joy-flags='{"name": "Ada"}'></div>
<script type="module" src="/joy.js"></script>
```

The `spa_minimal` example is the one-file template, and `spa_todomvc` is the
largest app. The templates `spa-pages` and `spa-pages-expanded` split an app
into page modules; read them in the repository.

## The application contract

```roc
app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.35.0/FtRCTy7CSPSdS2vLzGJPwYfcGurQfoaADXPNT8aJBBCr.tar.zst",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
}

init : Str -> (Model, List(Effect(Msg)))
update : Model, Msg -> (Model, List(Effect(Msg)))
view : Model -> Html(Msg)
subscriptions : Model -> List(Sub(Msg))
```

All four are required, `subscriptions` too when it returns `[]`. The app must
define types named exactly `Model` and `Msg`, even when no message is ever
sent. Listing them in the header is optional. `init` always takes the flags
string. `update` returns the model and a list of effects, never the bare model.

The fourth function is `view`. A `render` from 0.34.0 is "missing platform
required definition". The `html` pin is required. `view` returns joy-html's `Html`, so the app
pins exactly the release the platform pins. A different
release has a different `Html`, and the error reads "The difference is inside
this type, but it is not visible in this display". With no `html` pin, the
compiler flags only the first use of `import html.Html`.

## Effects and subscriptions

Every entry point is pure. Anything observable is an `Effect` value returned
from `init` or `update`, which the host runs and answers with a message. The
constructors are in `Http`, `Time`, `DOM`, `Navigation`, `Clipboard`,
`Media`, `Console`, `Port` and `WebCrypto`. Anything recurring is a `Sub`
returned from `subscriptions`: `Time.every`, `Keyboard.*`,
`Navigation.on_url_change`, `Navigation.on_link_click`,
`DOM.on_document_click`, `Port.listen`. The URL is `Navigation`'s:
`DOM.on_url_change` and `DOM.replace_url` do not exist. They are different types,
and each is rejected in the other's place. A subscription stays active
while the list contains it. To stop it, leave it out.

Every callback is a lambda. A tag is not a function, so `Http.get(url, Got)`,
`on_input(Typed)` and `Effect.map_all(effects, Left)` do not compile. `|r| Got(r)` does.
`on_click` and `on_submit` are the opposite. They take the message itself,
`on_click(Increment)`.

Annotations need the module imported: `Effect(Msg)` and `Sub(Msg)` are
"not declared in this scope" without `import pf.Effect` and `import pf.Sub`.
Exposing a module's own type, `import pf.Effect exposing [Effect]` or
`exposing [Html]`, is an error, "redundant expose".

A component is a model, a `Msg` and an `update` of its own. The parent wraps the
child's messages in a tag and maps both ways: `Html.map(html, |m| Left(m))` and
`Effect.map_all(effects, |m| Left(m))`. Do not name its functions `init`,
`update` or `view`: a method with the name of a top-level definition is a
"duplicate definition" warning. `joy_app` shows the whole pattern.

## HTTP

`Http.get` and `Http.post` send no headers and never time out. Anything else
starts from `Http.default_request`: `method` is a tag (`POST`), `body` is
`List(U8)`, and `timeout_ms` is `TimeoutMilliseconds(U64)` or `NoTimeout`.
The status is not an error: a 404 or a 500 arrives as `Ok(resp)`, and `Err` is
only `HttpErr(Timeout)` or `HttpErr(NetworkError)`. There is no `Http.Error`
type, and a type alias cannot hold `..`, so a `Msg` spells the union out:

```roc
Reply : Try(Http.Response, [HttpErr([Timeout, NetworkError])])
```

## Time

Timer delays are `U32` milliseconds (`Time.after`, `Time.every`,
`Time.debounce`), HTTP timeouts `U64` milliseconds. A timer's callback gets
`I64` milliseconds since the Unix epoch, not nanoseconds. There is no clock to
read and no `Time.now`: boot data, the time included, comes in through the
flags. There is no random source either: keep the seed of a PRNG package, such
as niclas-ahden/roc-prng, in the model. A debounce key is global to the app, and so is a port name, so prefix
both in a reusable component.

## JavaScript

`Port.send(name, value)` is an effect, received by `app.onPort(name, fn)` on the
page. `Port.listen(name, |s| ...)` is a subscription, fed by
`app.sendPort(name, value)`. Both carry strings, so structured data is JSON. A
name nobody registered is a no-op. The page gets `app` from two events that
`joy.js` dispatches on `document`: set `event.detail.setup = (app) => ...` in
`joy:mount` to register `onPort` before the app starts, and use
`event.detail.app` in `joy:mounted` to send. A browser feature with types of
its own is a custom effect: `Effect.call(id, args, |reply| ...)` or
`Effect.send`, its arguments written with `Wire`, and a `.js` file beside the
module.

## Testing

An effect is data, so a pure `expect` can assert what `update` asked for:
`effect.identity().id` is the effect's name, `"joy/http/send"` for every
request. A request is a `Call` whose callback takes the reply as `Wire`
bytes, so a test can answer it as the host would. `joy_http` answers with
statuses 404, 500, 0 (never completed) and 1 (timed out). `roc test` runs the platform's own
expects beside the app's.

## Traps

- Hashing is `pf.WebCrypto`. `import pf.Crypto` collides with the builtin
  `Crypto` module. Its algorithm is a tag, `Sha256`, and an empty result means
  it failed. For bytes already in memory, the builtin `Crypto.SHA256.hash` is
  pure and needs no effect.
- `dbg value` as a statement logs to the browser console. `x = dbg value`
  compiles and binds `{}`.
- The key event type is `Sub.KeyEvent`. `Keyboard.KeyEvent` does not exist.
- A platform path must be relative, `"../joy/platform/main.roc"`. An absolute
  path is refused.
