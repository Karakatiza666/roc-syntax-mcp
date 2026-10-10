# `Iter` (pure) and `Stream` (effectful), and how `for ... in` uses them.
#
# `Iter(item)` is the pure iterator every `for` loop runs on. A type opts into
# `for ... in` by defining an `iter` method:
#
#   iter : T -> Iter(item)
#
# The loop calls `iter` on the value after `in`, then repeatedly calls `next`:
#
#   Iter.next : Iter(item) -> [One({ item : item, rest : Iter(item) }),
#                             Skip({ rest : Iter(item) }),
#                             Done]
#
# `Skip` lets an adapter such as `keep_if` discard an element without yielding.

# Builtin collections already provide `iter` and `iter_rev`, so a `for` loop
# over a list needs nothing extra.
sum_list : List(I64) -> I64
sum_list = |items| {
	var $total = 0

	for n in items {
		$total = $total + n
	}

	$total
}

# `iter_rev` reads a list backwards in place. Unlike `List.rev` it does not
# build a reversed copy first. `Dict` and `Set` also provide `iter_rev`, which
# walks their current iteration order backwards.
reversed : List(I64) -> List(I64)
reversed = |items| {
	var $visited = []

	for n in items.iter_rev() {
		$visited = $visited.append(n)
	}

	$visited
}

# To reverse values coming from some other iterator source, collect them into a
# list first with `List.from_iter`, then call `iter_rev` on that list.

# The adapters are ordinary methods on `Iter`, so they chain by static dispatch:
#   Iter.map      : Iter(a), (a -> b) -> Iter(b)
#   Iter.keep_if  : Iter(a), (a -> Bool) -> Iter(a)
#   Iter.drop_if  : Iter(a), (a -> Bool) -> Iter(a)
#   Iter.fold     : Iter(a), acc, (acc, a -> acc) -> acc
#   Iter.step_by  : Iter(item), U64 -> Iter(item)
#   Iter.take_first, Iter.drop_first : Iter(item), U64 -> Iter(item)
#   Iter.with_index : Iter(a) -> Iter((U64, a))   the index comes first
#   Iter.collect  : Iter(item) -> output
even_doubles : List(I64) -> List(I64)
even_doubles = |items|
	items
		.iter()
		.keep_if(|n| n % 2 == 0)
		.map(|n| n * 2)
		.collect()

# Reducers: `sum` returns the item type directly, but the others return a
# `Try` because an empty iterator has no answer.
#   Iter.sum     : Iter(item) -> item
#   Iter.product : Iter(item) -> Try(item, [IterWasEmpty])
#   Iter.min     : Iter(item) -> Try(item, [IterWasEmpty])
#   Iter.max     : Iter(item) -> Try(item, [IterWasEmpty])
largest : List(I64) -> I64
largest = |items| items.iter().max() ?? 0

expect (1..=100).iter().sum() == 5050

# `collect` builds any type that has `from_iter`, such as `List`, `Set` or
# `Dict`. Type inference picks the target. `List.from_iter(it)` names it.
unique : Set(U64)
unique = [3, 1, 3].iter().collect()

expect unique == Set.from_list([1, 3])

# An `Iter` is lazy. `map` runs only for the items that something pulls, each
# item goes through the whole chain before the next one, and only `collect`
# builds a collection. So an iterator can be infinite if its consumer stops.
expect (0..<1_000_000).iter().map(|n| n * 2).take_first(2).collect() == [0, 2]

powers_of_two : Iter(U64)
powers_of_two = Iter.custom(1, Unknown, |n| Ok((n, n * 2)))

expect powers_of_two.take_first(5).collect() == [1, 2, 4, 8, 16]

# `size_hint` reports a length when one is known without walking the iterator.
#   Iter.size_hint : Iter(item) -> [Known(U64), Unknown]
# `collect` allocates a list of the `Known` length once, so give `Known(n)` only
# when the iterator yields exactly n items.

