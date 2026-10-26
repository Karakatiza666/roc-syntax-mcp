## R2: stream an upload in and a download out, ranges, conditional writes, lists and multipart uploads across requests.
##
## A body stays a JS stream unless the app reads it. Give `req.body()` to `put!`, and `obj.body` to `Response.from_body`
## (or the object to `R2.to_response`): no byte goes into wasm memory, so the 128 MB isolate limit does not apply to the
## object. A `Body` is a tag: write `Text("hello")` or `Bytes(list)`, never a bare string ("used where a non-string
## type is needed ... Body"). `req.body` without the call is a field read, and `Request` is opaque: use the methods.
## Every platform error is inside `Infra(R2Err(..))`. `NotFound` and `PreconditionFailed` are flat.
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.R2
import pf.Body
import pf.Io

files = R2.binding("FILES")

upload! : Str, Request => Try(Response, _)
upload! = |key, req| {
	meta = files.put_with!(key, req.body(), { http: { content_type: req.header("content-type") ?? "application/octet-stream" } })?
	Ok(Response.from_text(201, meta.etag))
}

## The whole GET of a key in one call: 200 with `accept-ranges`, 206 for one `Range`, 304 and 412 for the conditional
## headers, 404, and 416. The body is a stream. `R2.to_response(obj)` is the 200 response of an object that the app got
## itself, with its HTTP metadata and etag.
download! : Str, Request => Try(Response, _)
download! = |key, req| Ok(files.respond!(key, req)?)

## `Suffix(n)` reads the last n bytes. `obj.?range` is the range that R2 read, for the Content-Range header. It is there
## only for a call with `range`.
## Each field of `R2.Http` is optional: read it with `.?`, never with `.` ("The content_type field is optional").
first_kib! : Str => Try(Response, _)
first_kib! = |key| match files.get_with!(key, { range: From({ offset_bytes: 0, length_bytes: 1024 }) }) {
	Ok(obj) => {
		range = match obj.?range {
			Ok(From(r)) => "bytes ${r.offset_bytes.to_str()}-${(r.offset_bytes + (r.?length_bytes ?? 0) - 1).to_str()}/${obj.meta.size_bytes.to_str()}"
			_ => "bytes */${obj.meta.size_bytes.to_str()}"
		}
		# `R2.to_response` is always status 200. For a range, make the 206 response from the body.
		Ok(Response.from_body(206, obj.meta.http.?content_type ?? "application/octet-stream", obj.body).with_header("content-range", range))
	}
	Err(NotFound) => Ok(Response.from_status(404))
	Err(e) => Err(e)
}

## Compare and swap. A failed condition is `Err(PreconditionFailed)`, not a null. `R2.from_headers` gives If-Match,
## If-None-Match, If-Modified-Since and If-Unmodified-Since of the request to R2, quotes included. With no condition
## header the write is NOT conditional, so refuse a request that has none.
## When you build the condition by hand (`{ etag_matches: etag }`), the etag has no quotes: a quoted etag is `R2Err`.
replace! : Str, Request => Try(Response, _)
replace! = |key, req| match req.header("if-match") {
	Err(NotFound) => Ok(Response.from_status(428))
	Ok(_) =>
		match files.put_with!(key, req.body(), { only_if: R2.from_headers(req.headers()) }) {
			Ok(meta) => Ok(Response.from_text(200, meta.etag))
			Err(PreconditionFailed) => Ok(Response.from_status(412))
			Err(e) => Err(e)
		}
}

## `R2.absent` writes only a key that is not there.
create_only! : Str => Try(Response, _)
create_only! = |key| match files.put_with!(key, Text("{}"), { only_if: R2.absent }) {
	Ok(_) => Ok(Response.from_status(201))
	Err(PreconditionFailed) => Ok(Response.from_status(409))
	Err(e) => Err(e)
}

