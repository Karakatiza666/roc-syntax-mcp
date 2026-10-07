# The builder pattern: fluent, chainable configuration of an immutable value.
#
# basic-cli's `Cmd` and many HTTP request builders use this common Roc idiom:
#
#   1. Define a nominal record type with the configuration fields.
#   2. Define methods inside the `.{...}` block that each take a value of
#      that type as the first argument and return an updated copy.
#   3. Use static dispatch (`.method()`) to chain them.
#
# Because the methods take and return the same type, the calls chain:
#
#   Cmd.new("cargo")
#       .arg("build")
#       .env("RUST_BACKTRACE", "1")
#       .exec_cmd!()?
#
# ─────────────────────────────────────────────────────────────────────────────
# Skeleton
# ─────────────────────────────────────────────────────────────────────────────

Request := {
	url : Str,
	headers : List((Str, Str)),
	body : Str,
	timeout_ms : U64,
}.{

	## Returns a Request with default values. The usual entry point is a
	## "smart constructor" with zero or one argument. Its name is often
	## `new`, sometimes `default` or `builder`.
	new : Str -> Request
	new = |url| {
		url,
		headers: [],
		body: "",
		timeout_ms: 30_000,
	}

	## Each setter takes `Self` as the first argument (so it can be
	## called as `req.with_header(...)`) and returns a new Self with
	## one field updated. Use record-update syntax `{ ..req, ... }`
	## to keep all other fields.
	with_header : Request, Str, Str -> Request
	with_header = |req, key, value| {
		..req,
		headers: req.headers.append((key, value)),
	}

	## A setter for a scalar field has the same shape and replaces the field.
	with_body : Request, Str -> Request
	with_body = |req, body| { ..req, body }

	## Setters can also take and apply multiple values at once.
	with_headers : Request, List((Str, Str)) -> Request
	with_headers = |req, pairs| {
		..req,
		headers: req.headers.concat(pairs),
	}

	## A boolean toggle is a setter that hard-codes the new value.
	## Names such as `clear_X`, `disable_X` and `enable_X` read well in a chain.
	clear_headers : Request -> Request
	clear_headers = |req| { ..req, headers: [] }

	## Terminal methods (sometimes called "executors") consume the
	## builder and produce a final result. By convention they:
	##   - Do not return Self.
	##   - Are typically effectful (named with `!`).
	##   - Come last in the chain.
	send! : Request => Try({}, [HttpErr(Str)])
	send! = |req|
	# A stub. A real implementation calls the platform.
		if req.url.is_empty() {
			Err(HttpErr("empty URL"))
		} else {
			Ok({})
		}
}

# ─────────────────────────────────────────────────────────────────────────────
# Usage
# ─────────────────────────────────────────────────────────────────────────────

## `send!` is effectful, so this function is effectful too.
fetch_example! : {} => Try({}, [HttpErr(Str)])
fetch_example! = |_|
	Request.new("https://example.com")
		.with_header("Accept", "application/json")
		.with_body("{}")
		.send!()

# ─────────────────────────────────────────────────────────────────────────────
# Why this works in Roc
# ─────────────────────────────────────────────────────────────────────────────
#
# • Records are value types. `{ ..req, headers: ... }` makes a new record and
#   does not mutate the caller's value. The chain has no shared mutable state,
#   no half-initialized objects and no thread issues.
#
# • The compiler skips the copy when it can prove that nothing uses the
#   original again. A chain that uses each value once therefore updates in
#   place and does not allocate at each step.
#
# • `.method()` desugars to `Type.method(value, ...)`, so you can call a method
#   whose first parameter has the type itself as `value.method(...)`. This is
#   why setters always look like:
#
#       with_header : Request, Str, Str -> Request
#       with_header = |req, k, v| ...
#
#   with `req` as the first parameter, so that the dot syntax works.
#
# ─────────────────────────────────────────────────────────────────────────────
# Variations
# ─────────────────────────────────────────────────────────────────────────────
#
# 1. A bare record and module functions, with no nominal type.
#    This works the same way, but loses the namespace of `Request.new`.
#
# 2. Opaque (`::`) instead of nominal (`:=`).
#    Use `::` when the internal representation is an implementation detail
#    callers should not touch. Use `:=` (nominal) when the type is also
#    intentionally distinct from any structurally-equal record.
#
# 3. A builder that fails on `.build()` and not on each setter.
#    Setters never fail. A final `build : T -> Try(Final, ValidationErr)`
#    or a terminal effectful method runs all validation in one place.
#    This is the convention basic-cli uses for `exec_cmd!`.
#
# 4. `with_x : T, X -> T` vs `set_x : T, X -> T`: pick one name shape
#    and use it everywhere. `with_*` reads better in long chains. `set_*`
#    reads better when setters mix with other methods in a chain.

# A record builder is a different feature with a similar name. A record literal
# followed by `.Type` combines one wrapped value per field through that type's
# `map2`, so each field can have its own type and the result is a record.
Field(a) := { value : a }.{
	pure : a -> Field(a)
	pure = |x| { value: x }

	map2 : Field(a), Field(b), (a, b -> c) -> Field(c)
	map2 = |fa, fb, combine| { value: combine(fa.value, fb.value) }

	run : Field(a) -> a
	run = |field| field.value
}

built_config = {
	host: Field.pure("localhost"),
	port: Field.pure(8080.U16),
}.Field

expect built_config.run() == { host: "localhost", port: 8080 }
