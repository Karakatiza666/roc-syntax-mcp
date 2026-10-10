# Static dispatch (`.method()`) and the pipe operator (`|>`).
#
# Roc has both, and each has its own use:
#   `.method()` calls a function defined on the receiver's type.
#   `|>` passes a value as the first argument to any function in scope.

# `.method()` is static dispatch. Because the type checker knows `"One"` is a
# `Str`, `"One".concat(...)` resolves at compile time to `Str.concat("One", ...)`.
# There is no runtime lookup and no vtable.
example1 = "One".concat(" Two")

# So `value.method(a)` is `Type.method(value, a)`, where `Type` is the type of
# `value`. A method that the type does not have is a compile-time error.
expect "One".concat(" Two") == Str.concat("One", " Two")

# `|>` (the pizza operator) is for functions that are not methods of the
# receiver's type. `x |> f(y)` calls `f(x, y)`, and `x |> f` calls `f(x)`.
# Write a function name after `|>`, such as `parse` or `List.map`.
my_concat = Str.concat

example2 = "Three" |> my_concat(" Four")

# Both forms mix in one chain. Here `.map` is a `List` method, but the list of
# strings must then be joined, and `join_with` lives on `Str`, not `List`:
#   Str.join_with : List(Str), Str -> Str
# Its receiver is the `List(Str)`, yet it is a `Str` method, so `.join_with()`
# on a `List` receiver would not resolve. `|>` connects the two parts.
label_names : Str -> Str
label_names = |joined| if joined.is_empty() "No names provided" else "Names: ${joined}"

format_names : List(Str) -> Str
format_names = |names|
	names
		.map(|name| name.trim())
		|> Str.join_with(", ")
		|> label_names

# Methods are declared in the `.{ }` block after a nominal or opaque type
# declaration, then dispatched with `.method()` once a value has that type.
Counter := { value : I64 }.{
	new : () -> Counter
	new = || { value: 0 }

	increment : Counter -> Counter
	increment = |{ value }| { value: value + 1 }
}

example3 : Counter
example3 = Counter.new().increment()

# @rejects missing method
# example4 = Counter.new().decrement()

# Well-known methods opt a type into language syntax through ordinary static
# dispatch. Each use resolves to one concrete implementation at compile time,
# so no dispatch happens at runtime.
#
#   to_inspect         Str.inspect(value) and `dbg`
#   is_eq              `==` and `!=`
#   to_hash            Dict, Set, and other hash-based APIs
#   plus minus times   `+` `-` `*`
#   div_by             `/`
#   div_trunc_by       `//`
#   rem_by             `%`
#   is_lt is_lte       `<` `<=`
#   is_gt is_gte       `>` `>=`
#   range_exclusive_to `..<`
#   range_inclusive_to `..=`
#   negate not         unary `-` and unary `!`
#   from_numeral       a number literal typed as this type
#   from_quote         a quoted string literal typed as this type
#   from_interpolation an interpolated string literal typed as this type
#   iter               `for item in value`
#   parser_for         generic parsers, such as JSON
#   encoder_for        generic encoders, such as JSON
#
# See the `derived_methods` topic for the `method : _` opt-in form, and the
# `operators` topic for the full operator-to-method table.

# A `where` clause lets a function require a method by name, so a package can
# define and require its own method names rather than only the well-known ones.
stringify : a -> Str where [a.to_str : a -> Str]
stringify = |value| value.to_str()

# The `types` topic has the `where` rules, `where` aliases, and `Thing : thing`
# for a method that takes no value of the type.

# `->fn(arg)` also parses and canonicalizes, but upstream does not document it
# and does not use it anywhere in its own reference code. Prefer `|>`.
