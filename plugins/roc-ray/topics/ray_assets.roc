## Assets: a store, host-owned textures, sprites, and sound.
##
## Nothing here is loaded by naming a path in a drawing call. A store is opened
## once on a `Files.ReadDir` handle, textures and sounds are loaded through it, and what
## the app holds afterwards is a reference-counted host handle it keeps in the
## model. Dropping the last reference unloads the texture, so there is no
## unload call to forget.
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Assets
import rr.Audio
import rr.Color
import rr.Draw
import rr.Files
import rr.Math
import rr.Sprite

Model : {
	## Kept because a later load needs it, not because drawing does.
	store : Assets.Store,
	sheet : Assets.Texture,
	## Generated rather than read, which is why it is legal in `update!` as
	## well: only the calls that read the disk wait.
	swatch : Assets.Texture,
	walker : Sprite.Animation,
	blip : Audio.Sound,
	facing : F32,
}

Msg : []

program = { init!, update!, render! }

dev_flag = "--dev"

## Assets ship with the game, so a built game reads them beside the
## executable, which needs no declaration and works from any directory.
## `roc main.roc` builds its executable in a cache folder that has no assets, so
## `--dev` reads the source tree, and that read needs the declaration. Save
## files go in `io.files().app_data!()`, as `ray_project` shows.
config : List(Str) -> App.Config
config = |args| {
	base = App.default.with_title("Topic: assets")
	if List.contains(args, dev_flag) {
		base.with_permission(Directory("assets", ReadOnly))
	} else {
		base
	}
}

open_assets! : App.Io => Try(Files.ReadDir, _)
open_assets! = |io|
	if List.contains(io.args!(), dev_flag) {
		io.files().open_dir_read!("assets")
	} else {
		exe_dir = io.files().beside_executable!()?
		exe_dir.subdir("assets")
	}

## The error set is `_`. It is a type argument, so a written-out list is
## closed and has to name every tag each `?` can raise: opening a store, loading
## a texture and a sound, and generating one, is a set 23 tags wide.
## Upstream's examples spell it out. Inference writes the same set.
init! : App.Init(Model, _)
init! = App.init_for_args(
	config,
	|io| {
		# The store is opened on a directory handle, and anchors every relative
		# path that follows. A path that would escape it is refused rather than
		# rewritten, so "../secrets" is `PathInvalid` and not a read.
		store = Assets.open!(open_assets!(io)?, IgnoreManifest)?

		# Opening and `load_texture!` wait: legal in `init!`, where they block
		# startup, and in tasks, where they park the task. Both are refused in
		# `update!` and `render!`, and both type-check there.
		sheet = Assets.load_texture!(store, "walker.png")?

		Ok({
			store,
			sheet,
			swatch: Assets.generate_color_texture!({ width: 16, height: 16, color: Color.orange })?,
			walker: Sprite.animation({ frame_count: 8, fps: 12 }),
			# Sounds, music, fonts and shaders load through the same store.
			blip: Audio.load_sound!(store, "blip.wav")?,
			facing: 1,
		})
	},
)

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, input, _io| {
	# Pure, so animation advances in `update!` where the rest of the simulation
	# is. Only the draw needs a frame.
	# `Sprite` is a nominal type and carries receivers. `Sprite.Animation` is a
	# plain record alias and carries none, so its helpers are static calls.
	walker = Sprite.step(model.walker, input.time.elapsed_seconds)

	# Playing a sound is a host-state effect: legal in `init!`, `update!` and
	# tasks, refused in `render!`.
	if input.devices.key_pressed(KeySpace) {
		model.blip.play!()
	}

	Ok({ ..model, walker, facing: if input.devices.key_down(KeyLeft) -1 else 1 })
}

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
	frame.clear!(Color.from_hex_rgb(0x101820))

	# A texture draws through a configuration value rather than through
	# arguments: `Draw.texture_at` covers the whole texture, `Draw.texture_draw`
	# starts a fuller one.
	frame.texture!(Draw.texture_at(model.swatch, { x: 24, y: 24 }))

	# A sprite is a plain record of texture, source rectangle and transform.
	# Each transform receiver is a noun that sets what it names: `.rotation(r)`,
	# not `.with_rotation(r)`, which does not exist.
	Sprite.from_texture(model.sheet)
		.source(Sprite.animation_source(model.walker, { frame_size: Math.vec2(32, 32), row: 0 }))
		.pos(Math.vec2(400, 300))
		.origin(Math.vec2(16, 16))
		.scale_xy(Math.vec2(3 * model.facing, 3))
		.tint(Color.white)
		.draw!(frame)

	Ok({})
}
