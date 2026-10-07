# A nominal type is a distinct type with its own identity, so it is not
# interchangeable with its backing representation: `UserId := U64` makes
# `UserId` and `U64` different types even though they share a layout. Two
# nominal types with the same shape are likewise distinct.
#
# Declared with `:=`, often with a `.{ }` methods block. Contrast:
#   `:=`  nominal type, backing representation visible
#   `::`  opaque nominal type, backing hidden outside the defining module
#   `:`   type alias, transparent and interchangeable with its definition

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

# Bool itself is a nominal type defined in the builtins:
# Bool := [False, True].{ ... }
# `True`/`False` work wherever a `Bool` is expected. `Bool.True` is the
# qualified form.
