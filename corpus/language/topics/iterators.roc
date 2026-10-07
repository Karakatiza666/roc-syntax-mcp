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

# `size_hint` reports a length when one is known without walking the iterator.
#   Iter.size_hint : Iter(item) -> [Known(U64), Unknown]

# `Iter.custom` is the general unfold. It takes a seed, a length hint, and a
# step function mapping the seed to the next item plus the next seed, or
# `NoMore`. The seed type stays hidden inside the step closure.
#   Iter.custom : state, [Known(U64), Unknown],
#                 (state -> Try((item, state), [NoMore])) -> Iter(item)
countdown : U64 -> Iter(U64)
countdown = |from|
	Iter.custom(from, Known(from), |n| if n == 0 Err(NoMore) else Ok((n, n - 1)))

# A user-defined collection opts into `for ... in` by returning an `Iter` built
# from the APIs above.
Rows := { items : List(I64) }.{
	iter : Rows -> Iter(I64)
	iter = |rows| rows.items.iter()
}

# `Stream(item)` is the effectful counterpart. Its step is a `=>` function, so
# advancing it can perform effects.
#   Stream.from_iter : Iter(item) -> Stream(item)
#   Stream.map       : Stream(a), (a => b) -> Stream(b)
#   Stream.map!      : Stream(a), (a => b) => Stream(b)
#   Stream.next!     : Stream(item) => [One({ item, rest }), Skip({ rest }), Done]
#   Stream.collect!  : Stream(item) => List(item)
#   Stream.size_hint : Stream(item) -> [Known(U64), Unknown]
#
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

# `Stream(item)` is the effectful twin: each item comes from running an effect,
# like reading a line. Loop over one with `for!`, which calls `stream` on the
# value, so it also takes an `Iter`. A plain `for` over a `Stream` is a
# "missing method" error. `for!` only works inside an effectful function.
print_all! : Stream(Str) => {}
print_all! = |lines| {
	for! line in lines {
		echo!(line)
	}
}
