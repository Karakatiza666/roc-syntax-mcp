## Capture: PNG screenshots, GIF or WebM recordings, and pixel reads of the
## app's own frames.
##
## Each call is legal only in some phases. A call in another phase stops the
## app with a panic that names the phase, and the exit code is 134. `render!`
## gets no `App.Io`, so it cannot reach `io.capture()`.
##
## | Call                         | `init!` | `update!` | `render!` | task |
## |------------------------------|---------|-----------|-----------|------|
## | `screenshot!`                | stops   | stops     | no `io`   | yes  |
## | `screenshot_texture!`        | yes     | stops     | no `io`   | yes  |
## | `start!`                     | yes     | yes       | no `io`   | yes  |
## | `pixel_at!`, `read_region!`  | yes     | yes       | stops     | yes  |
##
## Every capture path is relative to `with_output_dir`. The host refuses a path
## outside it and does not rewrite it: `"../x.png"` is `PathEscapesOutputDir`,
## and `"/tmp/x.png"` is `PathInvalid`. An output directory such as `"../out"`
## stops the app before `init!`, with exit code 1.
##
## A headless run has no pixels. `screenshot!` and `screenshot_texture!` answer
## `Ok({})` and write no file, `pixel_at!` and `read_region!` answer
## `Err(Unavailable)`, and a recording stays `Active` with 0 frames and never
## finishes. Run a pixel test with `--host-hidden --host-frames=N`, which needs a
## display. `ray_headless` lists the switches.
##
## The examples `capture_screenshot`, `capture_plot` and `capture_ui_demo` are
## full recipes: screenshot results shown in the window, a hidden-window WebM
## render, and a recorded walkthrough driven by scripted input.
##
##   roc main.roc -- --record                                # writes captures/demo.webm
##   roc main.roc -- --check --host-hidden --host-frames=30  # exit 0 if the pixels are correct
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Capture
import rr.Color
import rr.Draw
import rr.Task

Model : {
	mode : [Play, Record, Check],
	poster : Draw.RenderTexture,
	shot : [Waiting, Retry, Done(Try({}, Capture.ScreenshotError))],
	export : [Waiting, Done(Try({}, Capture.TextureExportError))],
	pixel : Try(Color.Rgba, Capture.PixelReadError),
}

Msg : [Shot(Try({}, Capture.ScreenshotError)), Exported(Try({}, Capture.TextureExportError))]

program = { init!, update!, render! }

record_flag = "--record"

check_flag = "--check"

background = Color.from_hex_rgb(0x141b24)

poster_color = Color.from_hex_rgb(0x336699)

## The window does not exist yet when the config is read, so the config can
## read argv and ask for a hidden window. A hidden window renders on the GPU as
## a visible one does, and it still needs a display server.
config : List(Str) -> App.Config
config = |args| {
	base = App.default
		.with_title("Topic: capture")
		.with_size({ width: 640, height: 360 })
		.with_output_dir("captures")

	if List.contains(args, record_flag) {
		base.with_visible(Bool.False)
	} else {
		base
	}
}

## `Capture.default` is a 25 FPS, half-scale GIF of at most 300 frames with
## `FixedStep` timing. While the recording is `Active`, `FixedStep` makes
## `input.time.elapsed_seconds` exactly 1/fps on every cycle, here 1/30, so
## the video plays at the correct speed. After the recording,
## `elapsed_seconds` is real time again.
recording : Capture.Recording
recording =
	Capture.default
		.with_path("demo.webm")
		.with_format(WebM)
		.with_fps(30)
		.with_max_frames(90)

