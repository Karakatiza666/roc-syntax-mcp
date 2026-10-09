# Which construct to use.
#
# The other topics show what the language has. This topic shows what to pick
# when several constructs would work, and what the other choice costs. Every
# rule here is a default with a stated exception.

#
# 1. Errors: anonymous algebraic types, not a declared error type
#
#
# Put a structural tag union directly in the `Try` err position. Do not declare
# a nominal type to hold it.
#
#   parse_port : Str -> Try(U16, [Empty, NotANumber(Str)])   yes
#   PortErr := [Empty, NotANumber(Str)]                      no, see below
#
# The anonymous form is better for three reasons:
#
#   (a) It composes. An open union (`..`) accepts the errors of the caller's
#       other calls, so `?` passes errors from several modules through one
#       function, and nobody has to declare the combined type.
#   (b) It needs no conversion. Two functions that both return `[NotFound]` are
#       already compatible. Two nominal types with the same shape are distinct,
#       so every boundary between them needs a `map_err` that only converts.
#   (c) It stays inferable. `_` in the err position asks the compiler for the
#       exact union the body produces, and the unhandled-branch error message
#       then names the tags you have not covered yet.

# A public function annotates its errors structurally. A return-type union is
# already open, so a caller's own tags pass through without a `..`.
parse_port : Str -> Try(U16, [Empty, NotANumber(Str)])
parse_port = |text|
	if text.is_empty() {
		Err(Empty)
	} else {
		match U16.from_str(text) {
			Ok(port) => Ok(port)
			Err(_) => Err(NotANumber(text))
		}
	}

# Application code writes `_`, and the compiler makes the union of all errors
# that `?` passed up. The inferred error type here is
# `[Empty, NotANumber(Str), MissingHost]`, which nobody had to write down.
load_config : Str, Str -> Try({ host : Str, port : U16 }, _)
load_config = |host, port_text| {
	port = parse_port(port_text)?
	if host.is_empty() {
		Err(MissingHost)
	} else {
		Ok({ host, port })
	}
}

expect load_config("localhost", "8080") == Ok({ host: "localhost", port: 8080 })
expect load_config("", "8080") == Err(MissingHost)
expect load_config("localhost", "") == Err(Empty)

# Name the union only in these cases:
#
#   A type alias (`:`) when one long union repeats across many signatures. An
#   alias is structural, so it keeps every property above. It is a shorthand.
#   A nominal type (`:=`) at an FFI boundary, where the union must be closed so
#   that its memory layout is fixed. See the `platform_abi` topic.
#   A nominal type when the error carries methods, such as a custom `to_str`.
#
# An alias can stay open, so it still composes, but it must name the extension
# variable, because the compiler rejects a bare `..` in a type declaration.
ConfigErr(others) : [Empty, NotANumber(Str), MissingHost, ..others]

describe_err : ConfigErr(_) -> Str
describe_err = |err| match err {
	Empty => "port was blank"
	NotANumber(text) => "port ${text} is not a number"
	MissingHost => "host was blank"
	_ => "unknown"
}

# Wrap a shared error type per subsystem when the caller needs to know which
# subsystem failed. With `[FileErr(IOErr), StdoutErr(IOErr)]`, one caller can
# match `Err(FileErr(NotFound))` and another can match a bare `Err(_)`. The
# `error_design` topic has this convention and the others for error types.

#
# 2. Structural first, nominal only for identity or methods
#
#
# The same preference applies to types other than errors. A plain record or tag
# union gets `is_eq`, `to_hash`, and codec derivation for free, and two of
# them with the same shape are interchangeable.
#
# Use `:=` or `::` when you want the opposite: a type that the compiler keeps
# distinct from its representation.
#
#   `:`   alias, transparent. Shorthand for a shape.
#   `:=`  nominal, representation visible. Distinct identity, carries methods.
#   `::`  opaque, representation hidden outside the defining module.
#
# `UserId := U64` is useful because code that passes an `OrderId` where a
# `UserId` belongs then fails to compile. `Point : { x : F64, y : F64 }` stays
# an alias, because a `Point` incompatible with its own shape gains nothing.

Point : { x : F64, y : F64 }
UserId := U64

#
# 3. Derive the well-known methods, hand-write only the exception
#
#
# `method : _` on a nominal type asks the compiler to synthesize it. The
# compiler recognizes `is_eq`, `to_hash`, `parser_for`, `encoder_for`, `map`,
# and `map!`. Write a body only when you have a reason, because a derived
# method always matches the type's shape and a hand-written one can go stale.

Version := { major : U64, minor : U64 }.{
	is_eq : _
	to_hash : _
}

expect Version.{ major: 1, minor: 2 } == Version.{ major: 1, minor: 2 }

# `is_eq` and `to_hash` must agree: values that compare equal have to feed the
# hasher the same bytes. If you derive both, they agree. If you hand-write one
# and derive the other, a Dict can lose keys.

#
# 4. Method chains for the receiver, `|>` for everything else
#
#
# `.method()` resolves at compile time from the receiver's type, so a chain
# reads in the order it runs. Use it while the value passes through the first
# argument.

longest_word : Str -> Str
longest_word = |text|
	text.split_on(" ").fold("", |best, word|
		if word.count_utf8_bytes() > best.count_utf8_bytes() { word } else { best })

# Use `|>` when the value is not the first argument. `Str.join_with` takes the
# list first, so dispatch on a `List` receiver cannot find it. The pipe
# continues the chain.
shout_all : List(Str) -> Str
shout_all = |words|
	words.map(|w| w.with_ascii_uppercased()) |> Str.join_with(", ")

expect shout_all(["a", "b"]) == "A, B"

#
# 5. Keep `expect` next to the function it tests
#
#
# A top-level `expect` runs under `roc test` and is also an example that a
# reader can compare with the signature. Put it directly under the function, as
# above. Do not collect assertions in a separate block far from the code.
#
# See the `testing` topic for the block form and for `expect` inside a function.

#
# 6. Ask the compiler, do not guess
#
#
# The suffix conventions predict most builtin names (`_try` returns a `Try`,
# `!` is effectful, `_rev` walks backwards), but a prediction can be wrong.
# `search_symbols` finds a builtin by the shape of its type, and
# `roc_check` tells whether the code compiles. Both cost less than a guess
# that fails at build time.
