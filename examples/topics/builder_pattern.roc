# The builder pattern — fluent, chainable configuration of an immutable value.
#
# A common Roc idiom (used heavily by basic-cli's `Cmd`, by HTTP request
# builders, etc.) is:
#
#   1. Define a nominal record type with the configuration fields.
#   2. Define methods inside the `.{...}` block that each take a value of
#      that type as the first argument and return an updated copy.
#   3. Use static dispatch (`.method()`) to chain them.
#
# Because methods take and return the same type, you get this:
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
	## Constructor — returns a Request with sensible defaults.
	## A no-arg or single-arg "smart constructor" is the conventional
	## entry point. Often named `new`, sometimes `default`/`builder`.
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

	## Setter for a scalar field — same shape, just replacing the field.
	with_body : Request, Str -> Request
	with_body = |req, body| { ..req, body }

	## Setters can also take and apply multiple values at once.
	with_headers : Request, List((Str, Str)) -> Request
	with_headers = |req, pairs| {
		..req,
		headers: req.headers.concat(pairs),
	}

	## A boolean toggle is just a setter that hard-codes the new value.
	## (Naming: `clear_X`, `disable_X`, `enable_X` reads well in a chain.)
	clear_headers : Request -> Request
	clear_headers = |req| { ..req, headers: [] }

	## TERMINAL methods (sometimes called "executors") consume the
	## builder and produce a final result. By convention they:
	##   - Do not return Self.
	##   - Are typically effectful (named with `!`).
	##   - Come last in the chain.
	send! : Request => Try({}, [HttpErr(Str), ..])
	send! = |req|
		# (Pretend implementation — a real one calls the platform.)
		if req.url.is_empty() {
			Err(HttpErr("empty URL"))
		} else {
			Ok({})
		}
}

# ─────────────────────────────────────────────────────────────────────────────
# Usage
# ─────────────────────────────────────────────────────────────────────────────

## NB: `send!` is effectful, so this function is too.
fetch_example! : {} => Try({}, [HttpErr(Str), ..])
fetch_example! = |_|
	Request.new("https://example.com")
		.with_header("Accept", "application/json")
		.with_body("{}")
		.send!()

# ─────────────────────────────────────────────────────────────────────────────
# Why this works in Roc
# ─────────────────────────────────────────────────────────────────────────────
#
# • Records are VALUE types. `{ ..req, headers: ... }` produces a NEW record;
#   it doesn't mutate the caller's value. The chain is referentially clean:
#   no shared mutable state, no half-initialized objects, no thread issues.
#
# • Roc's compiler is smart enough to elide the copy when it can prove the
#   original is no longer used, so the builder pattern doesn't pay an
#   allocation per step — it's effectively in-place when used linearly.
#
# • `.method()` desugars to `Type.method(value, ...)`, so a method whose
#   first argument is the type name itself becomes a `value.method(...)`
#   call. This is why setters always look like:
#
#       with_header : Request, Str, Str -> Request
#       with_header = |req, k, v| ...
#
#   with `req` as the FIRST parameter — that's what makes the dot-syntax work.
#
# ─────────────────────────────────────────────────────────────────────────────
# Variations
# ─────────────────────────────────────────────────────────────────────────────
#
# 1. Bare record + module functions (no nominal type).
#    Works the same way, but loses the namespacing of `Request.new`.
#
# 2. Opaque (`::`) instead of nominal (`:=`).
#    Use `::` when the internal representation is an implementation detail
#    callers should not touch. Use `:=` (nominal) when the type is also
#    intentionally distinct from any structurally-equal record.
#
# 3. Builder that errs on `.build()` rather than on each setter.
#    Setters never fail; a final `build : T -> Try(Final, ValidationErr)`
#    or terminal effectful method runs all validation in one place.
#    This is the convention basic-cli uses for `exec_cmd!`.
#
# 4. `with_x : T, X -> T` vs. `set_x : T, X -> T` — pick one name shape
#    and stay consistent. `with_*` reads better in long chains; `set_*`
#    reads better when there are setters mixed with non-setters.
