# Function definitions in Roc.

# Anonymous function literal: `|args| body`. The body is a single expression,
# but a block `{ ... }` is itself an expression, so multi-statement bodies go
# inside curly braces.
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

	# The rest of the function.
	Str.count_utf8_bytes(first)
}

# `crash "msg"` aborts the program with a custom message when reached.
implement_me_later : Str -> Str
implement_me_later = |str| {
	if str == "" {
		str
	} else {
		crash "not implemented"
	}
}

# `...` is the placeholder for code not written yet. It desugars to
# `crash "not implemented"`.
todo_later = |_str| ...

# Functions are first-class values, so a top-level constant can name one.
my_concat = Str.concat
