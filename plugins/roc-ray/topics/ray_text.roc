## Text: one font, two ways to draw, and the phase rule that causes the most
## mistakes.
##
## Text is the clearest case of the platform's phase rule. Preparing text is
## legal in `init!`, `update!` and tasks and refused in `render!`. Drawing it
## needs a `Draw.Frame` and is legal only in `render!`. Neither rule is in the
## type of `prepare!`, so the obvious code, which builds the label where it is
## drawn, compiles and then stops the app.
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.10.0/5xecDmRJroKT9fnSiYsGdCKEzNWLnRKGtHJ5CxuCnpb9.tar.zst" }

import rr.App
import rr.Color
import rr.Draw
import rr.Text

Model : {
	## Prepared once, drawn every frame. The host measured it and holds the
	## laid-out glyphs, so redrawing costs nothing per frame.
	title : Text.Prepared,
	## Kept so that a label that changes can be prepared again in `update!`, the
	## phase that allows it.
	font : Text.Font,
	score : U64,
	score_label : Text.Prepared,
}

Msg : []

program = { init!, update!, render! }

## Written out, the startup set is closed: this body raises `ResourceLimit` and
## nothing else, so the list names exactly that.
init! : App.Init(Model, [ResourceLimit])
init! = App.init(
	App.default.with_title("Topic: text"),
	|_io| {
		# raylib's built-in font, metrics included. Legal here, in `update!`,
		# and in tasks. The phase rule refuses it in `render!`, but measuring is
		# not limited. A `Font` carries an immutable metric snapshot, so
		# `font.measure({ text, size, spacing })` is a pure call legal in every
		# callback, `render!` included.
		font = Draw.default_font!()
		Ok({
			font,
			# `Text.from` takes the font. There is no one-argument form. If the
			# second argument is missing, the error reports a builder with no font.
			title: Text.from("Prepared once", font).size(38).spacing(2.0).prepare!()?,
			score: 0,
			score_label: Text.from("0", font).size(24).prepare!()?,
		})
	},
)

## The platform's own set is open, so `update!` may add tags of its own.
update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64), ResourceLimit])
update! = |model, input, _io| {
	scored = input.devices.key_pressed(KeySpace)
	score = model.score + if scored 1 else 0

	# Re-prepared here, not in `render!`, and only when the text changed:
	# preparation allocates in the host's text table, and it returns
	# `ResourceLimit` when that table is full.
	score_label =
		if scored {
			Text.from(score.to_str(), model.font).size(24).prepare!()?
		} else {
			model.score_label
		}

	Ok({ ..model, score, score_label })
}

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
	frame.clear!(Color.from_hex_rgb(0x101820))

	# `align` is a tuple and the vertical half comes first, defaulting to
	# `(Top, Left)`. `pos` names the point the alignment picks out of the
	# measured bounds rather than the top-left corner.
	model.title.draw!(frame, { pos: { x: 400, y: 60 }, color: Color.ray_white, align: (Top, Center) })
	model.score_label.draw!(frame, { pos: { x: 776, y: 24 }, color: Color.orange, align: (Top, Right) })

	# `bounds` is the measurement the host already made, so laying out around a
	# label costs nothing extra.
	size = model.title.bounds()
	frame.rectangle!({
		x: 400 - size.width / 2 - 12,
		y: 52,
		width: size.width + 24,
		height: size.height + 16,
		style: Draw.outlined(Color.with_alpha(Color.ray_white, 40), 1),
	})

	# A builder draws directly too, with the same placement and no prepare
	# step: it is measured from the font's metrics on every call, which suits
	# text that changes every frame and needs a real font.
	Text.from("frame text", model.font).size(18).draw!(frame, { pos: { x: 24, y: 530 }, color: Color.ray_white })

	# `text_at!` is the third way: no font argument at all, raylib's own. Use
	# it while you build the game and for debug readouts. Use `Prepared` for
	# any text that a player reads and that does not change.
	frame.text_at!({ pos: { x: 24, y: 560 }, text: "space scores, esc quits", size: 16, color: Color.gray })
	Ok({})
}
