## A RocRay game in the browser: one platform-free core, two runners.
##
## roc-ray 0.10.0 has no wasm32 target. `--target=wasm32` fails with
## "unsupported target", and upstream closed the web target as not planned
## (roc-ray issue #154). So the rules and the picture of the game go in a
## module that imports no platform. Two runners drive that module:
##
## | File               | Imports       | Job                                                  |
## |--------------------|---------------|------------------------------------------------------|
## | `Game.roc`         | no platform   | the model, `advance`, `frame` as a list of shapes    |
## | `main.roc`         | `rr`          | roc-ray devices to `Input`, shapes to `Draw` calls   |
## | `web.roc`          | `pf` (yours)  | boxes the model, unpacks the input numbers           |
## | `platform/`        | nothing       | `main.roc` with a `wasm32` target, the host, `host.wasm` |
## | the page           | (JavaScript)  | the clock, the keys, the canvas, WebAudio            |
##
## This file holds the core and the roc-ray runner in one app, so that the
## checks compile both. In a project, move everything above the runner into
## `Game.roc`, inside `Game :: [].{ ... }`. Other files then write
## `Game.Shape`. The wasm side is in comments at the end, because no app can
## import two platforms. It was built and run with nightly
## `nightly-2026-09-27-a3ce7f1`, the nightly that roc-ray 0.10.0 pins.
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Color
import rr.Devices
import rr.Draw
import rr.Keys

# The core. Nothing from here to the runner uses `rr`.

## A frame is data. Both painters read this one list. The union is structural
## (`:`, not `:=`), so the wasm platform can declare the same union and the
## compiler unifies the two by shape. Colors are `0xRRGGBBAA`, which
## `Color.from_hex_rgba` reads, and which the page writes as a `#rrggbbaa`
## CSS color.
##
## `Poly` is convex only. A canvas fills any polygon, but `convex_polygon!`
## fills a fan from the first point, so a concave polygon also fills its notch.
## The core cuts a concave shape into convex pieces, and both painters draw
## the same picture.
Shape : [
	Rect({ x : F32, y : F32, width : F32, height : F32, rgba : U32 }),
	Disc({ x : F32, y : F32, radius : F32, rgba : U32 }),
	Poly({ points : List({ x : F32, y : F32 }), rgba : U32 }),
]

## The keys have the names of `Keys.Key`, and `Input` has the names of
## `Devices.Snapshot`, so rules ported from a roc-ray game keep their
## `input.key_down(KeyLeft)` calls. Each key is one bit, because JavaScript
## passes only numbers to a wasm function.
Key : [KeyLeft, KeyRight, KeyUp, KeyDown, KeySpace]

Input := { held : U32, struck : U32 }.{
	key_down : Input, Key -> Bool
	key_down = |input, key| U32.bitwise_and(input.held, bit(key)) != 0

	key_pressed : Input, Key -> Bool
	key_pressed = |input, key| U32.bitwise_and(input.struck, bit(key)) != 0

	from_bits : U32, U32 -> Input
	from_bits = |held, struck| { held, struck }

	## A press is an edge, and it belongs to one step only. When a slow frame
	## owes several steps, the steps after the first get this input.
	held_only : Input -> Input
	held_only = |input| { held: input.held, struck: 0 }

	bit : Key -> U32
	bit = |key|
		match key {
			KeyLeft => 1
			KeyRight => 2
			KeyUp => 4
			KeyDown => 8
			KeySpace => 16
		}
}

## The whole game as one record. A runner is a function of this record, so
## `main.roc` and `web.roc` each hand it over and name no rule.
## `advance` always gets `1 / fps` seconds: each runner keeps a fixed-step
## clock, so the same keys at the same steps play the same game on both.
CanvasApp(model) : {
	size : { width : I32, height : I32 },
	fps : I32,
	title : Str,
	init : model,
	advance : model, Input, F32 -> model,
	frame : model -> List(Shape),
}

Ball : { x : F32, y : F32, lit : Bool }

ball_game : CanvasApp(Ball)
ball_game = {
	size: { width: 640, height: 360 },
	fps: 60,
	title: "Ball",
	init: { x: 320, y: 180, lit: Bool.False },
	advance: |ball, input, dt| {
		speed = 200 * dt
		dx = (if input.key_down(KeyRight) speed else 0) - (if input.key_down(KeyLeft) speed else 0)
		dy = (if input.key_down(KeyDown) speed else 0) - (if input.key_down(KeyUp) speed else 0)
		lit = if input.key_pressed(KeySpace) !ball.lit else ball.lit
		{ x: ball.x + dx, y: ball.y + dy, lit }
	},
	frame: |ball| [
		Rect({ x: 0, y: 0, width: 640, height: 360, rgba: 0x101820ff }),
		Poly({ points: [{ x: 40, y: 320 }, { x: 600, y: 320 }, { x: 320, y: 300 }], rgba: 0x27ae60ff }),
		Disc({ x: ball.x, y: ball.y, radius: 20, rgba: if ball.lit 0xf2c94cff else 0x2f80edff }),
	],
}

