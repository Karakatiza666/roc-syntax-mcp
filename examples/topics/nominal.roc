# Nominal types are *distinct* from their underlying representation —
# two nominal types with the same shape are not interchangeable.
# Declared with `:=` (note the colon), often with a methods block.

# A nominal tag union with a custom `is_eq` method.
# Defining `is_eq` lets the type be compared with `==`.
Animal := [Dog(Str), Cat(Str)].{
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
# This is why you write `Bool.True` and `Bool.False` (not `True`/`False` directly).
