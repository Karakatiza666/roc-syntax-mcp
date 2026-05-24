# Effectful functions in Roc.
#
# Convention: any function whose name ends with `!` may perform side effects.
# Its type signature uses `=>` (thick arrow) instead of `->` (thin arrow).
# Pure functions never call effectful functions.

# An effectful function from the platform / standard library.
# In the new compiler, `echo!` is available without an `import`.
effect_demo! : Str => {}
effect_demo! = |msg|
	echo!(msg)

# Effectful functions can only be called from effectful contexts.
# This is enforced by the type system — you can't sneak side effects into a pure function.

print! = |something| {
	echo!(Str.inspect(something))
}

# Effectful pipelines compose with regular pipelines — but the resulting
# function must be effectful (named with `!` and using `=>`).
log_each! : List(Str) => {}
log_each! = |items| {
	for item in items {
		echo!(item)
	}
	{}
}
