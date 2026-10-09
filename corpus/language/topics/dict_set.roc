# `Dict(k, v)` and `Set(a)`: create, look up, update, remove, iteration order,
# and the methods a key type needs.
#
# There is no literal syntax for either. Build them with functions:
#   Dict.empty     : () -> Dict(k, v)
#   Dict.single    : k, v -> Dict(k, v)
#   Dict.from_list : List((k, v)) -> Dict(k, v)
#   Set.empty, Set.single, Set.from_list
#   collect() or from_iter() from an `Iter` (see the `iterators` topic)
ages : Dict(Str, U64)
ages = Dict.from_list([("Sam", 30), ("Alex", 25)])

# A dict is immutable: `insert` and `remove` return a new dict. When nothing
# else refers to the old dict, Roc updates it in place, so this is fast.
# `insert` on a key that is already there replaces its value.
expect ages.insert("Jo", 41).len() == 3
expect ages.insert("Sam", 31).get("Sam") == Ok(31)

# `get` returns a `Try`, so pair it with `??` for a default. `contains` checks
# for a key without its value.
#   Dict.get : Dict(k, v), k -> Try(v, [KeyNotFound])
expect ages.get("Sam") ?? 0 == 30
expect ages.get("Kim") == Err(KeyNotFound)
expect ages.contains("Alex")

# `update` changes a value from its current state. The callback gets `Ok(v)` or
# `Err(Missing)`. It returns `Ok(new)` to store a value, or `Err(Missing)` to
# remove the key.
#   Dict.update : Dict(k, v), k, (Try(v, [Missing]) -> Try(v, [Missing])) -> Dict(k, v)
count_words : List(Str) -> Dict(Str, U64)
count_words = |words| {
	var $counts = Dict.empty()

	for word in words {
		$counts = $counts.update(word, |existing| match existing {
			Ok(count) => Ok(count + 1)
			Err(Missing) => Ok(1)
		})
	}

	$counts
}

expect count_words(["a", "b", "a"]) == Dict.from_list([("a", 2), ("b", 1)])
expect ages.update("Sam", |_| Err(Missing)).keys() == ["Alex"]

# Iteration follows insertion order and yields `(key, value)` tuples, so a
# `for` pattern can destructure them. `to_list`, `keys` and `values` use the
# same order. `iter_rev` walks it backwards.
names : Dict(Str, U64) -> List(Str)
names = |dict| {
	var $out = []

	for (name, _age) in dict {
		$out = $out.append(name)
	}

	$out
}

expect names(ages) == ["Sam", "Alex"]

# A replaced value keeps its position. `remove` moves the last key into the
# hole, so after a removal the order is no longer pure insertion order. This
# makes removal fast, because no other entry moves.
expect ages.insert("Sam", 31).keys() == ["Sam", "Alex"]
expect Dict.from_list([("a", 1), ("b", 2), ("c", 3), ("d", 4)]).remove("b").keys() == ["a", "d", "c"]

# `==` on dicts and sets ignores the order.
expect Dict.from_list([("a", 1), ("b", 2)]) == Dict.from_list([("b", 2), ("a", 1)])

# `Set(a)` is a `Dict(a, {})`, and `{}` uses no memory. A set keeps each value
# once and follows the same order rules as a dict.
primes : Set(U64)
primes = Set.from_list([2, 3, 5, 7, 7, 7])

expect primes.len() == 4
expect primes.contains(5)
expect Set.from_list([1, 2]).union(Set.from_list([2, 3])).to_list() == [1, 2, 3]
expect Set.from_list([1, 2]).intersection(Set.from_list([2, 3])).to_list() == [2]
expect Set.from_list([1, 2]).difference(Set.from_list([2, 3])).to_list() == [1]

# Keys and set values need `is_eq` and `to_hash`. Numbers, `Str`, and records,
# tuples, tag unions and lists of such types have both. A nominal type opts in
# with `is_eq : _` and `to_hash : _`, or writes them (see the `hashing` topic).
expect Dict.single({ x: 0, y: 0 }, "origin").get({ x: 0, y: 0 }) == Ok("origin")

# A function has no equality, so it cannot be a key.
# @rejects type does not support equality
# handlers = Dict.single(|n| n + 1, "inc")