## `App.default.with_recording` only stores a recording in the config and
## starts nothing, so `input.capture` stays `Idle`. `start!` starts one.
init! : App.Init(Model, _)
init! = App.init_for_args(
	config,
	|io| {
		args = io.args!()
		mode =
			if List.contains(args, record_flag) {
				Record
			} else if List.contains(args, check_flag) {
				Check
			} else {
				Play
			}

		## `start!` returns `Ok` for a bad recording too. The refusal, for
		## example `PathEscapesOutputDir`, arrives as `Failed` in
		## `input.capture`: on cycle 0 after a start in `init!`, and on the next
		## cycle after a start in `update!`.
		if mode == Record {
			io.capture().start!(recording)?
		}

		## `screenshot_texture!` writes a PNG at the size of the render
		## texture, not of the window. The pixels of the texture are undefined
		## until a `render!` draws into it.
		poster = Draw.RenderTexture.load!({ width: 1280, height: 720 })?
		Ok({ mode, poster, shot: Waiting, export: Waiting, pixel: Err(Unavailable) })
	},
)

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, input, io| {
	## One screenshot can wait for its frame at a time. A second one in that
	## time answers `AlreadyPending` and writes nothing, so ask again.
	shot = List.fold(
		input.messages,
		model.shot,
		|current, message|
			match message {
				Shot(Err(AlreadyPending)) => Retry
				Shot(result) => Done(result)
				Exported(_) => current
			},
	)
	export = List.fold(
		input.messages,
		model.export,
		|current, message|
			match message {
				Exported(result) => Done(result)
				Shot(_) => current
			},
	)

	## `screenshot!` waits for the end of a frame, so it is legal only in a
	## task. Cycle 0 gives the first frame. The PNG has framebuffer pixels: on
	## a display scaled 2x, a 640x360 window writes a 1280x720 PNG.
	retry = match shot {
		Retry => Bool.True
		_ => Bool.False
	}
	if input.time.cycle_count == 0 or retry {
		Task.spawn!(input, || Shot(io.capture().screenshot!("frame0.png")))
	}

	## The task starts after the `render!` of cycle 0 drew into the poster.
	## `screenshot_texture!` keeps the alpha that the app drew.
	if input.time.cycle_count == 1 {
		poster = model.poster
		Task.spawn!(input, || Exported(io.capture().screenshot_texture!(poster, "poster.png")))
	}

	## The host keeps a copy of the screen only after the first read, so the
	## first `Screen` read of a run, and every read in `init!`, is
	## `Err(Unavailable)`. Each later frame costs a full readback while the app
	## keeps reading, so stop when a read succeeds.
	pixel =
		match model.pixel {
			Ok(color) => Ok(color)
			Err(_) => Capture.pixel_at!(Screen, { x: 8, y: 8 })
		}

	next = { ..model, shot: if retry Waiting else shot, export, pixel }

	## At `max_frames` the host writes the file, but the app does not exit.
	## `Finished` stays in `input.capture` until the app exits. A failed
	## recording only prints an error, and the exit code is 0 unless the app
	## exits with its own code.
	match model.mode {
		Play => Ok(next)
		Record =>
			match input.capture {
				Finished(_) => Err(Exit(0))
				Failed(_) => Err(Exit(1))
				_ => Ok(next)
			}
		Check => check!(next, input.time.cycle_count)
	}
}

## A pixel test. `read_region!` gives RGBA bytes, row by row from the top. A
## `Screen` read is always opaque, and a `Target` read keeps the alpha.
check! : Model, U64 => Try(Model, [Exit(I64)])
check! = |model, cycle| {
	strip = Capture.read_region!(Target(model.poster), { x: 0, y: 0, width: 2, height: 1 })
	expected = [poster_color.r, poster_color.g, poster_color.b, 255, poster_color.r, poster_color.g, poster_color.b, 255]
	match (model.pixel, strip, model.shot, model.export) {
		(Ok(color), Ok(bytes), Done(Ok(_)), Done(Ok(_))) =>
			if color == background and bytes == expected {
				Err(Exit(0))
			} else {
				Err(Exit(3))
			}

		## The cycle limit of `--host-frames` ends the run with exit code 0, so
		## a check that never got its results must fail by itself.
		_ => if cycle >= 20 Err(Exit(4)) else Ok(model)
	}
}

render! : Model, Draw.Frame => Try({}, [Exit(I64), ScopeLimit, ScopeUnavailable])
render! = |model, frame| {
	frame.with_render_texture!(
		model.poster,
		|canvas| {
			canvas.clear!(poster_color)
			canvas.circle!({ center: { x: 640, y: 360 }, radius: 200, style: Draw.filled(Color.ray_white) })
			Ok({})
		},
	)?

	frame.clear!(background)
	frame.texture!({
		texture: model.poster.texture(),
		source: model.poster.source(),
		dest: { x: 160, y: 90, width: 320, height: 180 },
		origin: { x: 0, y: 0 },
		rotation: 0,
		tint: Color.white,
	})
	Ok({})
}
