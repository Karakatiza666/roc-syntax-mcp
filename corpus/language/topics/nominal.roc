# A nominal type is a distinct type with its own identity, so it is not
# interchangeable with its backing type: `UserId := U64` makes `UserId` and
# `U64` different types even though they share a layout. Two nominal types with
# the same shape are likewise distinct. The layout is the same, so to wrap or
# unwrap a nominal value costs nothing at run time.
#
# Declared with `:=`, often with a `.{ }` methods block. Contrast:
#   `:=`  nominal type, backing type visible
#   `::`  opaque nominal type, backing type hidden outside the defining module
#   `:`   type alias, transparent and interchangeable with its definition
#
# @rejects type mismatch
# UserId := U64
# OrderId := U64
# to_order : UserId -> OrderId
# to_order = |id| id

# A nominal tag union with a custom `is_eq` method.
# Defining `is_eq` lets the type be compared with `==`.
Animal := [Dog(Str), Cat(Str)].{
	# In most cases, let the compiler derive it with `is_eq : _`.
	is_eq = |a, b| match (a, b) {
		(Dog(name1), Dog(name2)) => name1 == name2
		(Cat(name1), Cat(name2)) => name1 == name2
		_ => Bool.False
	}
}

# Usage:
#   dog : Animal
#   dog = Dog("Fido")
#   cat : Animal
#   cat = Cat("Whiskers")
#   dog == cat   # calls Animal.is_eq(dog, cat)

# Explicit construction names the type before the backing value:
#   `Distance.(26)`         any backing value
#   `Pair.(1, "two")`       tuple backing
#   `Point.{ x: 1, y: 2 }`  record backing
#   `Shape.Circle(2)`       tag backing, see the `tag_unions` topic
# The same forms destructure a nominal value in a pattern.
Distance := U64.{
	is_eq : _
}

Pair := (U64, Str)

# The methods block can also hold constants, such as `Point.origin`.
Point := { x : F64, y : F64 }.{
	origin : Point
	origin = { x: 0, y: 0 }
	is_eq : _
}

to_distance : U64 -> Distance
to_distance = |n| Distance.(n)

meters : Distance -> U64
meters = |Distance.(m)| m

pair_num : Pair -> U64
pair_num = |Pair.((n, _))| n

# A record pattern lists every field, or ends with `..` to ignore the others.
point_x : Point -> F64
point_x = |Point.{ x, .. }| x

expect meters(to_distance(5)) == 5
expect pair_num(Pair.(1, "two")) == 1
expect Point.origin == Point.{ x: 0, y: 0 }

# A record or tag literal becomes the nominal type where the code expects that
# type, as `origin` above shows. A number or string literal does not, unless the
# type defines `from_numeral` or `from_quote` (see `derived_methods`). A value
# that already has a concrete type, such as the `U64` argument of
# `to_distance`, also needs explicit construction.
#
# @rejects type mismatch
# zero : Distance
# zero = 0
#
# @rejects type mismatch
# to_distance_bare : U64 -> Distance
# to_distance_bare = |n| n

# Bool itself is a nominal type defined in the builtins:
# Bool := [False, True].{ ... }
# `True`/`False` work wherever a `Bool` is expected. `Bool.True` is the
# qualified form.