## To call a function stored in a record field, put the field access in
## parentheses. `ball_game.advance(...)` is a method call, and the check
## reports "missing method".
expect {
	moved = (ball_game.advance)(ball_game.init, Input.from_bits(Input.bit(KeyRight), 0), 0.5)
	moved.x == 420
}

## The fixed-step clock: take the steps that fell due, and keep the rest.
## Both runners use it. The page writes the same loop in JavaScript.
catch_up : CanvasApp(model), model, Input, F32 -> { game : model, owed : F32 }
catch_up = |canvas_app, game, input, owed| {
	dt = 1 / I32.to_f32(canvas_app.fps)
	if owed < dt {
		{ game, owed }
	} else {
		catch_up(canvas_app, (canvas_app.advance)(game, input, dt), input.held_only(), owed - dt)
	}
}

## At most this many steps per frame. A tab that was in the background owes
## many seconds, and without a cap the game would run them all at once.
max_steps : F32
max_steps = 4

# The roc-ray runner.

Model : { game : Ball, owed : F32 }

Msg : []

program = { init!, update!, render! }

init! : App.Init(Model, [])
init! = App.init(
	App.default
		.with_title(ball_game.title)
		.with_size(ball_game.size)
		.with_frame_pacing(Capped(ball_game.fps)),
	|_io| Ok({ game: ball_game.init, owed: 0 }),
)

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, input, _io| {
	cap = max_steps / I32.to_f32(ball_game.fps)
	owed = model.owed + input.time.elapsed_seconds
	Ok(catch_up(ball_game, model.game, ray_input(input.devices), if owed > cap cap else owed))
}

## `Keys.Key` is nominal and `Key` is structural, so the runner pairs them
## once. On the page, the keydown and keyup listeners set the same bits.
key_pairs : List((Key, Keys.Key))
key_pairs = [(KeyLeft, KeyLeft), (KeyRight, KeyRight), (KeyUp, KeyUp), (KeyDown, KeyDown), (KeySpace, KeySpace)]

ray_input : Devices.Snapshot -> Input
ray_input = |devices| {
	bits = List.fold(
		key_pairs,
		{ held: 0, struck: 0 },
		|acc, (key, ray_key)| {
			held = if devices.key_down(ray_key) U32.bitwise_or(acc.held, Input.bit(key)) else acc.held
			struck = if devices.key_pressed(ray_key) U32.bitwise_or(acc.struck, Input.bit(key)) else acc.struck
			{ held, struck }
		},
	)
	Input.from_bits(bits.held, bits.struck)
}

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
	for shape in (ball_game.frame)(model.game) {
		paint!(frame, shape)
	}
	Ok({})
}

paint! : Draw.Frame, Shape => {}
paint! = |frame, shape|
	match shape {
		Rect(r) => frame.rectangle!({ x: r.x, y: r.y, width: r.width, height: r.height, style: Draw.filled(Color.from_hex_rgba(r.rgba)) })
		Disc(d) => frame.circle!({ center: { x: d.x, y: d.y }, radius: d.radius, style: Draw.filled(Color.from_hex_rgba(d.rgba)) })
		Poly(p) => frame.convex_polygon!({ points: p.points, style: Draw.filled(Color.from_hex_rgba(p.rgba)) })
	}

