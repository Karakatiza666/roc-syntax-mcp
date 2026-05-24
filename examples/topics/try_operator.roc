# The `?` postfix operator: early-return an `Err` from a `Try`.
# If the value is `Ok(x)`, the expression evaluates to `x`.
# If it's `Err(e)`, the surrounding function returns `Err(e)` immediately.

question_postfix : List(Str) -> Try(I64, _)
question_postfix = |strings| {
	first_str = strings.first()?
	first_num = I64.from_str(first_str)?

	Ok(first_num)
}

# `?` with a right-hand side maps the err payload before early returning.
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

# ─── Method-chain alternatives ───────────────────────────────────────────────
#
# `Try` has `.map_ok` and `.map_err` methods (see `lookup_builtin` /
# `get_builtin_module` with `Try`). They transform the value INSIDE the
# Try without unwrapping it, and compose nicely with static dispatch.
#
# Used heavily by basic-cli's Path.roc:
#
#   host_path_type!(to_bytes(path))
#       .map_err(|err| PathErr(err))
#       .map_ok(|t| if t.is_sym_link IsSymLink else if t.is_dir IsDir else IsFile)
#
# Equivalent to a `match` that maps each branch, but read-left-to-right.
#
# When to reach for which:
#   • `?`              — you want to BUBBLE the err to the caller.
#   • `? Tag`          — you want to bubble it WRAPPED in a tag.
#   • `.map_err(...)`  — you want to bubble it TRANSFORMED by a function and
#                        the surrounding code is already a chain (no early
#                        return). Stays an expression — usable in a record
#                        field, an arg position, etc.
#   • `.map_ok(...)`   — you want to transform the success value but keep
#                        the err intact; same expression-friendliness.
