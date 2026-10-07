## Every snippet the overview page shows, in one app, so that the page always
## matches code that compiles. `plugin validate` fails the page when a fenced Roc block
## on it has no line-for-line home here.
app [Model, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
}

import rr.App
import rr.Camera
import rr.Color
import rr.Draw
import rr.Files
import rr.Math
import rr.Task
import rr.Text

Model : {
	label : Text.Prepared,
	font : Text.Font,
	pointer : Math.Vec2,
	camera : Camera.Camera2D,
	levels : Files.ReadDir,
	notes : Str,
}

Msg : [Read(Try(Str, Files.ReadTextError))]

program = { init!, update!, render! }

config = App.default
	.with_title("My game")
	.with_size({ width: 1280, height: 720 })
	.with_resizable(Bool.True)
	.with_frame_pacing(Capped(120))
	.with_permission(Directory("levels", ReadOnly))

init! : App.Init(Model, _)
init! = App.init(
	config,
	|io| {
		font = Draw.default_font!()
		Ok({
			font,
			label: Text.from("Score 0", font).size(24).prepare!()?,
			levels: io.files().open_dir_read!("levels")?,
			pointer: { x: 0, y: 0 },
			camera: Camera.centered(Math.vec2(0, 0), Math.vec2(800, 600)),
			notes: "",
		})
	},
)

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, input, _io| {
	if input.devices.key_pressed(KeyR) {
		levels = model.levels
		Task.spawn!(input, || Read(levels.read_text!("one.txt")))
	}
	notes = List.fold(input.messages, model.notes, |_, Read(r)| r ?? "unreadable")
	if input.devices.key_pressed(KeyQ) {
		Err(Exit(0))
	} else {
		Ok({ ..model, notes, pointer: input.devices.mouse.position() })
	}
}

render! : Model, Draw.Frame => Try({}, [Exit(I64), ScopeLimit])
render! = |model, frame| {
	frame.clear!(Color.from_hex_rgb(0x0d1425))
	frame.with_camera!(model.camera, |world| {
		world.circle!({ center: model.pointer, radius: 12, style: Draw.filled(Color.ray_white) })
		Ok({})
	})?
	model.label.draw!(frame, { pos: { x: 400, y: 24 }, color: Color.white, align: (Top, Center) })
	Ok({})
}
