## Starting a project: the window, the declarations, the arguments, and where
## a path points.
##
## Nothing is installed to build a RocRay app. The platform line in the header
## is a release URL, and the first build downloads and caches it, so an author
## supplies only a Roc nightly. The release and the nightly are a pair: the
## 0.10.0 bundle's own header pins `nightly-2026-09-27-a3ce7f1`, and under any
## other nightly every `roc check` reports a "roc version mismatch" warning on
## the platform's `main.roc`. That warning is not in the app's code.
##
## `roc main.roc` builds and runs. Use it while you write code.
## `roc build main.roc --output=dist/game` leaves an executable behind, which is
## what a finished game ships. The build fails if `dist/` does not exist, and
## the game reads `dist/assets/`, so copy `assets/` there. Arguments after `--`
## go to the app: `roc main.roc -- --dev`.
##
## Nothing reads the disk by ambient path. A file is read through a directory
## handle from `io.files()`, and every directory beyond the app's own is
## declared in the config with `with_permission`. Each declaration grants that
## access.
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Assets
import rr.Capture
import rr.Color
import rr.Draw
import rr.Files
import rr.Random
import rr.Text

Model : {
	font : Text.Font,
	store : Assets.Store,
	saves : Files.Dir,
	## Seeded once at startup and advanced in `update!`, so the whole run
	## replays from its seed. Nothing else in the platform makes one run differ
	## from the last.
	rng : Random.State,
	headless : Bool,
}

Msg : []

program = { init!, update!, render! }

dev_flag = "--dev"

## The window is configured before there is a window, and the configuration is
## opaque: `App.default` is the only way to start one and every change is a
## receiver, so a half-built config cannot be assembled with a record update.
##
## The defaults are 800x600, `Capped(240)`, a visible cursor, and
## `ExitKey(KeyEscape)`: an app that never reads Escape still closes when it is
## pressed. `with_exit_key(NoExitKey)` turns that off.
##
## Frame pacing is one tagged choice rather than a set of fields. `VSync` asks
## the driver to present with the display. `Capped(fps)` limits the loop on the
## CPU. `Uncapped` does neither and is for measurement. Upstream reports X11
## applications presented through a Wayland compositor running far below the
## refresh rate under `VSync`, so `Capped(60)` or `Capped(120)` is the safer
## default to ship on Linux.
config : List(Str) -> App.Config
config = |args| {
	base = App.default
		.with_title("Topic: starting a project")
		## Names the private data, config and cache directories that
		## `io.files().app_data!()` and its siblings open. No declaration needed.
		.with_app_id("dev.example.topic")
		.with_size({ width: 960, height: 600 })
		## A minimum size applies only to a window that the user can resize, so
		## set the two together. Without the second, the first does nothing.
		.with_resizable(Bool.True)
		.with_min_size({ width: 640, height: 400 })
		.with_frame_pacing(Capped(120))

	## While developing, the assets are in the source tree, not beside the
	## executable `roc main.roc` builds in its cache. Reading them needs the
	## directory declared. A target no declaration covers answers
	## `PermissionDenied`. A facility that is never declared stops the app.
	dev =
		if List.contains(args, dev_flag) {
			base.with_permission(Directory("assets", ReadOnly))
		} else {
			base
		}

	## A recording mode is possible only because this code reads argv here and
	## not in `init!`. The window does not exist yet, so this is the last point
	## at which an app can ask for a hidden one.
	if List.contains(args, "--record") {
		dev
			.with_visible(Bool.False)
			.with_output_dir("out")
			.with_recording(Capture.default.with_path("demo.gif").with_format(Gif).with_fps(25).with_max_frames(150))
	} else {
		dev
	}
}

## The asset directory: the source tree with `--dev`, else beside the
## executable, which needs no declaration and does not depend on the directory
## the user launched from. Paths handed to a handle are relative and may not
## contain `..`. A path that breaks the rule answers `PathInvalid`.
open_assets! : App.Io => Try(Files.ReadDir, _)
open_assets! = |io|
	if List.contains(io.args!(), dev_flag) {
		io.files().open_dir_read!("assets")
	} else {
		exe_dir = io.files().beside_executable!()?
		exe_dir.subdir("assets")
	}

## `_` is the error set. It is a type argument, so a list written out is closed
## and must name every tag the body's `?` can raise.
init! : App.Init(Model, _)
init! = App.init_for_args(
	config,
	|io| {
		Ok({
			## `Draw.default_font!` is raylib's built-in font. A font file set by
			## `with_default_font` is answered by `io.default_font!()` instead,
			## legal only in `init!`, and its path needs a declared directory.
			font: Draw.default_font!(),
			store: Assets.open!(open_assets!(io)?, IgnoreManifest)?,
			saves: io.files().app_data!()?,
			## `entropy!` is the one call that reads the operating system. An
			## app that must reproduce a run writes a constant seed instead.
			## Legal only in `init!`, like `args!`.
			rng: Random.seed(U64.to_u32_wrap(io.entropy!())),
			## `args!` includes `argv[0]`, so an app's own flags start at 1.
			headless: List.contains(io.args!(), "--record"),
		})
	},
)

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, program_input, _io| {
	roll = Random.step(model.rng, Random.bounded_i32(0, 99))

	if program_input.devices.key_pressed(KeySpace) {
		Ok({ ..model, rng: roll.state })
	} else {
		Ok(model)
	}
}

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
	frame.clear!(Color.from_hex_rgb(0x141b24))

	## `frame.size!()` is the surface being drawn to, in `F32`, and is legal
	## only here. Layout logic in `update!` reads `input.window.size`, which is
	## the same number as `I32`.
	surface = frame.size!()

	frame.text_at!({
		pos: { x: 24, y: 24 },
		text: if model.headless "recording" else "windowed",
		size: 20,
		color: Color.ray_white,
	})
	frame.text_at!({
		pos: { x: 24, y: 52 },
		text: surface.width.to_str(),
		size: 18,
		color: Color.gray,
	})
	Ok({})
}
