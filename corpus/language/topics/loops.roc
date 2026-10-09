# For loops, while loops, break, and reassignable `var`s.
#
# A `var` is a reassignable binding. Its name must start with `$`,
# so every `$name` is a binding that can change. A second `name = ...` in the
# same scope is a new constant that shadows the first, with a "duplicate
# definition" warning. See the `naming` topic.

# A `for` loop runs over an iterator. Anything with an `iter` method works,
# including lists, dicts, sets, and ranges. The loop body contains only
# statements, has no final expression, and the loop itself evaluates to `{}`.

# `for` loop with a var accumulator.
for_loop = |num_list| {
	var $sum = 0

	for num in num_list {
		$sum = $sum + num
	}

	$sum
}

# Ranges work directly: `1..<5` is exclusive, `1..=5` inclusive. See the
# `ranges` topic.
sum_range = |n| {
	var $sum = 0

	for i in 0..<n {
		$sum = $sum + i
	}

	$sum
}

# `iter_rev` walks a list backwards in place, without building a reversed copy
# the way `List.rev` does. Dicts and sets also provide `iter_rev`, which walks
# their current iteration order backwards. To reverse some other iterator
# source, collect it with `List.from_iter` first, then call `iter_rev`.
reverse_visit = |items| {
	var $visited = []

	for n in items.iter_rev() {
		$visited = $visited.append(n)
	}

	$visited
}

# Whatever sits between `for` and `in` is a pattern, so items destructure
# inline, and `_` discards.
sum_pairs = |pairs| {
	var $total = 0

	for (x, y) in pairs {
		$total = $total + x + y
	}

	$total
}

count_items = |items| {
	var $count = 0

	for _ in items {
		$count = $count + 1
	}

	$count
}

# The `for` pattern must be exhaustive, exactly like a destructuring
# assignment. `for Ok(n) in results { ... }` is not allowed, because the body
# would have no value for `n` if an item were `Err`. Name the whole item and
# `match` inside the body instead. For a tag pattern, this compiler crashes
# with "instantiation widened a closed tag union" and reports no error.
#
# @rejects non exhaustive destructure
# count_ones = |items| {
# 	var $count = 0
# 	for 1 in items {
# 		$count = $count + 1
# 	}
# 	$count
# }
# ones = count_ones([1.I64])

# `break` exits a `for` or `while` loop early.
break_in_for_loop = |bool_list| {
	var $all_true = Bool.True

	for b in bool_list {
		if b == Bool.False {
			$all_true = Bool.False
			break
		} else {
			{}
		}
	}

	$all_true
}

# `while` loop with a condition.
while_loop = |limit| {
	var $count = 0
	var $sum = 0

	while $count < limit {
		$sum = $sum + $count
		$count = $count + 1
	}

	$sum
}

# `break` exits only the innermost loop. In a nested loop, breaking out of the
# inner one leaves the outer one running.

# Roc has no `loop` keyword. Use `while True` when the exit check sits in the
# middle of the body, and leave with `break` or `return`. A loop that never
# ends during compile-time evaluation hangs the compiler.
first_power_over : U64 -> U64
first_power_over = |limit| {
	var $n = 1

	while True {
		$n = $n * 2
		if $n > limit {
			break
		}
	}

	$n
}

expect first_power_over(100) == 128

# `for!` loops over a `Stream` (see the `iterators` topic). Its pattern must be
# exhaustive too, and `break` and `return` work as in `for`.
first_over! : List(U64), U64 => Try(U64, [NotFound])
first_over! = |items, limit| {
	for! n in items.iter() {
		if n > limit {
			return Ok(n)
		}
	}

	Err(NotFound)
}

# Only the function that declares a var can reassign it, so a lambda passed to
# `for_each!` cannot change it. Use a `for` loop when you need to change a var
# for each item. The `naming` topic has the other `var` rules.
