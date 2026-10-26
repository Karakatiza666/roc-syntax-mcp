## KV namespaces, KV cells, and the Cache API with the put after the response.
##
## A KV binding has one value type and one format, given at the declaration (MC6): `Kv.json` (JSON text, which a JS
## Worker reads with `get(key, "json")`), `Kv.text` or `Kv.bytes`. Annotate the declaration. With no annotation, the
## first use fixes the type, and a second use with another type fails there ("This ? unwraps to ... But this position
## needs ...").
##
## KV is eventual: a write can take 60 s or more to show in other places. Use a Durable Object (`Object.Cell`) for a
## value that must be consistent. Every platform error is inside `Infra(KvErr(..))`. `NotFound` is flat.
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.Kv
import pf.Cache
import pf.Http

Prefs : { theme : Str, font_size : U32 }

prefs : Kv(Prefs)
prefs = Kv.json("PREFS")

## A cell is one key of a namespace, declared once: the `localStorage` wrapper, but shared by all isolates.
site_default : Kv.Cell(Prefs)
site_default = prefs.cell("site-default")

notes : Kv(Str)
notes = Kv.text("NOTES")

## Metadata has its own type, given at the read. It crosses as CBOR, and KV keeps 1,024 bytes of it at most.
Owner : { owner : Str }

read_prefs! : Str => Try(Prefs, _)
read_prefs! = |user| {
	# `get!` gives `Err(NotFound)` for a key that is not there. `get_or!` gives the default for that case only.
	# `get!(..) ?? default` would give the default for a `KvErr` too, and hide it.
	fallback = site_default.get_or!({ theme: "light", font_size: 14 })?
	Ok(prefs.get_or!(user, fallback)?)
}

write_prefs! : Str, Request => Try({}, _)
write_prefs! = |user, req| {
	p : Prefs
	p = req.json!()?
	# KV takes whole seconds, and the module rounds `ttl_ms` up. KV refuses a TTL under 60 s, so the module raises
	# a smaller `ttl_ms` to 60 s and gives `Ok`. `expires_ms` is a time of the clock, and it is not changed.
	# Metadata goes through `Kv.Metadata.of`, not as a bare record: a bare record does not compile.
	Ok(prefs.put_with!(user, p, { ttl_ms: 86_400_000, metadata: Kv.Metadata.of({ owner: user }) })?)
}

owner_of! : Str => Try(Str, _)
owner_of! = |user| {
	got = prefs.get_with_metadata!(user)?
	# A key with no metadata is `Err(Missing)` in the field, not an error of the call.
	meta : Try(Owner, [Missing])
	meta = got.metadata
	Ok(
		match meta {
			Ok(m) => m.owner
			Err(Missing) => "nobody"
		},
	)
}

## `list!` cannot take a type, so each `Kv.Key` holds its metadata as CBOR: parse it with the type of the use.
## `cache_ttl_ms` of `get_with!` must be 30 s or more, else `KvErr`. The module does not raise it.
## `list!` gives one page (1,000 keys or less). `page.next` is `More(cursor)` until the last page: pass the cursor in
## the next call.
owners! : Str => Try(List(Str), _)
owners! = |prefix| {
	page = notes.list!({ prefix, limit: 100 })?
	page.keys.map_try(
		|key| {
			m : Owner
			m = key.metadata?.parse()?
			Ok(m.owner)
		},
	)
}

## The Cache API of one data center. The key is a URL, and the module sends it as a GET request. `Cache.default` is
## `caches.default`, `Cache.named("x")` is `caches.open("x")`.
##
## `put_after!` tees a stream body now and gives the response to send. The put runs in the work after the response (an
## `Err` of the put is a log line). It works only for the result of a `fetch!` handler. `put!` waits for the put and
## gives the response to send too: send that response, not the one that you gave. The result is not `{}`, so
## `cache.put!(url, res)?` as a statement does not compile, and `Ctx.wait_until!(cache.put(url, res))` does not either.
## A 206 response or `Vary: *` is `CacheErr`. A response with `Set-Cookie` or `Cache-Control: no-store` is not stored,
## and the put still gives `Ok`. Locally, a response with no `cache-control` is not stored.
cached_proxy! : Request => Try(Response, _)
cached_proxy! = |req| {
	key = req.url()
	match Cache.default.get!(key) {
		Ok(hit) => Ok(hit)
		Err(NotFound) => {
			fresh = Http.get!("https://example.com/feed.json")?
			res = fresh.with_header("cache-control", "public, max-age=300")
			Ok(Cache.default.put_after!(key, res)?)
		}
		Err(e) => Err(e)
	}
}

purge! : Str => Try(Response, _)
purge! = |url| match Cache.named("feeds").delete!(url) {
	Ok({}) => Ok(Response.from_status(204))
	Err(NotFound) => Ok(Response.from_status(404))
	Err(e) => Err(e)
}

fetch! : Request => Try(Response, _)
fetch! = |req| match (req.method(), req.segments()) {
	(GET, ["prefs", user]) => {
		p = read_prefs!(user)?
		Ok(Response.from_json(200, p))
	}
	(PUT, ["prefs", user]) => {
		write_prefs!(user, req)?
		Ok(Response.from_status(204))
	}
	(GET, ["owner", user]) =>
		match owner_of!(user) {
			Ok(o) => Ok(Response.from_text(200, o))
			Err(NotFound) => Ok(Response.from_status(404))
			Err(e) => Err(e)
		}

	(GET, ["owners"]) => {
		os = owners!(req.query("prefix") ?? "")?
		Ok(Response.from_json(200, os))
	}
	(GET, ["feed"]) => cached_proxy!(req)
	(DELETE, ["feed"]) => purge!(req.query("url") ?? "")
	_ => Ok(Response.from_status(404))
}

## `prefs.declare()` and `notes.declare()` name the bindings for the manifest. A cell names its namespace with
## `site_default.declare()` too: list one of the two for a binding, because a binding name twice is refused at load.
worker = Worker.new({ fetch!: fetch!, bindings: [prefs.declare(), notes.declare()] })

event! = |e| worker.event!(e)