## The wasm side. Steps, in the order a build runs them:
##
## 1. `platform/main.roc` requires the same record of functions over a boxed
##    model, and declares a `wasm32` target. The union in `frame` is the
##    `Shape` above, written out again.
##
##        platform ""
##            requires {
##                [Model : model] for program : {
##                    init : {} -> Box(model),
##                    advance : Box(model), U32, U32 -> Box(model),
##                    frame : Box(model) -> List(Shape),
##                    release : List(Shape) -> {},
##                }
##            }
##            exposes []
##            packages {}
##            provides {
##                "roc_init": init_for_host,
##                "roc_advance": advance_for_host,
##                "roc_frame": frame_for_host,
##                "roc_release": release_for_host,
##            }
##            targets: {
##                inputs_dir: "targets/",
##                wasm32: {
##                    inputs: ["host.wasm", app],
##                    exports: ["advance", "computeFrame"],
##                },
##            }
##
##    `exports:` lists every host function that JavaScript calls. A plain C
##    function that the list leaves out is not a wasm export, and nothing
##    warns. A listed name that the host does not define fails the link with
##    "symbol exported via --export not found".
##
## 2. A provided function owns each `Box` it gets, and drops the model when it
##    returns. A call that only reads the model frees it, and the next
##    `advance` reads freed memory. So every provided function that takes the
##    model gives it back. `advance` returns it already. Wrap `frame`:
##
##        frame_for_host : Box(Model) -> { model : Box(Model), shapes : List(Shape) }
##        frame_for_host = |boxed| {
##            shapes = (program.frame)(boxed)
##            { model: boxed, shapes }
##        }
##
##    Annotate it. With no annotation, `roc glue` stops with "still has an
##    unresolved type variable".
##
## 3. `web.roc` is the app on that platform. It hands over the same
##    `ball_game` that `main.roc` runs:
##
##        app [Model, program] { pf: platform "platform/main.roc" }
##
##        import Game
##
##        Model : Game.Ball
##
##        program = {
##            init: |{}| Box.box(Game.ball_game.init),
##            advance: |boxed, held, struck| {
##                input = Game.Input.from_bits(held, struck)
##                Box.box(Game.catch_up(Game.ball_game, Box.unbox(boxed), input, 1 / 60).game)
##            },
##            frame: |boxed| (Game.ball_game.frame)(Box.unbox(boxed)),
##            release: |_frame| {},
##        }
##
##    The page calls `advance` once per step, so each call owes exactly one
##    step. `release` does nothing on purpose. The host hands the last frame
##    back before it asks for the next one, and Roc frees the list with the
##    layout it knows. The host never walks a `List(Shape)` itself.
##
## 4. Generate the C header, and build the host separately, as a wasm object
##    at the path that `inputs:` names:
##
##        roc glue CGlue.roc platform platform/main.roc
##        zig cc -target wasm32-freestanding -O2 -c platform/host.c \
##            -o platform/targets/wasm32/host.wasm
##
##    `CGlue.roc` is in the Roc repository at `src/glue/src/`, at the commit
##    that the nightly names. The header declares `roc_init`, `roc_frame` and
##    the others, and the shape structs. The host defines `roc_alloc`,
##    `roc_realloc`, `roc_dealloc`, `roc_dbg`, `roc_expect_failed` and
##    `roc_crashed`, keeps the model and the last frame in two statics, and
##    defines `advance` and `computeFrame` as plain functions.
##    `computeFrame` releases the last frame, calls `roc_frame`, keeps the
##    model it gets back, and returns the address of the result. A host that imports nothing runs with
##    `WebAssembly.instantiate(bytes, { env: {} })`.
##
## 5. Build the app: `roc build web.roc --target=wasm32 --output=game.wasm`.
##
## 6. Generate the JavaScript readers. The Roc repository has glue specs for
##    C, Zig and Rust, and none for JavaScript, so write your own. A glue spec
##    is a Roc app on `platform glue`. `roc glue` gives it the platform's type
##    table, and the spec prints a JavaScript function for each type that a
##    provided function uses. Each function decodes a value from a `DataView`
##    at the byte offsets in that table. Do not derive the layout from the
##    source. A record sorts its fields by alignment, largest first, then by
##    name. A tag union numbers its tags by name and puts the tag byte after
##    the payload. On wasm32 a `List` is three 4-byte words in this order:
##    elements, length, capacity. Run the spec with the app and the platform:
##
##        roc glue WebGlue.roc web platform/main.roc
##
## 7. The page runs one loop per animation frame:
##
##    - Add the elapsed time to `owed`, cap it at `max_steps` steps, and call
##      `advance(held, struck)` once for each step that fell due. Clear
##      `struck` after the first step, as `held_only` does.
##    - Store the address from `computeFrame()` in a variable first. Make the
##      `DataView` over `memory.buffer` in the next statement. The call can
##      allocate and grow the wasm memory. After growth, a `DataView` made
##      before the call reads an empty buffer, and each read throws. A call
##      that takes the view as its first argument and `computeFrame()` as its
##      second makes the view first, because JavaScript evaluates arguments
##      in order.
##    - Paint the shapes on a 2D canvas.
##    - Make the `AudioContext` in the first keydown or pointerdown listener.
##      A browser does not start audio before the page gets input.
##
## What stays on the desktop: every service on `App.Io` (`Files`, `Sqlite`,
## `Http`, `Udp`, `Cmd`, `Capture`, the clipboard), `Task.spawn!`, assets,
## fonts and shaders. The core asks for none of them. If the page needs data,
## the host passes it in as numbers or lists, through a provided function.
## To show the native game on a web page with no port, record a video with
## `Capture`, as `ray_capture` shows.
