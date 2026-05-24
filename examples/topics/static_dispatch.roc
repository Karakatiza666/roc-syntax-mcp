# Static dispatch and the `->` arrow application form.
#
# Roc no longer has the pizza operator `|>`. Instead it has two equivalent
# ways to chain: `.method()` for functions defined on the type, and
# `->fn(arg)` for any in-scope function.

# `.method()` — static dispatch.
# Because the type checker knows `"One"` is a `Str`, `"One".concat(...)` is
# rewritten at compile time to `Str.concat("One", ...)`.
example1 = "One".concat(" Two")

# `->fn(arg)` — arrow application. Useful when the function isn't a method
# of the receiver's type but you still want a left-to-right reading order.
my_concat = Str.concat
example2 = "Three"->my_concat(" Four")

# Method chains read naturally:
format_names : List(Str) -> Str
format_names = |names|
	names
		.map(|name| name.trim())
		.join_with(", ")
		->(|joined| {
			if joined.is_empty() "No names provided" else "Names: ${joined}"
		})

# Methods on a nominal/opaque type are dispatched via `.method()` once
# the value has the type. See the `nominal` and `opaque` topics.
