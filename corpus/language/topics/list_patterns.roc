# Lists: literals, list patterns, indexes, and fast list updates.
#
# A `List` is an array, not a linked list. All its elements have the same type.
# To put different kinds of values in one list, use tags.
shapes = [Circle(1.5), Rectangle(2, 3)]

expect shapes.len() == 2

# A list is immutable. `append`, `set` and the other updates return a new list,
# so use the result. A statement that discards it is an error.
#
# @rejects type mismatch
# add_four : List(U64) -> List(U64)
# add_four = |list| {
# 	list.append(4)
# 	list
# }

# List destructuring and pattern matching.

match_list_patterns : List(U64) -> U64
match_list_patterns = |lst| {
	match lst {
		[] => 0 # empty list
		[x] => x # exactly one element
		[1, 2, 3] => 6 # exact match
		[1, 2, ..] => 66 # starts with 1, 2
		[2, .., 1] => 88 # starts with 2 and ends with 1
		[1, .. as tail] => 77 + tail.len() # bind the rest with `as`
		[_head, 5] => 55 # ignore the head, match second
		[99, x] if x < 4 => 99 + x # match guards with `if`

		# Do not use `_` branches too much. Prefer explicit cases.
		_ => 100
	}
}

# `..` matches zero or more elements, at the start, the middle or the end. Each
# name on either side is one element, so `[first, .., last]` needs at least two.
ends : List(U64) -> [Some((U64, U64)), None]
ends = |items| match items {
	[first, .., last] => Some((first, last))
	_ => None
}

expect ends([5]) == None

# A list pattern can contain `..` only once.
#
# @rejects invalid pattern
# two_rests : List(U64) -> U64
# two_rests = |lst| match lst {
# 	[a, .., b, ..] => a + b
# 	_ => 0
# }

# Nested list patterns:
# match list_of_lists {
#     [first_list, ["bird", ..], ..] => ...
# }

# Indexing outside a pattern goes through methods that return a `Try`, so an
# out-of-range index is a value you handle rather than a crash:
#   List.get       : List(item), U64 -> Try(item, [OutOfBounds])
#   List.subscript : List(item), U64 -> Try(item, [OutOfBounds])
#   List.set       : List(a), U64, a -> Try(List(a), [OutOfBounds])
#
# `list[i]` is planned (it will desugar to `.subscript(i)`) but does not parse yet.
third_or_zero : List(I64) -> I64
third_or_zero = |items| items.subscript(2) ?? 0

# A grid of equal rows is faster as one flat list than as a `List(List(a))`,
# because each inner list is a separate allocation.
get_cell : List(U8), U64, U64, U64 -> Try(U8, [OutOfBounds])
get_cell = |grid, width, x, y| grid.get(y * width + x)

# Performance:
#   - `append` adds to the end in place when nothing else refers to the list.
#     The `loops` topic shows a loop that builds a list this way.
#   - When you know the final length, start with `List.with_capacity(n)` or call
#     `reserve`, so the list does not reallocate as it grows.
#   - `prepend` moves every element. To build a list in reverse, `append` each
#     element and reverse once at the end, or read it with `iter_rev`.
#   - `drop_first`, `take_first`, `sublist` and `.. as rest` copy no elements.
#     They return a slice, which keeps all of the original list in memory.
