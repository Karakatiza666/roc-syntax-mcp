## Testing a Worker: an app that a `node --test` file runs in Miniflare with `startApp`, the test helper of the
## platform bundle. The tests are JavaScript. Roc `expect` checks pure code only: a handler needs the shim and a binding.
##
## `roc-cfw sync` copies `test.mjs` to `.roc-cfw/` with the rest of the shim, so a test runs the app that you build:
##   roc build --target=wasm32 --no-cache --output=app.wasm main.roc, then roc-cfw sync, then node --test tests/
## The helper finds Miniflare in the `wrangler` of the machine (or `MINIFLARE`). It writes no `.wrangler/` directory
## and makes no network call: an outbound fetch that the table does not name gets a 599.
##
## tests/app.test.mjs (this file ran against the app below, with sql/0001_init.sql the CREATE TABLE of `notes`):
##
##   import { test, after } from 'node:test';
##   import assert from 'node:assert/strict';
##   import { startApp } from '../.roc-cfw/test.mjs';
##
##   const T0 = 1767225600000;
##   const app = await startApp({
##     dir: '.',                                   // app.wasm, .roc-cfw/, wrangler.toml, worker.options.js
##     now: T0,                                    // the shim clock; null is real time
##     d1: { DB: ['sql/0001_init.sql'] },          // .sql files or SQL texts, in order
##     outbound: { 'GET https://api.example.com/status': [{ status: 503 }, { status: 200 }] },
##     count: ['DB'],                              // count the calls of these bindings
##   });
##   after(() => app.close());
##
##   test('a note gets the time of the shim clock', async () => {
##     const res = await app.fetch('/notes', { method: 'POST', body: '{"text":"hi"}', headers: { 'content-type': 'application/json' } });
##     assert.equal(res.status, 201);
##     assert.deepEqual(await res.json(), { created_ms: T0 });
##     assert.equal(res.calls.DB.n, 1);            // the D1 round trips of this request
##   });
##
##   test('the clock moves only when the test moves it', async () => {
##     assert.equal(await (await app.fetch('/recent')).text(), '1');
##     app.advance(61_000);                        // or app.setNow(ms)
##     assert.equal(await (await app.fetch('/recent')).text(), '0');
##   });
##
##   test('outbound answers come in order, then the last again', async () => {
##     assert.equal(await (await app.fetch('/upstream')).text(), '503');
##     assert.equal(await (await app.fetch('/upstream')).text(), '200');
##     assert.deepEqual(app.outbound().count, { 'GET https://api.example.com/status': 2 });
##   });
##
##   test('reset seeds again and puts the clock back', async () => {
##     await app.reset();                          // D1, KV, R2, Cache, the clock, Memo pins
##     assert.deepEqual(await (await app.fetch('/notes')).json(), []);
##   });
##
## Other calls: `app.scheduled({ cron })`, `app.queue(name, messages)`, `app.idle()` (wait for `Response.after` work),
## `app.calls()`, `app.sql(name, texts)`, `app.logs`. `app.reset()` keeps Durable Object storage.
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.6/HgUugW5V5QQbmrjdjkRhjiZ8B9D9gzpEkSwdojqJcW4p.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.D1
import pf.Sql
import pf.Time
import pf.Http

db = D1.binding("DB")

Note : { id : I64, text : Str, created_ms : I64 }

Added : { text : Str }

Count : { n : I64 }

fetch! : Request => Try(Response, _)
fetch! = |req| match (req.method(), req.segments()) {
	(POST, ["notes"]) => {
		added : Added
		added = req.json!()?
		# Read time with `Time.now_ms!`. It is the shim option `now`, which `startApp({ now })`, `app.advance` and
		# `app.setNow` move, and so are `Memo` expiry and `set_alarm_in!`. `Date.now()` in JS code of the app (an `ops`
		# function) and timers (`Time.sleep!`, `Io.timeout`) stay on the real clock.
		now = Time.now_ms!()
		_ = db.run!("INSERT INTO notes (text, created_ms) VALUES (?, ?)", (added.text, now))?
		Ok(Response.from_json(201, { created_ms: now }))
	}
	(GET, ["notes"]) => {
		rows : List(Note)
		rows = db.all!("SELECT id, text, created_ms FROM notes ORDER BY id", Sql.none)?
		Ok(Response.from_json(200, rows))
	}
	(GET, ["recent"]) => {
		since = Time.now_ms!() - 60_000
		c : Count
		c = db.first!("SELECT count(*) AS n FROM notes WHERE created_ms >= ?", since)?
		Ok(Response.from_text(200, c.n.to_str()))
	}
	(GET, ["upstream"]) => {
		res = Http.get!("https://api.example.com/status")?
		Ok(Response.from_text(200, res.status().to_str()))
	}
	_ => Ok(Response.from_status(404))
}

# Declare each binding. `startApp` reads the bindings from the manifest of app.wasm, not from wrangler.toml, and makes
# a local D1, KV, R2, queue, rate limit or Durable Object for each one. With no `bindings` here, `d1: { DB: ... }`
# throws "the option d1 names DB, and the app does not declare it", and with no seed the request is a 500 with the
# log line `D1Err(... "Cannot read properties of undefined (reading 'prepare')")`. A kind with no local form (`Ai`,
# `Vectorize`, a service binding) needs `services` (a Node function) or `bindings` in the options.
worker = Worker.new({ fetch!: fetch!, bindings: [db.declare()] })

event! = |e| worker.event!(e)
