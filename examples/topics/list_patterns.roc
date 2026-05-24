# List destructuring and pattern matching.

match_list_patterns : List(U64) -> U64
match_list_patterns = |lst| {
	match lst {
		[] => 0                          # empty list
		[x] => x                         # exactly one element
		[1, 2, 3] => 6                   # exact match
		[1, 2, ..] => 66                 # starts with 1, 2
		[2, .., 1] => 88                 # starts with 2 and ends with 1
		[1, .. as tail] => 77 + tail.len()  # bind the rest with `as`
		[_head, 5] => 55                 # ignore the head, match second
		[99, x] if x < 4 => 99 + x       # match guards with `if`

		# Note: avoid overusing `_` in a match branch; prefer explicit cases.
		_ => 100
	}
}

# Nested list patterns:
# match list_of_lists {
#     [first_list, ["bird", ..], ..] => ...
# }
