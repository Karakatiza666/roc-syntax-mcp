## The shape of a Joy app: the four functions the platform requires, the flags
## string `init` receives, effects returned as data, callbacks written as
## lambdas, a component with its own `Msg`, and a test of what `update` returns.
##
## Every entry point is pure. `init` and `update` return the new model beside a
## list of `Effect` values, which the host runs and answers with a message.
app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.34.0/2B3sC6U2dWkVUK2VY2gJS5Wej9YCDo3ZYq2e7tMWUCNp.tar.zst",
	# The app pins joy-html itself, at exactly the release the platform pins.
	# `render` returns the platform's `Html`. Another joy-html release has a
	# different `Html` type, and the compiler error cannot name the difference.
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
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
# tag and maps both directions: `Html.map` for the view, `Effect.map` for what
# its update returns.

Counter := { n : I64 }.{
	Msg : [Inc, Ticked(I64)]

	# A nominal type has no `==` until it opts in to the derived one. The test
	# at the bottom needs `==`.
	is_eq : _

	init : Counter
	init = { n: 0 }

	update : Counter, Msg -> (Counter, List(Effect(Msg)))
	update = |c, msg|
		match msg {
			# Timer delays are U32 milliseconds. The callback gets I64
			# milliseconds since the Unix epoch.
			Inc => ({ n: c.n + 1 }, [Time.after(100, |now| Ticked(now))])
			Ticked(_) => (c, [])
		}

	view : Counter -> Html(Msg)
	view = |c| div([], [button([on_click(Inc)], [text("+")]), text(c.n.to_str())])
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
init = |flags| ({ left: Counter.init, right: Counter.init, booted: flags }, [Console.log("booted")])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		# A tag is not a function, so `effect.map(Left)` does not compile.
		# Every callback this platform takes is written as a lambda.
		Left(m) => {
			(left, effects) = Counter.update(model.left, m)
			({ ..model, left }, effects.map(|e| e.map(|x| Left(x))))
		}
		Right(m) => {
			(right, effects) = Counter.update(model.right, m)
			({ ..model, right }, effects.map(|e| e.map(|x| Right(x))))
		}
		Reset => {
			# `dbg` as a statement goes to the browser console. As an
			# expression, `x = dbg value`, it compiles and binds `{}`.
			dbg model.left
			({ ..model, left: Counter.init, right: Counter.init }, [])
		}
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			Html.map(Counter.view(model.left), |m| Left(m)),
			Html.map(Counter.view(model.right), |m| Right(m)),
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
