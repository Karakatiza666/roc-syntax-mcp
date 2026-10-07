## The app contract: three callbacks, one model, one message type.
##
## A RocRay app is a frame loop the platform owns. `init!` builds the first
## model, `update!` folds one `App.Input` into the next one, and `render!` draws
## it. Nothing here is optional. The platform's `requires` block names all
## three, plus two types that the app must declare.
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Color
import rr.Draw
import rr.Math
import rr.Random
import rr.Text

Model : {
	font : Text.Font,
	rng : Random.State,
	pointer : Math.Vec2,
	clicks : U64,
	seconds : F32,
	label : Str,
}

## Required, always, even by an app that spawns no task and has no message to
## deliver. The platform's `requires` block is `[Model : model, Msg : msg]`, and
## a missing `Msg` is a "missing platform required type" error pointing at
## `program`. The header exposes `[Model, program]` and never `Msg`.
Msg : []

## The whole wiring. The record's field names are the contract, so a callback
## named `tick!` or `draw!` is not found.
program = { init!, update!, render! }

## `App.init` pairs a static config with the startup callback. `init!` is not a
## bare function: the platform needs the config before it opens a window, and
## `App.init_for_args` is the variant whose config sees argv first.
##
## The callback receives `App.Io`, the app's authority. Everything that reaches
## the OS is a method on it: `io.args!()`, `io.entropy!()`, `io.files()`,
## `io.http()`, `io.stdout()`. There is no `App.args!` or `App.entropy!`.
##
## The error set is a type argument, so it is closed: `App.Init(Model, [])`
## fails as soon as a `?` raises `ResourceLimit`. `_` lets inference write it.
init! : App.Init(Model, _)
init! = App.init(
	App.default
		.with_title("Topic: the app contract")
		.with_size({ width: 800, height: 600 })
		.with_frame_pacing(Capped(60)),
	|io| {
		# argv[0] is included, so an app reading its own flags starts at index 1.
		# Legal only in `init!`: `update!` receives the same `App.Io`, so the call
		# type-checks there and stops the app when it runs.
		args = io.args!()

		# Entropy is the only thing that makes one run differ from the last, and
		# the app decides when to read it. Seed once here, keep the state in the
		# model, and every later draw is pure. `entropy!` is also legal only in `init!`.
		rng = Random.seed(U64.to_u32_wrap(io.entropy!()))

		Ok({
			font: Draw.default_font!(),
			rng,
			pointer: { x: 0, y: 0 },
			clicks: 0,
			seconds: 0,
			label: if List.len(args) > 1 "argv carried flags" else "no flags",
		})
	},
)

## One cycle. Three arguments: the model, this cycle's input, and the same
## `App.Io` `init!` had. A two-argument `update!` is a type mismatch reported
## at `program`, not at `update!`.
##
## `input.time.elapsed_seconds` is this cycle's duration as F32 seconds. The
## same record also carries `simulation_nanos` and `monotonic_nanos` as U64
## nanoseconds, so the unit is in the field name rather than in the type.
##
## Quitting is a return value: `Err(Exit(code))`. `App.default` already exits on
## Escape, so no app needs that check. Write the error set with no `..`: a tag
## union in a return type is already open, and `[Exit(I64), ..]` is a
## "redundant open tag union" warning.
update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, input, _io|
	if input.devices.key_pressed(KeyQ) {
		Err(Exit(0))
	} else {
		Ok({
			..model,
			seconds: model.seconds + input.time.elapsed_seconds,
			pointer: input.devices.mouse.position(),
			clicks: model.clicks + if input.devices.mouse.button_pressed(Left) 1 else 0,
		})
	}

## Draws, and only draws. It gets no `App.Io`, and its return type is
## `Try({}, ...)`, not `Try(Model, ...)`: the model cannot change here.
render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
	frame.clear!(Color.from_hex_rgb(0x101820))
	frame.circle!({ center: model.pointer, radius: 12, style: Draw.filled(Color.ray_white) })
	frame.text_at!({ pos: { x: 24, y: 24 }, text: model.label, size: 18, color: Color.ray_white })
	Ok({})
}
