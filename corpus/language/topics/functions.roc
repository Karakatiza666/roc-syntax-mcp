# Function definitions, blocks, and recursion in Roc.

# Roc has one syntax to define a function, the lambda `|args| body`. A named
# function is a constant whose value is a lambda. Roc has no `fn`, `\x ->` or
# `f x = ...` form.
identity = |x| x

add = |a, b| a + b

# `|| body` takes no arguments.
answer = || 42

# The body is one expression. A block `{ ... }` is an expression: zero or more
# statements, then a final expression that gives the value of the block. A name
# that a block defines is visible only inside that block.
describe = |n| {
	doubled = n * 2
	"n = ${n.to_str()}, doubled = ${doubled.to_str()}"
}

# `return` exits the enclosing function. A block can end in a statement such as
# `return`, with no final expression.
early_return = |arg| {
	first =
		if !arg {
			return 99
		} else {
			"continue"
		}

	Str.count_utf8_bytes(first)
}

# `...` is the placeholder for code not written yet. It desugars to
# `crash "not implemented"`.
todo_later = |_str| ...

# Functions are values. A constant that names a function stays generic,
# because copying a reference does no work.
same_len = List.len

expect same_len(["a"]) == 1 and same_len([1, 2]) == 2

# Recursion needs no keyword. Top-level definitions can be in any order, so two
# top-level functions can call each other.
is_even : U64 -> Bool
is_even = |n| if n == 0 True else is_odd(n - 1)

is_odd : U64 -> Bool
is_odd = |n| if n == 0 False else is_even(n - 1)

expect is_even(10) and is_odd(7)

# A top-level cycle is allowed only when every value in it is a function.
#
# @rejects circular value definition
# first_value = second_value + 1
# second_value = first_value + 1

# A recursive call that is not the last operation uses one stack frame per
# level, so a deep input can overflow the stack. `n * factorial(n - 1)` is one.
factorial : U64 -> U64
factorial = |n| if n <= 1 1 else n * factorial(n - 1)

# Pass an accumulator to make the call a self-tail call. When every self-call is
# a tail call, the compiler turns the function into a loop. The loop cannot
# overflow the stack, but it can run forever.
factorial_acc : U64, U64 -> U64
factorial_acc = |n, acc| if n <= 1 acc else factorial_acc(n - 1, n * acc)

expect factorial(5) == factorial_acc(5, 1)

# A self-call whose result goes directly into a tag of the function's own
# recursive return type also becomes a loop (tail recursion modulo cons). So
# `count_up` needs no accumulator, and `count_up(0, 1_000_000)` does not
# overflow the stack.
LinkedList(a) := [Nil, Cons(a, LinkedList(a))]

count_up : U64, U64 -> LinkedList(U64)
count_up = |current, end|
	if current >= end Nil else Cons(current, count_up(current + 1, end))

length : LinkedList(U64), U64 -> U64
length = |lst, acc| match lst {
	Nil => acc
	Cons(_, rest) => length(rest, acc + 1)
}

expect length(count_up(0, 10), 0) == 10
