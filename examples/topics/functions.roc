# Function definitions in Roc.

# Anonymous function literal: `|args| body`. The body is a single expression
# — but a block `{ ... }` is itself an expression, so multi-statement bodies
# go inside curly braces.
identity = |x| x

square = |n| n * n

# Multi-argument:
add = |a, b| a + b

# Multi-statement body uses a block (the block's last expression is the return value).
describe = |n| {
	doubled = n * 2
	"n = ${n.to_str()}, doubled = ${doubled.to_str()}"
}

# `return` causes an early return from the enclosing function.
early_return = |arg| {
	first =
		if !arg {
			return 99
		} else {
			"continue"
		}

	# Do some other stuff
	Str.count_utf8_bytes(first)
}

# `...` is a placeholder for "implement me later". Calling the function crashes.
implement_me_later = |_str| ...

# You can bind a top-level constant to an existing function — first-class values.
my_concat = Str.concat
