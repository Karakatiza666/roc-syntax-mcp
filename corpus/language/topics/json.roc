# JSON encoding and decoding via `Json` (full path `Encoding.Json`).
#
# The language has no special case for JSON. JSON is one implementation of the
# generic codec protocol. A type provides `parser_for` and `encoder_for` methods
# to say how it is read and written, and a format supplies the encoding value
# that those methods receive.

# Entry points. Each has a `where` clause that requires the shape to provide the
# matching codec method, so an unsupported shape is a compile-time error and not
# a runtime one. The clause names that requirement with a `where` alias that the
# format module declares, and does not spell out the method signature:
#
#   Json.parse       : Str -> Try(a, [InvalidJson(Str), ..errs])
#                          where [a.Parseable([InvalidJson(Str), ..errs])]
#   Json.to_str      : a -> Str where [a.Encodable([])]
#   Json.to_str_try  : a -> Try(Str, err) where [a.Encodable(err)]
#
# The `..errs` is necessary, because the derived parser for a record also produces
# `MissingRequiredField(Str)`, so the real error union is wider than
# `[InvalidJson(Str)]`. Annotate the err position with `_` and let the compiler
# infer it, exactly as the `error_design` topic recommends.
#
# `to_str` requires an encoder that cannot fail. `to_str_try` is for values that
# might not be representable: `F32` and `F64` can hold `NaN` or an infinity, and
# JSON can only represent finite numbers.

Point : { x : I64, y : I64 }

# Structural records, tuples, tag unions, lists, sets, dicts, and supported
# builtins get derived codecs, so this needs no annotation on the type itself.
encode_point : Point -> Str
encode_point = |point| Json.to_str(point)

decode_point : Str -> Try(Point, _)
decode_point = |json| Json.parse(json)

# A record is an object with its fields in alphabetical order. A tag with no
# payload is a string, and a tuple is an array.
expect Json.to_str({ name: "Sam", age: 30.U64 }) == "{\"age\":30,\"name\":\"Sam\"}"
expect Json.to_str((1.U64, "a")) == "[1,\"a\"]"

Status : [Active, Banned(Str)]

status_json : Status -> Str
status_json = |status| Json.to_str(status)

expect status_json(Active) == "\"Active\""
expect status_json(Banned("spam")) == "{\"Banned\":\"spam\"}"

# `JsonEncoding` selects the dialect: `[Default, CamelCase, TrailingCommas]`.
#
#   Json.parse                 uses Default
#   Json.parse_trailing_commas uses TrailingCommas
#   Json.parser_camel          returns a parser using CamelCase
#
# `CamelCase` renames record fields through `JsonEncoding.rename_field`, so a
# Roc `snake_case` field maps to a JSON `camelCase` key. `TrailingCommas`
# accepts a trailing comma before a closing bracket or brace.
decode_lenient : Str -> Try(Point, _)
decode_lenient = |json| Json.parse_trailing_commas(json)

# `parser_camel` returns the parser. Bound at the top level, it is built once,
# at compile time.
decode_camel : Str -> Try(Point, _)
decode_camel = Json.parser_camel()

# A generic function of your own that wraps an entry point must repeat its
# constraint. `Json` (full path `Encoding.Json`) declares `Encodable` and
# `Parseable`, so an app must qualify them. A bare `a.Encodable([])` is an
# undeclared type. The structural form that the alias expands to also fails:
# `where [a.encoder_for : e -> (a, s -> Try(s, []))]` type-mismatches against
# `to_str`. Copy the alias, qualified.
to_json : a -> Str where [a.Json.Encodable([])]
to_json = |value| Json.to_str(value)

from_json : Str -> Try(a, [InvalidJson(Str), ..errs])
	where [a.Json.Parseable([InvalidJson(Str), ..errs])]
from_json = |text| Json.parse(text)

origin : Point
origin = { x: 1, y: 2 }

expect to_json(origin) == "{\"x\":1,\"y\":2}"

round_tripped : Try(Point, _)
round_tripped = from_json(to_json(origin))
expect round_tripped == Ok(origin)

# A `where` alias is ordinary syntax, and any module can declare one:
#
#   a.Showable : where [a.to_str : a -> Str]
#   show : a -> Str where [a.Showable]

# A nominal type has no codec by default, because parsing could break its
# invariants and encoding could expose its internals. It opts into derived
# codecs the same way it opts into any other derived method (see the
# `derived_methods` topic). The derived codec uses the backing representation.
Config := { host : Str, port : U16 }.{
	parser_for : _
	encoder_for : _
}

# @rejects missing method
# UserId := { raw : U64 }
# user_json = Json.to_str(UserId.{ raw: 1 })

# Hand-write the methods instead when the type needs a custom representation, or
# when its backing should stay hidden. The `where` clause names only the format
# operations this type actually uses, so it works with any encoding that
# provides them, not just JSON.
#
#   parser_for  : encoding -> (state -> Try({ value : T, rest : state }, err))
#   encoder_for : encoding -> (T, state -> Try(state, err))
Token := { raw : Str }.{
	parser_for : encoding -> (state -> Try({ value : Token, rest : state }, err))
		where [
			encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err),
		]
	parser_for = |encoding| {
		Encoding : encoding

		|state| {
			parsed = Encoding.parse_str(encoding, state)?
			Ok({ value: Token.{ raw: parsed.value }, rest: parsed.rest })
		}
	}

	encoder_for : encoding -> (Token, state -> Try(state, err))
		where [
			encoding.encode_str : encoding, Str, state -> Try(state, err),
		]
	encoder_for = |encoding| {
		Encoding : encoding

		|token, state| Encoding.encode_str(encoding, token.raw, state)
	}
}

# `Encoding.Json` also exposes the per-type primitives that the derived codecs
# use, for hand-written parsers that must call the format directly:
# `parse_str`, `parse_bool`, `parse_null`, `parse_u8` through `parse_i128`,
# `parse_dec`, `parse_f32`, `parse_f64`, the `parse_list_*` and `parse_record_*`
# container steps, and the matching `encode_*` family.
#
# `Encoding.HttpHeader` is a second format on the same protocol. It parses
# headers into a record, and an absent header fits a `Try(_, [Missing])` field.
# This is why it is useful to define the codec methods once per type. A package
# can also ship a format, with no change to the types it parses.
parse_headers : Str -> Try({ content_length : U64, x_auth_token : Try(Str, [Missing]) }, _)
parse_headers = Encoding.HttpHeader.parser_for()

expect parse_headers("Content-Length: 12\r\n") == Ok({ content_length: 12, x_auth_token: Err(Missing) })

# A field missing from the input is an error unless the target says it may be
# missing: `?: T` (optional field) or `Try(T, [Missing])`. Any other missing
# field gives `Err(MissingRequiredField("name"))`.
Profile : { name : Str, nick ?: Str, age : Try(U64, [Missing]) }

parse_profile : Str -> Try(Profile, _)
parse_profile = |text| Json.parse(text)

expect parse_profile("{\"name\":\"ada\"}").is_ok()
expect parse_profile("{}") == Err(MissingRequiredField("name"))
