# The `?` postfix operator: early-return an `Err` from a `Try`.
# If the value is `Ok(x)`, the expression evaluates to `x`.
# If it's `Err(e)`, the surrounding function returns `Err(e)` immediately.

question_postfix : List(Str) -> Try(I64, _)
question_postfix = |strings| {
	first_str = strings.first()?
	first_num = I64.from_str(first_str)?

	Ok(first_num)
}

# `?` with spaces around it and a handler after it maps the err payload before
# early returning. Postfix `?` has no space before it.
# The RHS can be a bare tag (used as a constructor) or any function-like
# expression (e.g. a lambda). The err payload is passed as its argument.
question_with_err_map : List(Str) -> Try(Str, _)
question_with_err_map = |strings| {
	# `? NoFirstError` wraps the err as `NoFirstError(err)` before returning.
	first_str = strings.first() ? NoFirstError
	Ok(first_str)
}

question_with_err_lambda : List(Str) -> Try(Str, _)
question_with_err_lambda = |strings| {
	# Explicit lambda form.
	first_str = strings.first() ? |e| NoFirstError(e)
	Ok(first_str)
}

# Desugared, `x?` is:
#   match x {
#       Ok(v) => v
#       Err(e) => return Err(e)
#   }

# Method-chain alternatives
#
# `Try` has methods that transform the value inside without unwrapping it, so
# they compose with static dispatch and stay usable in expression position:
#
#   map_ok    : Try(a, err), (a -> b) -> Try(b, err)
#   map_err   : Try(ok, a), (a -> b) -> Try(ok, b)
#   map_both  : Try(a, b), (a -> c), (b -> d) -> Try(c, d)
#   map2      : Try(a, err), Try(b, err), (a, b -> c) -> Try(c, err)
#   on_err    : Try(ok, a), (a -> Try(ok, b)) -> Try(ok, b)
#   catch     : Try(ok, err), (err -> a), (ok -> a) -> a
#   collapse  : Try(a, a) -> a
#   ok_or     : Try(ok, _err), ok -> ok
#   err_or    : Try(_ok, err), err -> err
#   is_ok, is_err : Try(_ok, _err) -> Bool
#
# Each mapping method has an effectful twin taking a `=>` function and
# returning `=>`: `map_ok!`, `map_err!`, `map_both!`, `map2!`, `on_err!`,
# `catch!`.
#
# `on_err` recovers by returning another `Try`, so it chains fallbacks.
# `catch` handles both sides at once and returns a plain value, not a `Try`.
# `collapse` unwraps a `Try` whose ok and err types are the same.
chain_example : List(Str) -> Try(Str, [PathErr(Str)])
chain_example = |strings|
	strings
		.first()
		.map_err(|err| PathErr(Str.inspect(err)))
		.map_ok(|first| first.trim())

# Which one to use:
#   `?`             bubble the err to the caller by early return.
#   `? Tag`         bubble it wrapped in a tag.
#   `??`            do not bubble. Substitute a default here.
#   `.map_err(...)` bubble it transformed, staying inside an expression.
#   `.map_ok(...)`  transform the success value, keeping the err intact.
#   `.on_err(...)`  try a different way to produce an ok value.
#   `.catch(...)`   collapse both cases into one plain value.

# `??` is the counterpart to `?`. Where `?` propagates the err by early return,
# `??` handles it inline with a default and the function keeps going:
#
#   value = fallible ?? default
#
# desugars to `match fallible { Ok(v) => v, Err(_) => default }`.
parse_or_zero : Str -> I64
parse_or_zero = |text| I64.from_str(text) ?? 0

# With `?`, the caller decides. With `??`, the current function decides. See
# the `operators` topic.
