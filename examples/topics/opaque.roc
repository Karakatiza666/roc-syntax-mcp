# Opaque types hide their internal representation from users of the type.
# Declared with `::` (structural alias) — anyone in the same module can
# construct values, but the methods block is the public API.

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

# A bare opaque alias (no methods block) is also valid:
# Username :: Str
