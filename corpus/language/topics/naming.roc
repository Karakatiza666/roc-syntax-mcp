# Naming rules, definition order, unused names, shadowing, and `var` rules.
#
# Names use only ASCII letters, digits and `_`. Type and tag names start with an
# uppercase letter. Other names start with a lowercase letter, or have one of
# these forms:
#   `_name`   a name that the code does not read
#   `$name`   a variable declared with `var`
#   `name!`   an effectful function
# Do not put `$` or `!` in a type, tag, type variable, record field or package
# shorthand name. The compiler does not reject all of these uses.
#
# @warns type variable starting with dollar
# same : $a -> $a
# same = |x| x

# Top-level definitions can come in any order. Inside a block, define a name
# before the code that uses it.
later = earlier + 1
earlier = 1

expect later == 2

# @rejects used before definition
# use_first = || {
# 	y = x + 1
# 	x = 1
# 	y
# }

# A function argument, block definition or pattern binding that the code never
# reads gives a warning. Unused top-level names give no warning.
#
# @warns unused variable
# total = |price, quantity| price * 2
#
# A `_` prefix marks a name as unused on purpose, and the name still documents
# the value. Code that reads a `_name` gives a warning. The `_` pattern binds
# nothing.
ignore_quantity = |price, _quantity| price * 2

# @warns underscore variable used
# double = |_n| _n * 2

# A name that is already in scope can be defined again. This shadowing is a
# warning, and the program still runs. The new value applies until the end of
# the scope. An argument that has the name of a top-level value also shadows it.
#
# @warns duplicate definition
# step = |x| {
# 	total = 0
# 	total = x + 1
# 	total
# }
#
# @warns duplicate definition
# bump = |later| later + 1
#
# A definition cannot read the name that it defines, even when an earlier
# definition has that name. Use a new name, or a `var`.
#
# @rejects invalid assignment to itself
# grow = |x| {
# 	size = 1
# 	size = size + x
# 	size
# }

# A plain definition is a constant. Only a `var` can change its value. The
# `loops` topic shows `var` with `for` and `while`. These rules apply to a `var`:
#   1. Declare it inside a function body or block, not at the top level.
#   2. Its name starts with `$`, which is part of the name: `$n` and `n` differ.
#   3. Only the function that declares it can reassign it. A nested lambda can
#      read it.
#   4. A lambda reads the value that the `var` had when the lambda was defined.
#   5. Each value that you assign to it must have the same type.
captured = || {
	var $n = 1
	read_n = || $n
	$n = 5
	(read_n(), $n)
}

expect captured() == (1, 5)

# @rejects var outside body
# var $top = 0
#
# @rejects var reassignment error
# count_calls = |items| {
# 	var $count = 0
# 	add_one = || {
# 		$count = $count + 1
# 	}
# 	add_one()
# 	items.len() + $count
# }
#
# @rejects polymorphic var
# reuse = || {
# 	$xs : List(a)
# 	var $xs = []
# 	$xs.len()
# }
#
# @warns var name missing `$`
# no_dollar = || {
# 	var count = 0
# 	count
# }
#
# @warns dollar prefix without `var`
# no_var = || {
# 	$total = 0
# 	$total
# }

# `as` in a pattern names the whole matched value next to the names inside it.
# Imports and list patterns also use `as`, as the `imports` and `list_patterns`
# topics show.
first_ok : Try(U64, Str) -> (U64, Try(U64, Str))
first_ok = |try| match try {
	Ok(n) as whole => (n, whole)
	Err(_) => (0, try)
}

expect first_ok(Ok(3)) == (3, Ok(3))
