## The shape of a Joy app: the four functions the platform requires, the flags
## string `init` receives, effects returned as data, callbacks written as
## lambdas, a component with its own `Msg`, and a test of what `update` returns.
##
## Every entry point is pure. `init` and `update` return the new model beside a
## list of `Effect` values, which the host runs and answers with a message.
app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.35.0/FtRCTy7CSPSdS2vLzGJPwYfcGurQfoaADXPNT8aJBBCr.tar.zst",
	# The app pins joy-html itself, at exactly the release the platform pins.
	# `view` returns the platform's `Html`. Another joy-html release has a
	# different `Html` type, and the compiler error cannot name the difference.
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
}

# `exposing [Html]` is an error, "redundant expose": a type module exposes its
# own type. Only the functions go in the list.
import html.Html exposing [div, button, text]
import html.Attribute exposing [on_click]
# The annotations below need this import. `Effect(Msg)` names the type, so you
# must import the module even if you call none of its functions.
import pf.Effect
import pf.Sub
import pf.Console
import pf.Time

# --- A component -------------------------------------------------------------
#
# Its own model, messages, update and view. The parent wraps its messages in a
# tag and maps both directions: `Html.map` for the view, `Effect.map_all` for
# what its update returns.
#
# The methods are not named `init`, `update` and `view`. A method in a type's
# block that has the name of a top-level definition is a "duplicate
# definition" warning, and the app's own `init`, `update` and `view` are
# top-level.

Counter := { n : I64 }.{
	Msg : [Inc, Ticked(I64)]

	# A nominal type has no `==` until it opts in to the derived one. The test
	# at the bottom needs `==`.
	is_eq : _

	start : Counter
	start = { n: 0 }

	step : Counter, Msg -> (Counter, List(Effect(Msg)))
	step = |c, msg|
		match msg {
			# Timer delays are U32 milliseconds. The callback gets I64
			# milliseconds since the Unix epoch.
			Inc => ({ n: c.n + 1 }, [Time.after(100, |now| Ticked(now))])
			Ticked(_) => (c, [])
		}

	to_html : Counter -> Html(Msg)
	to_html = |c| div([], [button([on_click(Inc)], [text("+")]), text(c.n.to_str())])
}

# --- The four required functions --------------------------------------------
#
# The platform requires a type named `Model` and one named `Msg`, even when an
# app sends no message. Listing them in the header is optional. Defining them
# under exactly these names is required.

Model : { left : Counter, right : Counter, booted : Str }

Msg : [Left(Counter.Msg), Right(Counter.Msg), Reset]

# Always takes the flags string, even when the app ignores it. There is no
# clock to read and no URL to ask for: the page that embeds the app puts boot
# data into the flags.
init : Str -> (Model, List(Effect(Msg)))
init = |flags| ({ left: Counter.start, right: Counter.start, booted: flags }, [Console.log("booted")])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		# A tag is not a function, so `Effect.map_all(effects, Left)` does not
		# compile. Every callback this platform takes is written as a lambda.
		Left(m) => {
			(left, effects) = Counter.step(model.left, m)
			({ ..model, left }, Effect.map_all(effects, |x| Left(x)))
		}
		Right(m) => {
			(right, effects) = Counter.step(model.right, m)
			({ ..model, right }, Effect.map_all(effects, |x| Right(x)))
		}
		Reset => {
			# `dbg` as a statement goes to the browser console. As an
			# expression, `x = dbg value`, it compiles and binds `{}`.
			dbg model.left
			({ ..model, left: Counter.start, right: Counter.start }, [])
		}
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			Html.map(Counter.to_html(model.left), |m| Left(m)),
			Html.map(Counter.to_html(model.right), |m| Right(m)),
			# `on_click` takes the message itself, not a function that returns one.
			button([on_click(Reset)], [text("reset")]),
		],
	)

# Required even when there is nothing to subscribe to.
subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| []

# --- Testing update ----------------------------------------------------------
#
# An effect is data that the app can match on, so a pure test can
# assert exactly what an update asked the host to do. `roc test` runs these,
# and the platform's own expects beside them.

expect {
	(_, effects) = init("")
	match effects {
		[ConsoleLog(line)] => line == "booted"
		_ => Bool.False
	}
}

expect {
	(model, _) = init("")
	(next, effects) = update(model, Left(Inc))
	next.left == { n: 1 } and effects.len() == 1
}
