## Form bodies: URL-encoded into a `Dict`, multipart into raw parts.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.MultipartFormData
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, _context| {
	path =
		match request.target() {
			Resource({ raw_path, .. }) => raw_path
			_ => ""
		}
	match (request.method(), path) {
		(POST, "/submit") => Ok(Server.respond(handle_url_encoded!(request)?))
		(POST, "/upload") => Ok(Server.respond(handle_upload!(request)?))
		_ => Ok(Server.respond(text(405, "POST /submit or /upload")))
	}
}

# `parse_form_url_encoded` decodes plus signs and percent escapes, then
# validates UTF-8. A later duplicate key replaces an earlier value, so the
# result is a `Dict`, not a list of pairs.
handle_url_encoded! : Server.Request => Try(Response, [ServerErr(Str)])
handle_url_encoded! = |request| {
	# Limit the read before you use the body. A form body should never need megabytes.
	body = request.body().with_limit(64 * 1024).read_all!()
		? |err| ServerErr("failed to read form: ${Str.inspect(err)}")

	match MultipartFormData.parse_form_url_encoded(body) {
		Err(_) => Ok(text(400, "malformed form body"))
		Ok(fields) =>
			match Dict.get(fields, "email") {
				Ok(email) => Ok(text(200, "got ${email}"))
				Err(_) => Ok(text(422, "email is required"))
			}
	}
}

# Multipart needs the headers too: the boundary lives in `Content-Type`. Parts
# come back raw and undecoded, including their transfer encoding.
handle_upload! : Server.Request => Try(Response, [ServerErr(Str)])
handle_upload! = |request| {
	body = request.body().with_limit(10 * 1024 * 1024).read_all!()
		? |err| ServerErr("failed to read upload: ${Str.inspect(err)}")

	match MultipartFormData.parse_multipart_form_data({ headers: request.headers(), body }) {
		Err(_) => Ok(text(400, "malformed multipart body"))
		Ok(parts) =>
			match parts.find_first(is_avatar) {
				Ok(part) => Ok(text(200, "received ${U64.to_str(List.len(part.data))} bytes"))
				Err(_) => Ok(text(422, "no avatar part"))
			}
	}
}

# A part carries raw `Content-Disposition` and `Content-Type` bytes, so the
# field name has to be matched out of the disposition string.
is_avatar : MultipartFormData.FormData -> Bool
is_avatar = |part| {
	disposition = Str.from_utf8(part.disposition) ?? ""
	Str.contains(disposition, "name=\"avatar\"")
}

text : U16, Str -> Response
text = |status, body|
	Response.from_status(status)
		.add_header("Content-Type", "text/plain; charset=utf-8")
		.with_body(Str.to_utf8(body))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})
