# For loops, while loops, break, and reassignable `var`s.
#
# A `var` is a *reassignable* binding. Its name MUST start with `$`,
# so any time you see `$name` you know it can be mutated.
# Constants (without `$`) can never be reassigned.

# `for` loop with a var accumulator.
for_loop = |num_list| {
	var $sum = 0

	for num in num_list {
		$sum = $sum + num
	}

	$sum
}

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

# Vars can only be reassigned in the function where they were declared.
# This means `for_each!(|x| { $count = $count + 1 })` is a compile error.
# Use a `for` loop instead when you need to mutate a var.
