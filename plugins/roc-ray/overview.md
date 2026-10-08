# roc-ray in one page

The platform over raylib, with the HTTP types from `roc-lang/http`.
There is no separate `roc-ray-types` package. Every type is `rr.*`.
`get_builtin_module Draw` for the full API, `search_symbols Task.spawn!` for one
signature, `search scope="roc-ray"` when you do not know the name,
`list_roc_index kind="examples"` for complete programs that all compile, and
`search_roc_syntax query="ray_game"` for a worked program on one subject:
`ray_project`, `ray_game`, `ray_app`, `ray_draw`, `ray_input`, `ray_tasks`,
`ray_text`, `ray_assets`.

## Starting a project

A game is one `main.roc`. The platform line is a release URL that the first
build downloads and caches, so the only install is a Roc nightly. The bundle's
own header pins `nightly-2026-09-27-a3ce7f1`. Under any other nightly, every
check reports a "roc version mismatch" warning on the platform's `main.roc`.
That warning is not in your code.

```bash
roc main.roc -- --dev                 # build and run; args after -- go to the app
mkdir -p dist && cp -r assets dist/   # the folder must exist, and assets go beside the game
roc build main.roc --output=dist/game # the executable a finished game ships
```

`App.Config` is opaque. `App.default` is the only way to start one, and every
change is a receiver.

```roc
config = App.default
	.with_title("My game")
	.with_size({ width: 1280, height: 720 })
	.with_resizable(Bool.True)
	.with_frame_pacing(Capped(120))
	.with_permission(WorkingDirectory(ReadOnly))
```

Defaults: 800x600, `Capped(240)`, and `ExitKey(KeyEscape)`, so every app quits
on Escape with no code. `with_exit_key(NoExitKey)` turns that off. `VSync`
presents with the display, `Capped(fps)` limits on the CPU, `Uncapped` is for
measurement. Upstream reports X11-through-Wayland running far below refresh
under `VSync`, so `Capped(60)` or `Capped(120)` is the safer Linux default.

Nothing reads the disk by ambient path. Files come through directory handles
from `io.files()`, and anything beyond the app's own resources is declared
with `with_permission`: `Directory(path, ReadOnly)`, `WorkingDirectory(..)`,
`HttpOrigin(url)`, `EnvVar`, `ClipboardRead`, `UdpBind`, `Command`. Each
declaration grants that access. A target outside every declaration answers
`PermissionDenied`. A facility that is never declared stops the app. A built
game reads its assets beside the executable, which needs no declaration.
`ray_assets` shows the pattern: the source tree with `--dev`, else beside the
executable. Save files go in `io.files().app_data!()`.
`App.init_for_args` takes `List(Str) -> App.Config`, so `--dev` can add the
source-tree declaration and a recording mode can ask for a hidden window.

## The application contract

```roc
app [Model, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
}

program = { init!, update!, render! }

init! : App.Init(Model, _)
update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
render! : Model, Draw.Frame => Try({}, [Exit(I64), ScopeLimit])
```

`Msg` is required even with no tasks (`Msg : []`). Without it, the error is
"missing platform required type" at `program`. `update!` takes three arguments.
A two-argument one from an older release is a type mismatch reported at
`program`, quoting the platform's `requires` block. `init!` is
`App.init(config, |io| ...)`. `render!` returns `{}`, so it cannot change the
model. Quitting is `Err(Exit(code))` from `update!`, or `io.exit!(code)` from
`init!` or a task.

`App.Io` is the app's authority, handed to `init!` and `update!` and not to
`render!`. OS access is a method on it: `io.args!()`, `io.entropy!()`,
`io.files()`, `io.http()`, `io.sqlite()`, `io.stdout()`, `io.clipboard()`,
`io.env()`. There is no `App.args!`, `Files.read_text!` or `Http.send!`. A
service value can be passed to a helper or captured by a task.

## Phases, and what the compiler misses

Only drawing is limited by a type: `Draw.Frame` exists only in `render!`.
`init!` and `update!` get the same `App.Io`, so everything else type-checks in
both and stops the app with a programmer error when it runs in the wrong one.

| Phase | Legal | Notably refused |
|---|---|---|
| `init!` | Everything that waits, blocking startup. `io.args!`, `io.entropy!`, `io.default_font!` are legal only here | Drawing, `Task.spawn!` |
| `update!` | Host state: window, audio, clipboard, stdout, textures from bytes, preparing text, `Task.spawn!` | Drawing, every effect that waits |
| Task | Everything that waits: files, HTTP, SQLite, commands, `Task.sleep!` | Drawing, and the model |
| `render!` | Drawing and pure measurement | Preparing text, `Draw.default_font!`, any host-state effect |

The usual mistake is to read a file, load a texture or prepare a label in the
wrong callback. It compiles.

## Input and frame

`App.Input(Msg)` is what one cycle observed: `input.devices` (keys, text,
pointer, pads, and `events` in arrival order), `input.time`, `input.window`,
`input.dropped`, and `input.messages` from finished tasks. `Draw.Frame` is
everything that can be drawn on. `input.devices.key_down(KeyW)` and
`Keys.key_down(input.devices, KeyW)` are one call. `key_down` is a level.
`key_pressed` is an edge, and a tap between two cycles still reads pressed.

## The shape of a game

`ray_game` is upstream's structure as one compiling program.

- The model holds loaded resources beside the world. Restarting rebuilds the
  world and keeps the textures, fonts and sounds.
- Rules are pure. A step takes the world, the controls, and seconds of delta,
  and returns the next world. `Devices.none.with_key_down(KeyW)` and
  `App.Input.for_tests({})` build inputs for `expect`. `Audio.Sound.stub`,
  `Text.font_stub` and `Text.Prepared.stub` build a model without a window.