# `Iter.custom` is the general unfold. It takes a seed, a length hint, and a
# step function mapping the seed to the next item plus the next seed, or
# `NoMore`. The seed type stays hidden inside the step closure.
#   Iter.custom : state, [Known(U64), Unknown],
#                 (state -> Try((item, state), [NoMore])) -> Iter(item)
countdown : U64 -> Iter(U64)
countdown = |from|
	Iter.custom(from, Known(from), |n| if n == 0 Err(NoMore) else Ok((n, n - 1)))

# An iterator is a value. `next` does not change it, and returns `rest` to
# continue with.
first_item : Iter(U64) -> U64
first_item = |iterator| match iterator.next() {
	One({ item, rest: _ }) => item
	Skip(_) => 0
	Done => 0
}

expect {
	numbers = [7, 8].iter()
	first_item(numbers) == 7 and first_item(numbers) == 7
}

# A user-defined collection opts into `for ... in` by returning an `Iter` built
# from the APIs above.
Rows := { items : List(I64) }.{
	iter : Rows -> Iter(I64)
	iter = |rows| rows.items.iter()
}

# The functions passed to `Iter` methods are pure.
# @rejects type mismatch
# loud! : List(Str) => List(Str)
# loud! = |lines| lines.iter().map(|line| {
# 	echo!(line)
# 	line
# }).collect()
#
# `Stream(item)` is the effectful counterpart. Its step is a `=>` function, so
# advancing it can perform effects.
#   Stream.custom    : state, [Known(U64), Unknown],
#                      (state => Try((item, state), [NoMore])) -> Stream(item)
#   Stream.from_iter : Iter(item) -> Stream(item)
#   Stream.map       : Stream(a), (a => b) -> Stream(b)
#   Stream.map!      : Stream(a), (a => b) => Stream(b)
#   Stream.next!     : Stream(item) => [One({ item, rest }), Skip({ rest }), Done]
#   Stream.collect!  : Stream(item) => List(item)
#   Stream.fold!     : Stream(a), acc, (acc, a => acc) => acc
#   Stream.for_each! : Stream(a), (a => {}) => {}
#   Stream.size_hint : Stream(item) -> [Known(U64), Unknown]
#
# A stream is lazy too. `map`, `keep_if`, `drop_if`, `with_index`,
# `take_first` and `drop_first` pull nothing. A consumer (`for!`, `fold!`,
# `for_each!`, `collect!`) pulls the items and runs the effects, so it works
# only in an effectful function. Building a stream is pure.
ticks : U64 -> Stream(U64)
ticks = |count|
	Stream.custom(0, Known(count), |n| {
		echo!("tick ${n.to_str()}\n")
		if n < count Ok((n, n + 1)) else Err(NoMore)
	})

tick_total! : U64 => U64
tick_total! = |count| ticks(count).map(|n| n * 10).fold!(0, |sum, n| sum + n)

# `Iter.stream` lifts a pure iterator into a `Stream`. The lifted steps do no
# effect themselves, but the stream can then be combined with effectful
# operations, and it carries the source's length forward so `collect!` can
# pre-size its result.
report_all! : List(Str) => List({})
report_all! = |lines|
	lines
		.iter()
		.stream()
		.map!(|line| echo!("${line}\n"))
		.collect!()

# Loop over a `Stream` with `for!`, which calls `stream` on the value, so it
# also takes an `Iter`. A plain `for` takes only an `Iter`, but its body can
# call effectful functions.
print_all! : Stream(Str) => {}
print_all! = |lines| {
	for! line in lines {
		echo!(line)
	}
}

# @rejects missing method
# print_plain! : Stream(Str) => {}
# print_plain! = |lines| {
# 	for line in lines {
# 		echo!(line)
# 	}
# }
#
# `for!` works only inside an effectful function.
# @rejects type mismatch
# print_pure : Stream(Str) -> {}
# print_pure = |lines| {
# 	for! line in lines {
# 		echo!(line)
# 	}
# }

