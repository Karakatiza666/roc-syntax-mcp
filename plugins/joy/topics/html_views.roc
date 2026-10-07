## Writing views with joy-html: element and void-element shapes, typed
## attributes, events and their modifiers, keyed lists, `lazy` regions, and the
## import lists that collide.
app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.34.0/2B3sC6U2dWkVUK2VY2gJS5Wej9YCDo3ZYq2e7tMWUCNp.tar.zst",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

# Two modules cannot both expose the same name. `style` is the `<style>`
# element in Html and the attribute in Attribute, and `on_click` is in both
# Attribute and Event. Expose it from one and qualify the other. Event is a
# small subset of Attribute (click, input, change, check, touch). Everything
# else, including `on_submit` and `on_keydown`, is only in Attribute.
import html.Html exposing [div, form, label, input, button, ul, li, text]
import html.Attribute exposing [class_list, style, id, for_, type, value, checked, disabled, placeholder, on, on_click, on_input, on_check, on_key, on_submit]
import pf.Effect

Row : { id : Str, label : Str, done : Bool }

Model : { rows : List(Row), draft : Str, busy : Bool, selected : Str }

Msg : [Typed(Str), Add, Toggle(Str, Bool), Remove(Str), Select(Str), Nothing]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ rows: [], draft: "", busy: Bool.False, selected: "" }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Typed(s) => ({ ..model, draft: s }, [])
		Add => {
			row = { id: model.rows.len().to_str(), label: model.draft, done: Bool.False }
			({ ..model, rows: model.rows.append(row), draft: "" }, [])
		}
		Toggle(row_id, on) => ({ ..model, rows: model.rows.map(|r| if r.id == row_id { ..r, done: on } else r) }, [])
		Remove(row_id) => ({ ..model, rows: model.rows.keep_if(|r| r.id != row_id) }, [])
		Select(row_id) => ({ ..model, selected: row_id }, [])
		Nothing => (model, [])
	}

# A named function, so `Html.lazy2` can tell it is the same view as last time.
# A lambda written at the call site is a new value every render and never
# skips.
row_view : Row, Bool -> Html(Msg)
row_view = |r, is_selected|
	li(
		# Each class with the Bool that turns it on. `classes` takes a plain list.
		[class_list([("row", Bool.True), ("done", r.done), ("selected", is_selected)])],
		[
			# `for` is a keyword, so the attribute is `for_`. `type` is fine.
			# `on` sends a message for any DOM event that has no helper.
			label([for_("row-${r.id}"), on("dblclick", Select(r.id))], [text(r.label)]),
			# A void element takes one argument, its attributes: not `input([], [])`.
			# Boolean attributes take a Bool, not a string.
			input([type("checkbox"), id("row-${r.id}"), checked(r.done), on_check(|on| Toggle(r.id, on))]),
			# `on_click` takes the message itself. `stop_propagation` keeps the
			# click from reaching a handler on the row's ancestors.
			button([on_click(Remove(r.id)).stop_propagation()], [text("x")]),
		],
	)

render : Model -> Html(Msg)
render = |model|
	div(
		# `style` takes pairs, not a CSS string.
		[style([("max-width", "40rem"), ("margin", "0 auto")])],
		[
			# `on_submit` prevents the browser's own submit, so the page stays.
			form(
				[on_submit(Add)],
				[
					# A key list filters the event: only Escape sends the message, and
					# `.prevent_default()` would then suppress only Escape.
					input([value(model.draft), placeholder("New item"), on_input(|s| Typed(s)), on_key("keydown", ["Escape"], |_| Typed(""))]),
					button([type("submit"), disabled(model.busy or model.draft == "")], [text("Add")]),
				],
			),
			# `keyed` wraps each child, not the list: a row keeps its DOM node,
			# and its checkbox state, when rows above it are removed. Unkeyed
			# children are patched by position.
			# Pass a row only what it reads. The Bool is built here and still
			# skips, so a new selection re-renders two rows. A list or string
			# built here is a new value each render and never skips.
			ul([], model.rows.map(|r| Html.keyed(r.id, Html.lazy2(row_view, r, model.selected == r.id)))),
			# An element joy-html has no helper for.
			Html.element("output", [Attribute.attribute("aria-live", "polite")], [text("${model.rows.len().to_str()} items")]),
		],
	)

subscriptions = |_model| []
