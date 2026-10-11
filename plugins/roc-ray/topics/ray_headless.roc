## Running an app with no person at the keyboard: in CI, as a smoke test, and
## on the system a cross-built executable is for.
##
## Every built RocRay app reads switches that begin with `--host-`. The host
## removes them before the app sees its arguments, so `io.args!()` and the list
## that `App.init_for_args` gives to its config never hold them. An app cannot
## tell that it runs headless. To make the app check itself, give it a flag of
## its own, as `--smoke` does here. `ray_project` shows `init_for_args`.
##
##   ./dist/game --host-headless                          # 3 cycles, then exit 0
##   ./dist/game --host-headless-frames=120               # N cycles, then exit 0
##   ./dist/game --smoke --host-headless-frames=60 --host-keys=3:SPACE~
##   roc main.roc -- --host-headless-frames=120           # through roc: after --
##
## | Switch                       | Effect                                      |
## |------------------------------|---------------------------------------------|
## | `--host-headless`            | No window, GPU or audio device. 3 cycles    |
## | `--host-headless-frames=N`   | Headless, and stop after N cycles           |
## | `--host-frames=N`            | Stop a real windowed run after N cycles     |
## | `--host-hidden`              | Real window, not shown. Needs a display     |
## | `--host-keys=SCRIPT`         | `3:S,4:LEFT+X` holds keys on those cycles.  |
## |                              | `3:SPACE~` taps: pressed, never held        |
## | `--host-text=SCRIPT`         | `2:ab,3:c` types text on those cycles       |
## | `--host-drops=SCRIPT`        | `4:/tmp/a.png` arrives in `input.dropped`   |
## | `--host-close=CYCLE[,CYCLE]` | A close request, as the close button makes  |
## | `--host-stats-output=PATH`   | Record an Observatory capture of the run    |
## | `--host-help`                | Print every switch, exit 0                  |
##
## Cycle numbers count from 0, the same as `input.time.cycle_count`. A value
## needs `=`: `--host-headless-frames 60` is an "unknown host argument". An
## unknown or malformed `--host-` switch prints the usage and exits with 2
## before `init!` runs, so a typo in CI fails the job and does not pass it.
##
## The exit code is the result that CI reads:
##
## | Run                                      | Exit code |
## |------------------------------------------|-----------|
## | All N cycles ran                         | 0         |
## | `update!` returned `Err(Exit(code))`     | code      |
## | `init!` returned an error, for example a missing asset | not 0 (255) |
## | A `dbg` ran, and the app exited with 0   | 1         |
## | Bad `--host-` switch                     | 2         |
##
## A headless run loads files, assets, fonts and sounds as a windowed run
## does. Thus an executable whose `assets/` was not copied beside it fails in
## `init!`, and a headless run is a correct smoke test of a cross-built game.
## The x64win link needs the Windows SDK, so a Linux machine cannot make it.
## Build on a Windows runner and run the result there, in the same job.
## `release_multiplatform_ray` lists the targets and the build options.
##
##   mkdir -p dist
##   roc build main.roc --target=x64win --output=dist/game.exe
##   cp -r assets dist/
##   dist/game.exe --host-headless --host-headless-frames=3
##
## `--host-hidden` and `--host-frames=N` use the real renderer, so captures
## write real pixels. They need a display server. With no display the host
## stops with a GLFW assertion. On a Linux runner without a display, use
## `--host-headless`.
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Capture
import rr.Color
import rr.Draw
import rr.Task

Model : {
	smoke : Bool,
	x : F32,
	jumps : U64,
	shot : [NotAsked, Asked, Answered(Try({}, Capture.ScreenshotError))],
}

Msg : [Shot(Try({}, Capture.ScreenshotError))]

program = { init!, update!, render! }

smoke_flag = "--smoke"

## The cycle by which the scripted tap must have arrived. Keep it below the
## N of `--host-headless-frames=N`. When the host stops the run first, the
## exit code is 0, and a check that did not run yet passes.
smoke_deadline = 30

## Exit codes of this app's own checks, so a CI log tells them apart.
missed_tap = 3
out_of_bounds = 4

init! : App.Init(Model, _)
init! = App.init(
	App.default
		.with_title("Topic: headless runs")
		.with_size({ width: 640, height: 360 }),
	|io|
		Ok({
			## `args!` holds `argv[0]` and the app's own flags, never a
			## `--host-` switch.
			smoke: List.contains(io.args!(), smoke_flag),
			x: 0,
			jumps: 0,
			shot: NotAsked,
		}),
)

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, input, io| {
	## Headless time is fixed: `elapsed_seconds` is 0 on cycle 0 and exactly
	## 1/60 after it, so two runs with one script give one result. While a
	## task is live, each headless cycle also waits 1/60 s of real time. A
	## task that waits 2 s needs about 120 cycles, and a task that is still
	## running when the last cycle ends is abandoned with a warning, exit 0.
	dt = input.time.elapsed_seconds

	## A scripted key arrives through the same path as a real one. `3:SPACE~`
	## is one `key_pressed` edge on cycle 3, with no `key_down`.
	jumps = if input.devices.key_pressed(KeySpace) model.jumps + 1 else model.jumps
	x = model.x + 120 * dt

	## Headless has no framebuffer. `screenshot!` answers `Ok({})` and writes
	## no file, and `Capture.pixel_at!` answers `Err(Unavailable)`. A
	## recording started with `io.capture().start!` stays `Active` with 0
	## frames and never becomes `Finished`, so an app that waits for
	## `Finished` to quit runs until the host's cycle limit. `ray_capture`
	## shows the capture calls.
	shot =
		if input.time.cycle_count == 1 {
			Task.spawn!(input, || Shot(io.capture().screenshot!("frame.png")))
			Asked
		} else {
			List.fold(
				input.messages,
				model.shot,
				|_, message|
					match message {
						Shot(result) => Answered(result)
					},
			)
		}

	next = { ..model, x, jumps, shot }

	## The checks run only under the app's own flag. An inline `expect` is
	## not a check here: `roc build` leaves it out of the executable, and
	## only an `--opt=dev` build reports it. A `dbg` makes the exit code 1
	## even when every check passed, so remove it before CI runs the app.
	if !model.smoke {
		Ok(next)
	} else if x < 0 or x > 640 {
		Err(Exit(out_of_bounds))
	} else if jumps > 0 {
		## The check is done. Ending the run here, and not at the host's
		## cycle limit, makes the exit code mean "checked".
		Err(Exit(0))
	} else if input.time.cycle_count >= smoke_deadline {
		Err(Exit(missed_tap))
	} else {
		Ok(next)
	}
}

## Headless calls `render!` every cycle, and every draw call is accepted and
## draws nothing. A run proves that the drawing code does not crash, not that
## it draws the correct pixels.
render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
	frame.clear!(Color.from_hex_rgb(0x141b24))
	frame.circle!({ center: { x: model.x, y: 180 }, radius: 16, style: Draw.filled(Color.ray_white) })
	Ok({})
}
