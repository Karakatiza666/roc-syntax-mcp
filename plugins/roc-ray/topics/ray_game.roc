## The shape of a game: a pure step, seconds of delta, and effects at the edge.
##
## The platform owns the loop, so a game has only the structure that it gives
## itself. Upstream's examples use three layers: a
## `Model` holding loaded resources beside the changing world, a pure step that
## takes the world and the seconds since the last cycle and returns the next
## world, and an `update!` that performs whatever the step asked for.
##
## With this structure, `expect` can test the game's rules without a window,
## an audio device, or a frame.
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Audio
import rr.Camera
import rr.Color
import rr.Devices
import rr.Draw
import rr.Keys
import rr.Math

## Tuning lives at the top level, named, and in units the step can use without
## converting: pixels per second, not pixels per frame.
speed = 260.F32

coin_radius = 18.F32

shake_decay = 4.F32

## The game's phase, and the reason `update!` is a `match` rather than a chain
## of `if`s. This tag stops a paused or finished game from advancing its
## physics.
GameState : [Playing, Won]

World : {
	player : Math.Vec2,
	coins : List(Math.Vec2),
	score : U64,
	shake : F32,
	state : GameState,
}

## What the pure step asks for and cannot do itself. Sound is an effect, and an
## effect in the middle of a rule makes the rule untestable, so the step names
## the cue and `update!` performs it.
Cue : [Collected, Finished]

Sounds : {
	pickup : Audio.Sound,
	win : Audio.Sound,
}

## Loaded resources sit beside the world rather than inside it, so a restart
## rebuilds the world and keeps everything that was expensive to load.
Model : {
	world : World,
	sounds : Sounds,
}

Msg : []

program = { init!, update!, render! }

start_coins : List(Math.Vec2)
start_coins = [{ x: 240, y: 180 }, { x: 560, y: 320 }, { x: 380, y: 460 }]

new_world : World
new_world = {
	player: { x: 400, y: 300 },
	coins: start_coins,
	score: 0,
	shake: 0,
	state: Playing,
}

## One cycle of play: the next world together with the cues it wants performed.
##
## `dt` is a plain parameter rather than something read off an input, so the
## caller decides what a step covers and an `expect` can hand it a number.
advance : World, Math.Vec2, F32 -> { world : World, cues : List(Cue) }
advance = |world, dir, dt| {
	## Every rate is multiplied by the seconds the last cycle took. A frame
	## count would tie the game's speed to the machine it runs on, and the
	## platform paces frames rather than steps.
	player = Math.add(world.player, Math.scale(dir, speed * dt))
	reached = |coin| Math.distance(coin, player) <= coin_radius
	taken = List.count_if(world.coins, reached)
	coins = List.drop_if(world.coins, reached)
	score = world.score + taken
	won = List.is_empty(coins)

	{
		world: {
			player,
			coins,
			score,
			## A decaying number rather than a timer that has to be started and
			## stopped: it is one subtraction, and it cannot get stuck on.
			shake: Math.clamp(world.shake - shake_decay * dt, 0, 1) + (if taken > 0 1 else 0),
			state: if won Won else Playing,
		},
		cues: List.concat(
			List.repeat(Collected, taken),
			if won and !(List.is_empty(world.coins)) [Finished] else [],
		),
	}
}

## 1 while either key of a pair is held. Top-level rather than a closure inside
## `direction`: under nightly-2026-09-27-a3ce7f1 a local closure capturing
## `keys` makes the `if` below an "unconditional condition" warning.
axis : Devices.Snapshot, Keys.Key, Keys.Key -> F32
axis = |keys, a, b| if keys.key_down(a) or keys.key_down(b) 1 else 0

## The direction the keys ask for, normalized so a diagonal is not faster than
## an axis. A `Devices.Snapshot` is a plain value, so this is pure, and
## `Devices.none.with_key_down(KeyW)` builds one for an `expect`.
direction : Devices.Snapshot -> Math.Vec2
direction = |keys| {
	raw = {
		x: axis(keys, KeyRight, KeyD) - axis(keys, KeyLeft, KeyA),
		y: axis(keys, KeyDown, KeyS) - axis(keys, KeyUp, KeyW),
	}
	if raw.x == 0 and raw.y == 0 raw else Math.normalize(raw)
}

