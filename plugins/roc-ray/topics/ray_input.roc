## Input: one snapshot per cycle, and the difference between held and pressed.
##
## `update!` receives an `App.Input(Msg)`, and every device reading is on
## `input.devices`. The `Keys`, `Mouse` and `Gamepad` modules hold the same
## queries as plain functions over that snapshot, so `input.devices.key_down(k)`
## and `Keys.key_down(input.devices, k)` are one call written two ways.
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Color
import rr.Draw
import rr.Keys
import rr.Math

Model : {
	pos : Math.Vec2,
	typed : Str,
	zoom : F32,
	pad : Str,
	clipboard : Str,
}

Msg : []

program = { init!, update!, render! }

## Reading the clipboard is declared, like every access beyond the app's own
## resources. Without `ClipboardRead` the read stops the app at runtime.
init! : App.Init(Model, [])
init! = App.init(
	App.default.with_title("Topic: input").with_permission(ClipboardRead),
	## `Devices.none` is the empty snapshot: the seed for a model that needs one
	## before the first cycle, and the base `expect` builds on with
	## `with_key_down`. Nothing here needs it, because the model keeps only what
	## it derived from an input. That makes the model testable.
	|_io| Ok({ pos: { x: 400, y: 300 }, typed: "", zoom: 1, pad: "no pad", clipboard: "" }),
)

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, program_input, io| {
	input = program_input.devices

	# Held is level, pressed is an edge retained since the previous input, so
	# each press is consumed by exactly one `update!`. The host records key and
	# button events as they arrive, so a tap released between two cycles still
	# reads as both pressed and released. `input.events` lists them in order.
	# Movement reads the level. A shortcut reads the edge.
	dx = (if Keys.key_down(input, KeyRight) 1.F32 else 0) - (if input.key_down(KeyLeft) 1.F32 else 0)
	dy = (if input.key_down(KeyDown) 1.F32 else 0) - (if input.key_down(KeyUp) 1.F32 else 0)
	speed = 240 * program_input.time.elapsed_seconds

	# Typed text is not key state: it arrives as Unicode codepoints in event
	# order, respects the keyboard layout, and is capped at 32 per cycle. There
	# is no Str on the snapshot, so an app decodes what it wants itself.
	typed = Str.concat(
		model.typed,
		Str.from_utf8_lossy(
			List.map(List.keep_if(input.text_input, |c| c >= 32 and c < 127), |c| U32.to_u8_wrap(c)),
		),
	)

	# The wheel is two axes and a delta rather than a position, so it is folded
	# into model state rather than read as one.
	wheel = input.mouse.wheel_delta()

	# A pad is resolved out of the snapshot and is scoped to it: query it here
	# and keep the answer, rather than keeping the `View` in the model.
	pad =
		match input.gamepad(One) {
			Connected(view) => if view.button_down(FaceDown) "pad: A held" else "pad: connected"
			Disconnected => "no pad"
		}

	# The clipboard is a service on `App.Io`, not a `Window` function. The read
	# is a copy rather than I/O, so it is legal in `update!` and answers in the
	# cycle that asked.
	clipboard =
		if input.key_down(KeyLeftControl) and input.key_pressed(KeyV) {
			io.clipboard().read_text!() ?? model.clipboard
		} else {
			model.clipboard
		}

	Ok({
		pos: Math.add(model.pos, Math.vec2(dx * speed, dy * speed)),
		typed,
		zoom: Math.clamp(model.zoom + wheel.y * 0.1, 0.25, 4),
		pad,
		clipboard,
	})
}

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
	frame.clear!(Color.from_hex_rgb(0x101820))
	frame.circle!({ center: model.pos, radius: 10 * model.zoom, style: Draw.filled(Color.ray_white) })
	frame.text_at!({ pos: { x: 24, y: 24 }, text: model.typed, size: 18, color: Color.ray_white })
	frame.text_at!({ pos: { x: 24, y: 48 }, text: model.pad, size: 16, color: Color.gray })
	Ok({})
}
