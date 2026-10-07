## Work that waits, and the phase rule that is not in the types.
##
## Every effect in this platform is legal in some phases and refused in others,
## and only one of those rules is typed: `Draw.Frame` is passed only to
## `render!`, so only `render!` can draw. `init!` and `update!` receive the same
## `App.Io`, so everything else (reading a file, sending a request, running a
## query, sleeping) is an ordinary call that type-checks in either and stops
## the app with a programmer error when it runs in the wrong phase.
##
## Waiting effects are legal in `init!`, where they block startup, and in tasks,
## where they park the task while the frame loop keeps running. `Task` exists
## only for this reason.
##
## A task gives you overlap for waiting, and nothing else. Every task body
## runs on the frame thread and yields only at a waiting effect, so a long pure
## computation inside one holds the frame exactly as it would in `update!`.
##
## `Http` takes and returns the `roc-lang/http` package's `Request` and
## `Response`, and the platform does not re-export them. An app that names
## either pins the same release in its own header, as below. Without the pin,
## `Request.from_method` "does not exist".
app [Model, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import rr.App
import rr.Color
import rr.Draw
import rr.Files
import rr.Http
import rr.Task
import rr.Url
import http.Request
import http.Response

Model : {
	## A directory handle is an ordinary value: opened once in `init!`, kept
	## in the model, captured by any task that reads beneath it.
	notes_dir : Files.ReadDir,
	## Which fetch the reply belongs to. Two tasks started a cycle apart can
	## finish in any order, so a reply that does not match the current request
	## is dropped rather than shown.
	fetch : U64,
	status : Str,
	notes : Str,
}

## The message type the platform's `requires` block binds. A task can report
## only through its return value. It cannot read or write the model.
Msg : [
	Fetched(U64, Str),
	Failed(U64, Str),
	Read(Try(Str, Files.ReadTextError)),
]

program = { init!, update!, render! }

## Both accesses are declared, and a literal is a `Url` here. `HttpOrigin` takes
## a `Url`, not a `Str`: a runtime string goes through `Url.parse` first, or the
## mismatch names the whole `Permission` union with `HttpOrigin(Str)` in it.
config = App.default
	.with_title("Topic: tasks")
	.with_permission(WorkingDirectory(ReadOnly))
	.with_permission(HttpOrigin("https://www.roc-lang.org"))

init! : App.Init(Model, _)
init! = App.init(
	config,
	## Waiting is legal here, and it blocks: nothing is drawn until this
	## returns. If a file is small enough to read at startup, read it here.
	## Anything else belongs in a task. `Task.spawn!` is refused here, because
	## it needs an `App.Input`, and `init!` has none.
	|io| {
		notes_dir = io.files().working_directory_read!()?
		Ok({ notes_dir, fetch: 0, status: "idle", notes: notes_dir.read_text!("notes.txt") ?? "no notes" })
	},
)

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, input, io| {
	# `Task.spawn!` takes the input as its first argument. It is never read:
	# the `Input(msg)` is the witness that pins the closure's message type.
	fetch =
		if input.time.cycle_count == 0 or input.devices.key_pressed(KeyR) {
			id = model.fetch + 1
			# A service is selected from `io` here and captured by the closure.
			http = io.http()
			Task.spawn!(input, || fetch!(http, id, "https://www.roc-lang.org/"))
			id
		} else {
			model.fetch
		}

	# Reading the file right here would compile and then stop the app:
	#     model.notes_dir.read_text!("notes.txt")
	# The call is legal in `init!` and in tasks and refused in `update!`, and
	# nothing in its type says so. Spawn it instead.
	if input.devices.key_pressed(KeyN) {
		dir = model.notes_dir
		Task.spawn!(input, || Read(dir.read_text!("notes.txt")))
	}

	status = List.fold(input.messages, model.status, |current, message| apply(current, message, fetch))
	notes = List.fold(
		input.messages,
		model.notes,
		|current, message|
			match message {
				Read(Ok(text)) => text
				Read(Err(_)) => "unreadable"
				_ => current
			},
	)

	Ok({ ..model, fetch, status, notes })
}

## One request, written top to bottom. Waiting inside a task parks that task
## rather than the app.
##
## `Http.Client.get_utf8!` takes a `Url`. A quoted literal becomes one at
## compile time. A URL held as a `Str` will not coerce, so it is parsed here.
fetch! : Http.Client, U64, Str => Msg
fetch! = |http, id, raw|
	match Url.parse(raw) {
		Err(_) => Failed(id, "not a URL")
		Ok(url) =>
			match http.send!(Request.from_method(GET).with_uri(url.to_str())) {
				Ok(response) =>
					match Str.from_utf8(Response.body(response)) {
						Ok(body) => Fetched(id, "${Response.status(response).to_str()}, ${List.len(Str.to_utf8(body)).to_str()} bytes")
						Err(_) => Failed(id, "the body was not UTF-8")
					}

				# An origin no declaration covers answers this, redirects included.
				Err(PermissionDenied) => Failed(id, "origin not declared")
				Err(InvalidUrl(_)) => Failed(id, "not a URL this platform will fetch")
				Err(HttpErr(Timeout)) => Failed(id, "timed out")
				Err(HttpErr(NetworkError)) => Failed(id, "network error")
				Err(HttpErr(MalformedResponse)) => Failed(id, "malformed response")
				Err(HttpErr(Other(bytes))) => Failed(id, Str.from_utf8(bytes) ?? "failed")
			}
	}

## A reply from an abandoned fetch leaves the state alone.
apply : Str, Msg, U64 -> Str
apply = |status, message, current|
	match message {
		Fetched(id, detail) if id == current => detail
		Failed(id, reason) if id == current => reason
		_ => status
	}

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
	frame.clear!(Color.from_hex_rgb(0x0d1425))
	frame.text_at!({ pos: { x: 24, y: 24 }, text: model.status, size: 18, color: Color.ray_white })
	frame.text_at!({ pos: { x: 24, y: 52 }, text: model.notes, size: 15, color: Color.gray })
	Ok({})
}
