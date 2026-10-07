Model : { count : I64 }

Msg : [Increment, Decrement]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ count: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Increment => ({ count: model.count + 1 }, [])
		Decrement => ({ count: model.count - 1 }, [])
	}

render : Model -> Html(Msg)
render = |model|
	Html.div(
		[Attribute.class("counter")],
		[
			Html.button([Attribute.on_click(Decrement)], [Html.text("-")]),
			Html.text(model.count.to_str()),
			Html.button([Attribute.on_click(Increment)], [Html.text("+")]),
		],
	)
