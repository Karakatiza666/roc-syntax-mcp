# Records are heterogeneous, named-field structures.

# Record literal.
person = { name: "Alice", age: 30 }

# Field access with `.field`.
greeting = "Hi, ${person.name}!"

# Destructuring brings fields into scope as constants.
destructuring = || {
	rec = { x: 1, y: "two" }
	{ x, y } = rec

	(x, y)
}

# Record update: `{ ..base, field: new }` creates a new record from `base`.
record_update : { name : Str, age : I64 } -> { name : Str, age : I64 }
record_update = |p| {
	{ ..p, age: 31 }
}

# Records compose with type annotations. Inline record type:
distance : { x : F64, y : F64 } -> F64
distance = |p| (p.x * p.x + p.y * p.y).sqrt()
