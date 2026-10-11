## A pixel-art look: draw the scene on a fixed 320x180 canvas, then scale the
## canvas up by a whole number to fill the window.
##
## The canvas is a `Draw.RenderTexture`. Each frame has two passes:
##
## | Pass | Draws on | Coordinates |
## |------|----------|-------------|
## | 1 | the canvas, in `with_render_texture!` | canvas pixels, 0..320 and 0..180 |
## | 2 | the window, one `texture!` call | logical window units |
##
## The shapes and the scope rules are in `ray_draw`. This program shows only
## what changes with a canvas: the scale, the bars at the edges, sharp pixels,
## and the mouse in canvas pixels.
##
## Traps, each found by running a build on a real display:
##
## - The canvas texture is stored upside down. Draw it with
##   `canvas.source()`, which has a negative height. A source of
##   `{ x: 0, y: 0, width: 320, height: 180 }` shows the scene upside down.
## - A scale that is not a whole number gives uneven pixels. At 3.3, the
##   canvas pixels were 6 and 7 screen pixels wide, side by side.
## - Blur comes from the `Bilinear` filter, at any position. With `Point`, a
##   non-whole offset gives no blur, and it moves the image by one screen
##   pixel. Keep the offset and the scale whole.
## - `Draw.RenderTexture.load!` is legal in `init!`, `update!` and a task. In
##   `render!` it type-checks and stops the app with a programmer error.
## - At most 32 render textures are alive at one time. The next `load!` answers
##   `ResourceLimit`. A size of zero answers `RenderTextureLoadFailed`.
##   Load the canvas once in `init!` and keep it in the model.
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Assets
import rr.Color
import rr.Draw
import rr.Math

canvas_width = 320.I32

canvas_height = 180.I32

## A canvas pixel, with (0, 0) at the top left of the canvas.
Pixel : { x : I32, y : I32 }

## Where the canvas goes in the window. `scale` is screen units per canvas
## pixel, and `x` and `y` are the top-left corner of the canvas in the window.
Placement : { scale : I32, x : I32, y : I32 }

Model : {
	canvas : Draw.RenderTexture,

	## The window size from the last `update!`. `update!` and `render!` both
	## call `place` on it, so the mouse and the picture use one placement.
	window : { width : I32, height : I32 },
	cursor : Try(Pixel, [Outside]),
}

Msg : []

program = { init!, update!, render! }

init! : App.Init(Model, _)
init! = App.init(
	App.default.with_title("Pixel canvas").with_size({ width: 960, height: 540 }).with_resizable(Bool.True),
	|_io| {
		canvas = Draw.RenderTexture.load!({ width: canvas_width, height: canvas_height })?
		# A new render texture already samples with `Point`. The call states the
		# filter that this look needs. `Bilinear` on this texture blurs every
		# pixel edge.
		Assets.set_texture_filter!(canvas.texture(), Point)
		Ok({ canvas, window: { width: 960, height: 540 }, cursor: Err(Outside) })
	},
)

## The largest whole scale at which the canvas fits, centered. The rest of the
## window shows as bars. A window smaller than the canvas gets scale 1 and a
## negative offset, so the edges of the canvas are cut.
place : { width : I32, height : I32 } -> Placement
place = |window| {
	scale = I32.max(1, I32.min(window.width // canvas_width, window.height // canvas_height))
	{
		scale,
		x: (window.width - canvas_width * scale) // 2,
		y: (window.height - canvas_height * scale) // 2,
	}
}

## Window units to a canvas pixel, or `Outside` when the point is in a bar.
## Use floor and not truncation: a point 0.5 units left of the canvas is -0.17
## canvas pixels, and truncation makes that pixel 0.
to_canvas : Placement, { x : F32, y : F32 } -> Try(Pixel, [Outside])
to_canvas = |placement, point| {
	scale = I32.to_f32(placement.scale)
	column = F32.floor_to_i32_try((point.x - I32.to_f32(placement.x)) / scale)
	row = F32.floor_to_i32_try((point.y - I32.to_f32(placement.y)) / scale)
	match (column, row) {
		(Ok(x), Ok(y)) =>
			if x >= 0 and y >= 0 and x < canvas_width and y < canvas_height {
				Ok({ x, y })
			} else {
				Err(Outside)
			}
		_ => Err(Outside)
	}
}

## The color of one ground tile. The rule is pure, so an `expect` can test one
## canvas pixel without a window.
ground_color : Pixel -> Color.Rgba
ground_color = |pixel|
	if (pixel.x // 8 + pixel.y // 8) % 2 == 0 {
		Color.from_hex_rgb(0x3e7b27)
	} else {
		Color.from_hex_rgb(0x2f5e1d)
	}

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, input, _io| {
	# `input.window.size` and the mouse position are in the same logical units.
	window = input.window.size
	cursor = to_canvas(place(window), input.devices.mouse.position())
	Ok({ ..model, window, cursor })
}

render! : Model, Draw.Frame => Try({}, [Exit(I64), ScopeLimit, ScopeUnavailable])
render! = |model, frame| {
	frame.with_render_texture!(
		model.canvas,
		|canvas| {
			canvas.clear!(Color.from_hex_rgb(0x5fa8d3))
			canvas.circle!({ center: { x: 260, y: 40 }, radius: 18, style: Draw.filled(Color.from_hex_rgb(0xf9d71c)) })
			for tile in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39] {
				for row in [0, 1, 2] {
					pixel = { x: tile * 8, y: 156 + row * 8 }
					canvas.rectangle!({ x: I32.to_f32(pixel.x), y: I32.to_f32(pixel.y), width: 8, height: 8, style: Draw.filled(ground_color(pixel)) })
				}
			}
			match model.cursor {
				Ok(pixel) => canvas.rectangle!({ x: I32.to_f32(pixel.x), y: I32.to_f32(pixel.y), width: 1, height: 1, style: Draw.filled(Color.white) })
				Err(Outside) => {}
			}
			Ok({})
		},
	)?

	# The clear color is the color of the bars.
	frame.clear!(Color.black)
	placement = place(model.window)
	frame.texture!({
		texture: model.canvas.texture(),
		source: model.canvas.source(),
		dest: {
			x: I32.to_f32(placement.x),
			y: I32.to_f32(placement.y),
			width: I32.to_f32(canvas_width * placement.scale),
			height: I32.to_f32(canvas_height * placement.scale),
		},
		origin: Math.zero,
		rotation: 0,
		tint: Color.white,
	})
	Ok({})
}

## 960x540 is three times 320x180, so it has no bars.
expect place({ width: 960, height: 540 }) == { scale: 3, x: 0, y: 0 }

## The height limits the scale here, and the spare width becomes bars.
expect place({ width: 1000, height: 600 }) == { scale: 3, x: 20, y: 30 }

expect to_canvas({ scale: 3, x: 20, y: 30 }, { x: 132, y: 182 }) == Ok({ x: 37, y: 50 })

## A point in the left bar, 0.5 units from the canvas, is outside it.
expect to_canvas({ scale: 3, x: 20, y: 30 }, { x: 19.5, y: 100 }) == Err(Outside)

expect to_canvas({ scale: 3, x: 20, y: 30 }, { x: 980, y: 100 }) == Err(Outside)

expect ground_color({ x: 8, y: 160 }) != ground_color({ x: 0, y: 160 })
