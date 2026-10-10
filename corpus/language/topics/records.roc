# Records are heterogeneous, named-field structures.

# Record literal. A trailing comma makes `roc fmt` put each field on its own
# line.
person = { name: "Alice", age: 30 }

# Field access with `.field`.
greeting = "Hi, ${person.name}!"

# A field pun: `{ name, age }` means `{ name: name, age: age }`. A pun of one
# field needs a comma, because `{ name }` is a block that returns `name`.
make_person = |name, age| { name, age }
one_field = |name| { name, }
block_value = |name| { name }

expect make_person("Kim", 41) == { name: "Kim", age: 41 }
expect one_field("Kim") == { name: "Kim" }
expect block_value("Kim") == "Kim"

# Field order is not part of the type, so these aliases are one type.
PersonA : { name : Str, age : U64 }
PersonB : { age : U64, name : Str }

to_b : PersonA -> PersonB
to_b = |p| p

# `==` on two records compares every field, in any order. A nominal record has
# no `==` until it defines `is_eq` or derives it with `is_eq : _`.
expect { a: 1, b: "x" } == { b: "x", a: 1 }

# @rejects missing method
# Plain := { x : U64 }
# same = Plain.{ x: 1 } == Plain.{ x: 1 }

# Destructuring brings fields into scope as constants.
destructuring = || {
	rec = { x: 1, y: "two" }
	{ x, y } = rec

	(x, y)
}

# In a record pattern, `field: pattern` renames a field or matches its value.
# A pattern without `..` lists every field. `..` ignores the other fields. A
# one-field pattern is `{ name }`. Only the literal needs the comma.
User : { active : Bool, name : Str, age : U64 }

user_label : User -> Str
user_label = |user| match user {
	{ active: True, name: who, .. } => who
	{ name, .. } => "inactive ${name}"
}

expect user_label({ active: False, name: "Ari", age: 9 }) == "inactive Ari"

only_name : { name : Str } -> Str
only_name = |{ name }| name

# @rejects type mismatch
# name_only : User -> Str
# name_only = |{ name }| name

# Record update: `{ ..base, field: new }` creates a new record from `base`, and
# `base` does not change. An update only replaces fields that exist, with
# values of the same type. Build a new record to add a field or change a type.
record_update : { name : Str, age : I64 } -> { name : Str, age : I64 }
record_update = |p| {
	{ ..p, age: 31 }
}

# @rejects type mismatch
# add_field : { name : Str } -> { name : Str, extra : U64 }
# add_field = |p| { ..p, extra: 1 }
#
# @rejects type mismatch
# change_type : { age : U64 } -> { age : Str }
# change_type = |p| { ..p, age: "x" }

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

# An open record type ends in `..` and accepts records with more fields. It is
# compile-time polymorphism: every concrete record still has a fixed shape.
# `{}` is the closed empty record, with the one value `{}`. `{ .. }` accepts
# any record.
get_name : { name : Str, .. } -> Str
get_name = |record| record.name

expect get_name({ name: "Ari", age: 41 }) == "Ari"

# @rejects type mismatch
# takes_empty : {} -> U64
# takes_empty = |_| 1
# not_empty = takes_empty({ a: 1 })

# A record type field can carry a default (`port : U16 ?? 8080`) or be optional
# (`timeout_ms ?: U64`), which changes how you read it. See the `record_fields`
# topic.
#
# Field names are a compile-time concept: field access is a fixed offset, not a
# lookup, and the names are not stored at runtime. A record has no allocation and
# no reference count of its own. Its fields are stored inline, in a local on the
# stack or inside the value that holds the record. See the `memory` topic.
# A record's set of fields is fixed at compile time. Use a `Dict` when the keys
# vary at runtime.
