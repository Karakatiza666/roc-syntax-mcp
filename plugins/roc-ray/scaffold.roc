## The app `roc_check` wraps bare code in when the caller names a scope and the
## code carries no header of its own.
##
## Everything above `@user-code` is the prelude. `roc_check` appends each
## `@default` block below it only when the submitted code does not define that
## name. src/roc_check.ts reads both markers, and
## scripts/check-platform-examples.sh compiles the whole file, so the scaffold
## always matches the pinned platform.
app [Model, program] {
	rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

# The compiler does not warn about an unused import. The scaffold imports every
# exposed module, so a snippet that uses Tilemap or Sqlite compiles as submitted.
import rr.App
import rr.Assets
import rr.Audio
import rr.Camera
import rr.Capture
import rr.Cmd
import rr.Color
import rr.Devices
import rr.Draw
import rr.Files
import rr.Font
import rr.Gamepad
import rr.Http
import rr.Keys
import rr.Math
import rr.Mouse
import rr.Permission
import rr.Physics
import rr.Random
import rr.Sprite
import rr.Sqlite
import rr.Stderr
import rr.Stdout
import rr.Task
import rr.Text
import rr.Texture
import rr.Tilemap
import rr.Time
import rr.Trace
import rr.Udp
import rr.Url
import rr.Window
import http.Header
import http.Method
import http.Request
import http.Response

# @user-code

# @default Model
Model : {}

# @default Msg
# The platform's `requires` block names this type, so an app without one does
# not compile even when it spawns no task and delivers no message.
Msg : []

# @default program
program = { init!, update!, render! }

# @default init!
# `crash` has the bottom type, so this type-checks against the Model that the
# submitted code declares. `roc check` stops at types, so nothing here runs.
# There is no annotation, because it would have to name every error tag that
# the `?` operators in the submitted code can raise.
init! = App.init(App.default, |_io| Ok(crash("scaffolded init!: define your own to build a Model")))

# @default update!
# Three arguments. The third is the same `App.Io` that `init!` receives.
update! = |model, _input, _io| Ok(model)

# @default render!
render! = |_model, frame| {
	frame.clear!(Color.black)
	Ok({})
}
