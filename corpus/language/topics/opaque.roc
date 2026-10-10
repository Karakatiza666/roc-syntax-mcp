# An opaque type is a nominal type whose backing type is hidden outside its
# defining module, so it can only be created and inspected through the methods
# that module exposes.
#
# Declared with `::` rather than `:=`. Inside the defining module the backing
# type is still accessible, so the methods block is the public API.

# Opaque type with methods.
# Useful when you want to hide fields so callers can't depend on internals.
Secret :: {
	key : Str,
}.{
	new : Str -> Secret
	new = |k| { key: k }

	unlock : Secret, Str -> Str
	unlock = |secret, password| {
		if password == "open sesame" {
			"The secret key is: ${secret.key}"
		} else {
			"Wrong password!"
		}
	}
}

# Usage:
#   secret = Secret.new("my_secret_key")    # call the type's `new` method
#   secret.unlock("open sesame")            # static dispatch to `unlock`

# An opaque tag union hides its tags in the same way.
Level :: [Low, Medium, High].{
	low : Level
	low = Low

	is_high : Level -> Bool
	is_high = |level| match level {
		High => True
		_ => False
	}
}

# In another module, these uses of `Level` and `Secret` fail to compile:
#   `Level.High`, `Secret.{ key: "k" }`   cannot use opaque nominal type
#   a `Level.High =>` match branch        cannot use opaque nominal type
#   a `High =>` branch on a `Level`       type mismatch
#   `x : Level` then `x = High`           type mismatch
#   `x : Secret` then `x = { key: "k" }`  type mismatch
#   `secret.key`                          type mismatch
# A bare tag or record literal does not lift into an opaque type there. So the
# defining module can add, rename or remove tags and fields, and other modules
# still compile. They call `Level.low` and `level.is_high()`.

# A bare opaque alias (no methods block) is also valid:
# Username :: Str
