## Shipping: one executable per system, its assets beside it, in one zip.
##
## `roc build` makes an executable for the system it runs on. `--target` makes
## one for another system. The 0.10.0 default bundle has four targets, and no
## other target builds:
##
## | System               | Target       | Build it from                      |
## |----------------------|--------------|------------------------------------|
## | Linux x86-64 (X11)   | `x64v1glibc` | Linux                              |
## | macOS, Intel         | `x64mac`     | Linux or macOS                     |
## | macOS, Apple silicon | `arm64mac`   | Linux or macOS                     |
## | Windows x86-64       | `x64win`     | Windows, with the MSVC build tools |
##
## From Linux, the first three link, because the bundle holds what the linker
## needs. `x64win` from Linux fails at the link step with
## "Error: WindowsSDKNotFound". Build it on a Windows system. There is no ARM
## Linux target: `--target=arm64glibc` fails with "unsupported target" and
## lists the four above.
##
## ```sh
## mkdir -p dist/game-linux-x64/game dist/game-macos-arm64/game
## roc build --target=x64v1glibc main.roc --output=dist/game-linux-x64/game/game
## roc build --target=arm64mac main.roc --output=dist/game-macos-arm64/game/game
## ```
##
## `--opt=speed` is the default, so a plain `roc build` is already the release
## build. `--output` is the full path of the executable, and its directory must
## exist: if not, the build fails with "Error: LinkFailed". With no `--output`,
## the executable is `./main`, named after `main.roc`.
##
## Wayland. The release has a second bundle with the same API, built on
## raylib's native Wayland backend. It is a different platform URL in the app
## header, and it has one target, `x64v1glibc`:
##
## https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/DDs5HiQ8vfCk6zFwWshZ9Dyx3avmQqV9EuNkQn4VGmHi.tar.zst
##
## The default bundle's X11 build also runs under XWayland, so ship that one
## unless you need native Wayland.
##
## `wasm32` is not a roc-ray target (see `wasm_bridge_ray`). For a video, see `ray_capture`.
##
## The executable is self-contained: the host, raylib, SQLite and the encoders
## are linked in. It needs only the system C library and graphics and audio
## (on Linux: X11 or Wayland, OpenGL 3.3, and PulseAudio, PipeWire or ALSA).
## It does need its assets. How the app finds `assets/` beside the executable,
## and from the source tree while you develop, is in `ray_project`. Copy them
## into place:
##
## ```sh
## cp -r assets dist/game-linux-x64/game/
## ```
##
## To check a build on the system it is for, with no person at the keyboard,
## run it with `--host-headless`. `ray_headless` shows the switches and the
## exit codes.
##
## One zip per system. Put `LICENSES/` in each: roc-ray's `LICENSE` and libvpx's
## `vendor/libvpx/LICENSE` from the release tag both ask to go with a binary.
## raylib, SQLite and msf_gif ask for nothing.
##
## ```text
## game-1.0-linux-x64.zip
## └── game/
##     ├── game            (game.exe on Windows)
##     ├── assets/
##     └── LICENSES/
## ```
##
## The executables are not signed with a publisher certificate, so each system
## warns the first time someone runs a downloaded one:
##
## | System  | What the user sees and does                                       |
## |---------|-------------------------------------------------------------------|
## | macOS   | Gatekeeper refuses it. `xattr -dr com.apple.quarantine game`, then run. To stop the warning, sign with an Apple Developer ID and notarize |
## | Windows | SmartScreen says "Windows protected your PC". More info, then Run anyway |
## | Linux   | The execute bit must survive. `zip` and `unzip` keep it. If lost, `chmod +x game` |
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Color
import rr.Draw
import rr.Files

Model : {
	saves : Files.Dir,
	frames : U64,
}

Msg : []

program = { init!, update!, render! }

## The app id names the save directory under the user's home. Saves survive a
## reinstall only while the id stays the same, so choose it before the first
## release and do not change it.
init! : App.Init(Model, _)
init! = App.init(
	App.default
		.with_title("Topic: shipping")
		.with_app_id("dev.example.ship")
		.with_frame_pacing(Capped(60)),
	|io| Ok({ saves: io.files().app_data!()?, frames: 0 }),
)

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, _input, _io| Ok({ ..model, frames: model.frames + 1 })

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
	frame.clear!(Color.from_hex_rgb(0x141b24))
	frame.text_at!({
		pos: { x: 24, y: 24 },
		text: model.frames.to_str(),
		size: 20,
		color: Color.ray_white,
	})
	Ok({})
}