init! : App.Init(Model, _)
init! = App.init(
	App.default.with_title("Topic: the shape of a game").with_frame_pacing(Capped(120)),
	|_io| Ok({
		world: new_world,
		sounds: {
			pickup: Audio.gen_tone!({ freq: 880, ms: 90 })?,
			win: Audio.gen_tone!({ freq: 1320, ms: 260 })?,
		},
	}),
)

## The only place where an effect happens, and only because a rule asked for it.
perform_cue! : Sounds, Cue => {}
perform_cue! = |sounds, cue|
	match cue {
		Collected => sounds.pickup.playback().with_volume(0.5).play!()
		Finished => sounds.win.play!()
	}

## Escape needs no check here: `App.default` already ends the app on it, and
## `Err(Exit(code))` is the way to quit on anything else.
update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, program_input, _io| {
	input = program_input.devices

	next =
		match model.world.state {
			Playing =>
				advance(
					model.world,
					direction(input),
					## The seconds the last cycle took. `simulation_nanos` on the
					## same record is `U64` nanoseconds. Use it to measure time,
					## not to move things.
					program_input.time.elapsed_seconds,
				)

			## A finished game still runs `update!` every cycle. A restart
			## rebuilds the world, so nothing loaded is in the world.
			Won => if input.key_pressed(KeySpace) { { world: new_world, cues: [] } } else { { world: model.world, cues: [] } }
		}

	for cue in next.cues {
		perform_cue!(model.sounds, cue)
	}

	Ok({ ..model, world: next.world })
}

## The camera follows the player, so it is a function of the world and is
## derived here rather than stored. If the model stores a value that it can
## derive, the two copies can disagree.
camera_for : World -> Camera.Camera2D
camera_for = |world|
	Camera.follow(
		Math.add(world.player, Math.vec2(world.shake * 3, 0)),
		{ screen: { x: 800, y: 600 }, zoom: 1 },
	)

## `with_camera!` can answer `ScopeLimit`, so the set names it. Open output
## unions let a caller widen this. They do not let the body raise a tag that
## the annotation leaves out.
render! : Model, Draw.Frame => Try({}, [Exit(I64), ScopeLimit])
render! = |model, frame| {
	frame.clear!(Color.from_hex_rgb(0x101820))

	frame.with_camera!(
		camera_for(model.world),
		|world_frame| {
			for coin in model.world.coins {
				world_frame.circle!({ center: coin, radius: coin_radius, style: Draw.filled(Color.yellow) })
			}
			world_frame.circle!({ center: model.world.player, radius: 14, style: Draw.filled(Color.ray_white) })
			Ok({})
		},
	)?

	## The HUD is drawn outside the camera scope, so it stays put while the
	## world moves under it.
	frame.text_at!({
		pos: { x: 24, y: 24 },
		text: model.world.score.to_str(),
		size: 22,
		color: Color.ray_white,
	})
	Ok({})
}

## Controls read from a built snapshot, no window involved.
expect direction(Devices.none.with_key_down(KeyW)) == { x: 0, y: -1 }

## A whole input, for a test of anything that reads one: `for_tests` and the
## `with_*` receivers build it, and its fields read as they do in `update!`.
expect {
	input : App.Input(Msg)
	input = App.Input.for_tests({}).with_devices(Devices.none.with_key_down(KeyD))
	direction(input.devices) == { x: 1, y: 0 }
}

## A model built from stubs, which is what makes the rules testable. `Sound`,
## `Font` and `Text.Prepared` each carry one: a handle that resolves to no host
## resource, so playing it is a no-op rather than a crash.
test_world : World
test_world = { ..new_world, coins: [{ x: 400, y: 300 }, { x: 700, y: 300 }] }

## Movement is in pixels per second, so half the elapsed time is half the
## distance. The `dt` parameter exists to make this true.
expect {
	step = advance({ ..test_world, coins: [] }, Math.vec2(1, 0), 0.5)
	step.world.player.x == test_world.player.x + speed * 0.5
}

## A coin under the player is collected once, scores once, and asks for exactly
## one sound.
expect {
	step = advance(test_world, Math.vec2(0, 0), 0.016)
	step.world.score == 1 and step.cues == [Collected]
}

## Taking the last coin wins, and says so once rather than every cycle after.
expect {
	first = advance({ ..test_world, coins: [{ x: 400, y: 300 }] }, Math.vec2(0, 0), 0.016)
	again = advance(first.world, Math.vec2(0, 0), 0.016)
	first.world.state == Won and first.cues == [Collected, Finished] and again.cues == []
}
