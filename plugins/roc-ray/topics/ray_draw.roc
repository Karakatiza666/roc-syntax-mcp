## Drawing: the frame, the styles, and the scopes that change render!'s type.
##
## Every drawing call needs a `Draw.Frame`, and the only `Frame` there is the
## one `render!` is handed. So `update!` cannot draw. It has no frame to draw
## on, and the compiler reports an error.
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Camera
import rr.Color
import rr.Draw
import rr.Math

Model : {
	camera : Camera.Camera2D,
	## Read in `update!` from `input.window`, because `frame.size!()` is legal
	## only in `render!`. The two disagree about the type as well as the phase:
	## `input.window.size` is `I32` and `frame.size!()` is `F32`.
	viewport : { width : I32, height : I32 },
	spin : F32,
}

Msg : []

program = { init!, update!, render! }

init! : App.Init(Model, [])
init! = App.init(
	App.default.with_title("Topic: drawing").with_size({ width: 900, height: 600 }),
	|_io|
		Ok({
			camera: Camera.centered(Math.vec2(0, 0), Math.vec2(900, 600)),
			viewport: { width: 900, height: 600 },
			spin: 0,
		}),
)

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, input, _io| Ok({ ..model, viewport: input.window.size, spin: model.spin + input.time.elapsed_seconds })

## The error set is the important part. Every scoped call can answer
## `ScopeLimit`: `with_camera!`, `with_scissor!` and `with_blend_mode!`, and
## `with_shader!` and `with_render_texture!` add `ScopeUnavailable`. A return
## type's union is open for callers, but the body may raise only the tags it
## lists: a `?` on a scoped call against `Try({}, [Exit(I64)])` is "produces the
## tag ScopeLimit but the annotated tag union does not list it". Write the tag
## out, with no `..`, which in a return type is a "redundant open tag union"
## warning.
render! : Model, Draw.Frame => Try({}, [Exit(I64), ScopeLimit])
render! = |model, frame| {
	size = frame.size!()
	frame.clear!(Color.from_hex_rgb(0x0d1425))

	# A style is a value rather than a flag: `filled`, `outlined`, `stroke` for
	# lines, and `filled_and_outlined` for both at once with the outline width
	# last.
	frame.rectangle!({
		x: 24,
		y: 24,
		width: size.width - 48,
		height: 64,
		style: Draw.filled_and_outlined(Color.from_hex_rgb(0x18243b), Color.with_alpha(Color.white, 55), 2),
	})

	# `segments` is how many triangles each corner is drawn with. Upstream's own
	# examples pass `radius` both as a logical-unit value and as a fraction
	# below 1, so read one nearby before copying a number.
	frame.rounded_rectangle!({
		x: 24,
		y: 108,
		width: 260,
		height: 120,
		radius: 18,
		segments: 12,
		style: Draw.filled(Color.from_hex_rgb(0x18243b)),
	})

	# A record literal is a `Math.Vec2` wherever one is expected, and inference
	# reaches through a binding, so `Math.vec2` is for computing rather than for
	# writing a point down.
	frame.line!({
		start: { x: 24, y: 248 },
		end: { x: size.width - 24, y: 248 },
		stroke: Draw.stroke(Color.with_alpha(Color.ray_white, 90), 2),
	})

	# A scope is a nested frame, not a begin/end pair: the callback is handed its
	# own `Frame`, and that is the one the scope applies to. The outer `frame` is
	# still in scope inside the callback and drawing on it still type-checks, so
	# the name the callback binds is the one to use.
	frame.with_camera!(model.camera, |world| {
		world.circle!({ center: Math.vec2(0, 0), radius: 40, style: Draw.filled(Color.from_hex_rgb(0x2f80ed)) })
		world.rectangle!({ x: -120, y: -20, width: 60, height: 40, style: Draw.outlined(Color.ray_white, 1) })
		Ok({})
	})?

	# Scissor takes a `Math.Rect`, which is `{ x, y, width, height }`, and clips
	# every call made on the frame it hands back.
	frame.with_scissor!({ x: 320, y: 300, width: 240, height: 160 }, |clipped| {
		clipped.circle!({ center: { x: 440, y: 380 }, radius: 200, style: Draw.filled(Color.with_alpha(Color.orange, 120)) })
		Ok({})
	})?

	# The debug FPS counter is styled like everything else rather than being a
	# bare corner: `{ pos, size, color }`, and `pos` is the record, not the call.
	frame.fps!({ pos: { x: 24, y: size.height - 32 }, size: 16, color: Color.with_alpha(Color.ray_white, 160) })
	Ok({})
}
