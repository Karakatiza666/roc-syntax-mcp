# joy-html

`niclas-ahden/joy-html`: an HTML tree typed by its message, `Html(msg)`, and the
attributes and events on it. It is what a Joy app's `render` returns, and any
platform can render it to a string for the server. Three modules: `Html` for
elements, `Attribute` for attributes and events, and `Event`, a small subset of
the events.

```roc
import html.Html exposing [div, button, text]
import html.Attribute exposing [on_click]
```

`html.Attributes` and `html.Events` give "package module is private". The names
are singular. `exposing [Html]` is an error, "redundant expose", because the
module already exposes its own type.

| Shape | Is |
|---|---|
| An element | `div(attrs, children)`. `Html.element("output", attrs, children)` for a tag with no helper |
| A void element | One argument: `input([...])`, `img`, `br`, `hr`, `meta`, `link`, `source` |
| Text | `text(s)`. Always escaped. There is no function for raw markup |
| `style` | Pairs, `style([("margin", "0")])`, not a CSS string |
| Classes | `class("a b")`, `classes(["a", "b"])`, or `class_list([("done", todo.done)])` to switch each one with a Bool |
| Boolean attributes | `Bool`: `disabled(model.busy)`, `checked(on)`. `width`, `height`, `rows` are `U64` |
| `for` | `for_`, because `for` is a keyword. `type` is fine |
| A list | `Html.keyed(id, child)` on each child, not on the list |

## Events

`on_click(msg)` and `on_submit(msg)` take the message. `on_submit` also stops
the browser's own submit. The rest take a lambda: `on_input(|s| Typed(s))`,
`on_check(|on| Toggle(on))`, `on_keydown`, the `on_pointer_*` family,
`on_file`, and `on_visible(msg, { root_margin, rearm_key })` for infinite
scroll. `on("dblclick", msg)` sends a message for any DOM event with no helper.
`on_key("keydown", ["Enter", "Escape"], |e| ...)` fires only for the keys
listed, and an empty list means every key. `.stop_propagation()` and
`.prevent_default()` are methods on any event attribute:
`on_click(Remove(id)).stop_propagation()`. On `on_key` with a key list,
`.prevent_default()` stops only those keys, and the browser keeps Tab.

An element keeps one handler per event, so `on_check` and `on_change` on one
checkbox both bind `change` and the last one wins. When a render hides a
focused input, `blur` arrives after the message that hid it. So a commit on
`blur` must do nothing when the edit already ended: the `todomvc` example
checks its `Editing` state.

Two modules cannot both expose the same name. `style` is both the
`<style>` element and the attribute, and `on_click` is in both `Attribute` and
`Event`, so expose each from one module and qualify the other. `Event` has only
click, input, change, check and touch. `on_submit` and `on_keydown` are only in
`Attribute`.

## Skipping work

`Html.lazy(view, arg)` keeps the previous subtree while its arguments are
equal, up to `lazy8`. The view has to be a named function: a lambda written at
the call site is a new value each time and never skips. So is a list or string
built during the render, but a `Bool` or number is compared by value. Pass a row
only what it reads: `Html.keyed(id, Html.lazy2(row_view, row, selected == row.id))`
re-renders two rows when the selection moves. `keyed` does not force the lazy
region. `Html.map` over a lazy region defeats it, so build the parent's message
inside the view instead.

## Server rendering

`Html.render : Html(msg) -> Str`, and `Html.ssr_document`, which adds
`<!DOCTYPE html>`. Text and attributes are escaped and event handlers dropped.
basic-webserver has an `Html` module of its own, and importing both unaliased
lets the platform's win, so `Html.ssr_document` "does not exist": alias it,
`import pf.Html as WsHtml`. `html_ssr` shows the whole server.

Worked programs: `html_views` for views, `html_ssr` for the server, and the
`joy_*` topics for apps.