## A stream that the app makes (`Body.writer!`, `compress!`) has no known length. `put!` takes it: up to 5 MiB it is one
## put, and past 5 MiB it is a multipart upload with parts of 5 MiB (the last one smaller), one part in memory at a time.
## Past 5 MiB, `only_if` and `checksum` are `R2Err`: give `length_bytes` (the exact count), and the put is one request.
## The writes run with `Io.start!`, because `put!` waits until the stream ends. Close the writer before the put.
generated! : Str => Try(Response, _)
generated! = |key| {
	{ body, writer } = Body.writer!()?
	_ = Io.start!(writer.write_text("hello, "))
	_ = Io.start!(writer.write_text("world"))
	writer.close!()
	_ = files.put!(key, body)?
	Ok(Response.from_status(201))
}

## At most 1,000 objects a page. `http` and `custom` of each `Meta` are empty unless `include` names them.
list! : Str, Str => Try(Response, _)
list! = |prefix, cursor| {
	page = if cursor == "" {
		files.list!({ prefix, delimiter: "/", include: [Http] })?
	} else {
		files.list!({ prefix, delimiter: "/", include: [Http], cursor })?
	}
	next = match page.next {
		More(c) => c
		Done => ""
	}
	Ok(Response.from_json(200, { keys: page.objects.map(|o| o.key), folders: page.prefixes, next }))
}

## A multipart upload spans requests. `R2.Upload` and `R2.Part` are plain data: send them to the client, or keep them in
## KV or D1. `resume_multipart_upload` is pure and checks nothing: a wrong id is `R2Err` at `upload_part!`.
## Parts are numbered from 1 to 10,000. Each part except the last is 5 MiB or more.
mp_start! : Str => Try(Response, _)
mp_start! = |key| {
	up = files.create_multipart_upload_with!(key, { http: { content_type: "application/zip" } })?
	Ok(Response.from_json(200, up))
}

mp_part! : Str, Str, Str, Request => Try(Response, _)
mp_part! = |key, upload_id, n, req| {
	part_number = U32.from_str(n) ? |_| Infra(BadData("part number"))
	part = files.resume_multipart_upload(key, upload_id).upload_part!(part_number, req.body())?
	Ok(Response.from_json(200, part))
}

mp_done! : Str, Str, Request => Try(Response, _)
mp_done! = |key, upload_id, req| {
	parts : List(R2.Part)
	parts = req.json!()?
	_ = files.resume_multipart_upload(key, upload_id).complete!(parts)?
	# On the edge the `Meta` of `complete!` has no `http` and no `custom` (Miniflare has them). Read the stored
	# object with `head!`.
	meta = files.head!(key)?
	Ok(Response.from_text(200, meta.http.?content_type ?? "none"))
}

## Delete takes a list of keys. Work after the response goes in `Response.after`. The work gets the key, not the
## request: a read of the request body in the work is `BodyErr`. An `Err` of the work is a log line.
remove! : Str => Try(Response, _)
remove! = |key| Ok(Response.from_status(202).after(|| files.delete!([key])))

fetch! : Request => Try(Response, _)
fetch! = |req| match (req.method(), req.segments()) {
	(PUT, ["files", key]) => upload!(key, req)
	(GET, ["files", key]) => download!(key, req)
	(GET, ["head", key]) => first_kib!(key)
	(POST, ["replace", key]) => replace!(key, req)
	(POST, ["create", key]) => create_only!(key)
	(POST, ["generated", key]) => generated!(key)
	(GET, ["list"]) => list!(req.query("prefix") ?? "", req.query("cursor") ?? "")
	(POST, ["mp", key]) => mp_start!(key)
	(PUT, ["mp", key, upload_id, n]) => mp_part!(key, upload_id, n, req)
	(POST, ["mp", key, upload_id]) => mp_done!(key, upload_id, req)
	(DELETE, ["files", key]) => remove!(key)
	_ => Ok(Response.from_status(404))
}

worker = Worker.new({ fetch!: fetch!, bindings: [files.declare()] })

event! = |e| worker.event!(e)
