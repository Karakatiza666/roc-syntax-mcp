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

# `..rest` in a record pattern binds every field you did not name as a new
# record, so it is also a way to remove a field.
remove_field : { name : Str, age : I64, email : Str } -> { name : Str, age : I64 }
remove_field = |p| {
	{ email: _, ..rest } = p
	rest
}

# Records compose with type annotations. Inline record type:
distance : { x : F64, y : F64 } -> F64
distance = |p| (p.x * p.x + p.y * p.y).sqrt()

# A record type field can carry a default (`port : U16 ?? 8080`) or be optional
# (`timeout_ms ?: U64`), which changes how you read it. See the `record_fields`
# topic.
#
# Field names are a compile-time concept: field access is a fixed offset, not a
# lookup, and the names are not stored at runtime. The compiler decides whether
# a record is on the stack or the heap.
# A record's set of fields is fixed at compile time. Use a `Dict` when the keys
# vary at runtime.
