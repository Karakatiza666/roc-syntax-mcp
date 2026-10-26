## HTTP in a Worker: routing, JSON in and out, outbound `fetch` with
## `Http.send!`, two calls at the same time, a timeout, a streamed response
## with `Response.after`, and a webhook signature check with a secret.
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.Http
import pf.Io
import pf.Body
import pf.Env
import pf.Time
import pf.WebCrypto
import pf.Memo

Repo : { full_name : Str, stargazers_count : U64 }

Ask : { name : Str }

fetch! : Request => Try(Response, _)
fetch! = |req| match (req.method(), req.segments()) {
	(POST, ["hello"]) => {
		# Annotate the value of a JSON read. With no annotation, the compiler says
		# "encoder_for ... never resolved to a concrete type" at the read.
		ask : Ask
		ask = req.json!()?
		Ok(Response.from_json(200, { greeting: "hello ${ask.name}" }))
	}
	(GET, ["repo", owner, name]) => repo!(owner, name)
	(GET, ["two"]) => two!()
	(GET, ["slow"]) => slow!()
	(GET, ["events"]) => events!()
	(POST, ["webhook"]) => webhook!(req)
	(GET, ["config"]) => {
		cfg = config.get!()?
		Ok(Response.from_text(200, cfg.motd))
	}
	_ => Ok(Response.from_status(404))
}

repo! : Str, Str => Try(Response, _)
repo! = |owner, name| {
	token = Env.secret!("GITHUB_TOKEN")?
	# A Request is opaque. Build it with `get`, `post`, `new` and `with_*`.
	# A Secret has no codec and does not show in `Str.inspect`: `reveal` gives the text.
	out = Request.get("https://api.github.com/repos/${owner}/${name}")
		.with_header("Authorization", "Bearer ${token.reveal()}")
		.with_header("User-Agent", "roc-worker")
	res = Http.send!(out)?
	# `send!` gives `Ok` for each status. Only a throw of fetch is an `Err`.
	# On the edge, a DNS failure is status 530 and a blocked address is 403,
	# not `Network`: check the status, or ask `Http.cloudflare_error(res)`.
	if res.status() != 200 {
		return Ok(Response.from_status(502))
	}
	# `send!` read the body in the same crossing (up to 1 MiB, else
	# `TooLarge`), so this `json!` does not wait. `Http.open!` keeps the
	# body a stream.
	repo : Repo
	repo = res.json!()?
	Ok(Response.from_text(200, "${repo.full_name}: ${repo.stargazers_count.to_str()}"))
}

two! : () => Try(Response, _)
two! = || {
	# Each function that waits has a pure twin with no `!` that gives an `Io`.
	# `Io.both!` runs two in one crossing, at the same time. Their errors join.
	(a, b) = Io.both!(Http.get("https://a.example.com"), Http.get("https://b.example.com"))?
	Ok(Response.from_text(200, "${a.status().to_str()} ${b.status().to_str()}"))
}

slow! : () => Try(Response, _)
slow! = || {
	# `timeout` races the `Io` with a sleep: `Err(Infra(TimedOut))` after the time.
	match Io.run!(Http.get("https://slow.example.com").timeout(5_000)) {
		Ok(res) => Ok(Response.from_text(200, res.status().to_str()))
		Err(Infra(TimedOut)) => Ok(Response.from_status(504))
		Err(e) => Err(e)
	}
}

events! : () => Try(Response, _)
events! = || {
	{ body, writer } = Body.writer!()?
	# The handler gives the response. `after` runs the work once Workers has the
	# response. The work writes to the stream. A `write!` in the handler itself
	# waits for a reader that does not exist yet.
	Ok(
		Response.from_body(200, "text/event-stream", body).after(
			|| {
				writer.write_text!("data: start ${Time.now_ms!().to_str()}\n\n")?
				Time.sleep!(1_000)
				writer.write_text!("data: ${WebCrypto.random_uuid!()}\n\n")?
				writer.close!()
				Ok({})
			},
		),
	)
}

webhook! : Request => Try(Response, _)
webhook! = |req| {
	secret = Env.secret!("WEBHOOK_SECRET")?
	body = req.bytes!()?
	given = req.header("X-Signature") ?? ""
	# `hmac_sha256` is pure Roc, with no crossing.
	mac = WebCrypto.hmac_sha256(secret.reveal().to_utf8(), body)
	if WebCrypto.timing_safe_equal!(hex(mac).to_utf8(), given.to_utf8()) {
		Ok(Response.from_status(204))
	} else {
		Ok(Response.from_status(401))
	}
}

hex : List(U8) -> Str
hex = |bytes| {
	digits = "0123456789abcdef".to_utf8()
	out = bytes.fold([], |acc, b| acc.append(digits.get((b // 16).to_u64()) ?? 48).append(digits.get((b % 16).to_u64()) ?? 48))
	Str.from_utf8(out) ?? ""
}

Config : { motd : Str }

load_config! : () => Try(Config, _)
load_config! = || {
	res = Http.get!("https://example.com/config.json")?
	res.json!()
}

# A value kept in the isolate across requests, as CBOR bytes: a cache, not
# state. The first `get!` in an isolate, and the first after `max_age_ms`,
# runs `load!`. Two tasks can both run `load!`.
config = Memo.new("config", { max_age_ms: 60_000, load!: load_config! })

worker = Worker.new({ fetch!: fetch! })

event! = |e| worker.event!(e)