- `input.time.elapsed_seconds` is F32 seconds since the last cycle. Every rate
  is per second and the step multiplies. The host never calls `update!` twice
  to catch up.
- A pure step cannot play a sound, so it returns cues and `update!` performs
  them. That keeps the rule testable.
- The phase is a tag in the world, and `update!` matches on it.
- Derive what you can. A camera following the player is computed in
  `render!`, not stored.

## Drawing

A style is a value: `Draw.filled`, `Draw.outlined`, `Draw.stroke`,
`Draw.filled_and_outlined` with the width last. A scope is a nested frame, and
the callback's frame is the one the scope applies to. The outer `frame` still
type-checks inside it, so use the inner name.

```roc
	frame.clear!(Color.from_hex_rgb(0x0d1425))
	frame.with_camera!(model.camera, |world| {
		world.circle!({ center: model.pointer, radius: 12, style: Draw.filled(Color.ray_white) })
		Ok({})
	})?
```

`with_camera!`, `with_scissor!` and `with_blend_mode!` raise `ScopeLimit`.
`with_shader!` and `with_render_texture!` add `ScopeUnavailable`. A record
literal is a `Math.Vec2` wherever one is expected.

## Text, and everything else that is loaded

```roc
	|io| {
		font = Draw.default_font!()
		Ok({
			font,
			label: Text.from("Score 0", font).size(24).prepare!()?,
			notes_dir: io.files().working_directory_read!()?,
```

`Text.from` takes the font. `prepare!` is refused in `render!`. The
`Prepared.draw!` it makes is legal only there. For text that changes every
frame, `Text.from(s, font).draw!(frame, placement)` or `frame.text_at!` draw
without preparing. `font.measure(...)` and `prepared.bounds()` are pure and
legal anywhere.

Assets come from a store opened on a handle:
`Assets.open!(dir, IgnoreManifest)`, then `Assets.load_texture!(store, path)`,
`Audio.load_sound!(store, path)`, `Draw.load_store_font!(store, ...)`. Loading
from disk waits, so it belongs in `init!` or a task. Generating from bytes is
legal in `update!`. Handles are reference-counted and unload themselves. Paths
are relative, may not contain `..`, and a bad one answers `PathInvalid`.

## Work that waits

```roc
	if input.devices.key_pressed(KeyR) {
		notes_dir = model.notes_dir
		Task.spawn!(input, || Read(notes_dir.read_text!("notes.txt")))
	}
```

`Task.spawn!` takes the input as the witness that pins the message type. It is
never read, and `init!` has none to pass. The closure cannot touch the model,
and its value arrives on a later `input.messages` in the order tasks finished.
Overlapping requests of one kind need an id in the message. Inside a task, a
waiting effect returns normally, so load-parse-fetch is straight-line code
with `?`. Tasks run on the frame thread, so a long computation stalls the frame.

## Errors

A tag union in a return type is already open, so `Try(Model, [Exit(I64), ..])`
is a "redundant open tag union" warning, and a warning fails the check. The
union is open for callers but not for the body: a `?` on `with_camera!` against
`Try({}, [Exit(I64)])` is "produces the tag ScopeLimit but the annotated tag
union does not list it". List every tag the body raises, or write `_`.

`App.Init(Model, errors)` takes the set as a type argument, so a list written
there is closed: `App.Init(Model, [])` fails on the first `?`, and the
`ray_assets` startup, which opens a store and loads from it, raises many tags.
`App.Init(Model, _)` lets inference write it.

## Where to start reading

`list_roc_index kind="examples"` names them all. In order:

1. `hello_world` for the whole loop.
2. `move_box` for speed times seconds.
3. `pong` for movement, collision, scoring, generated sound and pure tested rules.
4. `task_sleep` and `async_read` before anything that waits.
5. The closest recipe:
`sprite_and_sound`, `camera`, `particles`, `responsive_ui`, `generated_assets`,
`http_fetch`, `sqlite_scores`, `udp_cursor`, `drop_viewer`, `input_inspector`,
`post_process`, `projective_texture`, `postcard_studio`, `capture_plot`,
`capture_screenshot`, `capture_ui_demo`.

Upstream's `breakout`, `snake`, `top_down` and `cave_climb` are split across
modules and `live_plot` imports a font file, so they are not bundled. Read
them in the repository.

## Traps

- `HttpOrigin` and `get_utf8!` take a `Url`. A literal coerces, even through a
  top-level binding. A runtime `Str` needs `Url.parse` first, and the mismatch
  names the whole `Permission` union.
- A top-level constant is evaluated at compile time, so `show_fps = Bool.False`
  read by an `if` is an "unconditional condition" warning. Put debug flags in
  the model or read them from argv.
- `frame.size!()` is `F32` and legal only in `render!`. `input.window.size` is
  `I32` and is what `update!` lays out with.
- `input.devices.text_input` is `List(U32)` codepoints, at most 32 per cycle.
- `input.time.simulation_nanos` and `monotonic_nanos` are `U64` nanoseconds.
- `Sprite.Animation` is a plain record with no receivers:
  `Sprite.step(animation, dt)`. A `Sprite` carries them, named `.rotation(r)`,
  not `.with_rotation(r)`.
- `io.args!()` includes `argv[0]`, so an app's own flags start at index 1.
- `Http.Client.send!` takes the `roc-lang/http` package's `Request`. Naming it
  means pinning `http: ".../roc-lang/http/releases/download/1.0.0/..."` in
  the app header too. `ray_tasks` has the line.
