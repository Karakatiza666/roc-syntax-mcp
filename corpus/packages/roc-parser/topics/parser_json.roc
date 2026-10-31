## Read and write JSON of any shape with the `JsonValue` module of
## lukewilliamboswell/roc-parser 3.0: `JsonValue.parse_str` into a lossless
## value, `get`, `at` and `get_path` to walk it, `parse_with` to choose how
## strict to be, and `to_str` to write it back.
##
## The module is `JsonValue`, not `Json`, because Roc auto-imports a builtin
## `Json`. Use the builtin to decode a document into a record whose shape you
## know. Use `JsonValue` when a record cannot describe the document (keys such
## as `bom-ref`, items of different shapes, JSON Schema) or when the data must
## pass through unchanged: member order, every digit of a number, repeated keys.
##
## The error tag is `InvalidJsonValue`, so that one function can use `?` on
## both the builtin (`InvalidJson(Str)`) and this module.
##
## Full manual: walking a value, error positions, numbers, repeated keys, every
## option, writing, compile-time checks, and use inside a larger grammar:
## https://github.com/lukewilliamboswell/roc-parser/blob/3.0.0/docs/json.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/3.0.0/6xsRdRqenJrAb4wG7HaST4Xh349vD5sHAJDsKTK6E3dr.tar.zst",
}

import pf.Stdout
import parser.JsonValue
import parser.Parser
import parser.Utf8

# --- Parse, then walk --------------------------------------------------------
#
# A `JsonValue` is `Null`, `Bool(Bool)`, `Number(Str)`, `String(Str)`,
# `Array(List(JsonValue))` or `Object(List({ key, value }))`. An object keeps
# its members in source order. `get(key)`, `at(index)` and `get_path(path)`
# give `Try(JsonValue, [Missing])`. A path segment on an array is a decimal
# string such as "0". `as_str`, `as_bool`, `as_list` and `as_object` give
# `Err(WrongType)` for another variant.

sbom_text =
	\\{
	\\  "components": [
	\\    { "bom-ref": "pkg:roc/parser@3.0.0", "name": "roc-parser", "licenses": [{ "license": { "id": "UPL-1.0" } }] },
	\\    { "bom-ref": "pkg:roc/unicode@4.3.0", "name": "unicode", "licenses": [{ "expression": "UPL-1.0 OR MIT" }] }
	\\  ]
	\\}

# A licence is an SPDX id or an SPDX expression. A record type cannot hold both.
licence : JsonValue -> Str
licence = |component| {
	match component.get_path(["licenses", "0", "license", "id"]) {
		Ok(String(id)) => id
		_ =>
			match component.get_path(["licenses", "0", "expression"]) {
				Ok(String(expression)) => expression
				_ => "no licence"
			}
	}
}

components : Str -> Try(List(Str), [InvalidJsonValue(JsonValue.Error), Missing, WrongType])
components = |text| {
	bom = JsonValue.parse_str(text)?
	list = bom.get("components")?.as_list()?
	Ok(list.map(|component| "${(component.get("name") ?? Null).as_str() ?? "?"}: ${licence(component)}"))
}

expect components(sbom_text) == Ok(["roc-parser: UPL-1.0", "unicode: UPL-1.0 OR MIT"])

expect JsonValue.parse_str("{\"b\": 1, \"a\": 2}").map_ok(JsonValue.keys) == Ok(["b", "a"])
expect JsonValue.parse_str("[10, 20]").map_ok(|v| v.at(1)) == Ok(Ok(Number("20")))
expect JsonValue.parse_str("{}").map_ok(|v| v.get("x")) == Ok(Err(Missing))
expect JsonValue.parse_str("[]").map_ok(|v| v.as_str()) == Ok(Err(WrongType))

# --- Errors carry a position -------------------------------------------------
#
# `InvalidJsonValue({ line, column, message })`. Lines and columns start at 1,
# and a column counts UTF-8 bytes, so the `é` moves the column by 2.
expect JsonValue.parse_str("[\"café\", tru]") == Err(InvalidJsonValue({ line: 1, column: 11, message: "invalid literal: expected true, false or null" }))

# Strict means RFC 8259 and nothing else: no comments, no trailing comma, no
# single quotes, and exactly one value in the document.
expect JsonValue.parse_str("[1, 2,]").is_err()
expect JsonValue.parse_str("// note\n{}").is_err()
expect JsonValue.parse_str("{\"a\": 1} {\"b\": 2}").is_err()

# --- Numbers keep their text -------------------------------------------------
#
# A `Number` holds the text as written, so no digit is lost and `1.50` is not
# `1.5`. Convert when you need arithmetic. `as_i64` and `as_u64` accept only
# integers, `as_dec` any number that fits a `Dec`. For an `F64`, use
# `F64.from_str` on the text.
expect JsonValue.parse_str("1.50") != JsonValue.parse_str("1.5")
expect JsonValue.parse_str("18446744073709551615").map_ok(JsonValue.as_u64) == Ok(Ok(18446744073709551615))
expect JsonValue.parse_str("1e3").map_ok(JsonValue.as_i64) == Ok(Err(WrongType))
expect JsonValue.parse_str("1.50").map_ok(JsonValue.as_dec) == Ok(Ok(1.5))
expect JsonValue.parse_str("18446744073709551616").map_ok(JsonValue.as_u64) == Ok(Err(OutOfRange))

# --- Repeated keys are an error by default ------------------------------------
#
# Readers disagree about `{"id": 1, "id": 2}`, so `parse_str` rejects it. The
# `duplicates` option is `Reject`, `CollapseIdentical` (equal copies only),
# `KeepFirst` or `KeepLast`.
repeated = "{\"id\": 1, \"name\": \"web\", \"id\": 2}"

expect JsonValue.parse_str(repeated).is_err()
expect JsonValue.parse_with(repeated, { duplicates: KeepLast }).map_ok(|v| v.get("id")) == Ok(Ok(Number("2")))
expect JsonValue.parse_with(repeated, { duplicates: KeepFirst }).map_ok(|v| v.get("id")) == Ok(Ok(Number("1")))
expect JsonValue.parse_with(repeated, { duplicates: CollapseIdentical }).is_err()

# --- Options: pass only the fields you change --------------------------------
#
# `JsonValue.parse_str(text)` is `parse_with(text, {})`. Limits: `max_depth`
# (default 128), `max_items`, `max_string_bytes`, `max_number_digits`.
# Relaxations, all off by default: `comments` and `trailing_commas` (JSONC),
# `bom`, `non_finite` (`NaN`, `Infinity`), `control_characters`, and
# `lone_surrogates: Replace`. Checks: `duplicates`, `top_level` (`Any`,
# `ObjectOrArray` or `Object`) and `interoperable_numbers` (I-JSON).
read_jsonc : Str -> Try(JsonValue, [InvalidJsonValue(JsonValue.Error)])
read_jsonc = |text| JsonValue.parse_with(text, { comments: True, trailing_commas: True })

expect read_jsonc("{\n  // target\n  \"strict\": true, /* on */\n}").map_ok(|v| v.get("strict")) == Ok(Ok(Bool(True)))

# `/*` inside a string is text, not a comment.
expect read_jsonc("[\"src/**/*.ts\"]") == Ok(Array([String("src/**/*.ts")]))

# Options for a document from the network.
untrusted : JsonValue.Options
untrusted = { max_depth: 32, max_items: 1000, max_string_bytes: 4096, top_level: Object, interoperable_numbers: True }

expect JsonValue.parse_with("[1, 2, 3]", untrusted).is_err()
expect JsonValue.parse_with("{\"id\": 9007199254740993}", untrusted).is_err()
expect JsonValue.parse_with("{\"ids\": [1, 2, 3]}", untrusted).is_ok()

# --- Write it back -----------------------------------------------------------
#
# `to_str` writes compact JSON and `to_str_with` takes `{ indent, sort_keys }`.
# Both return a `Try`, because a value built in code can hold what JSON cannot
# say: `InvalidNumber(text)`, `DuplicateKey(key)` or `TooDeep`. Numbers are
# written as their text. A parsed value reads back as itself.
release : JsonValue
release = Object([
	{ key: "name", value: String("roc-parser") },
	{ key: "sizes", value: Array([Number("1.50"), Number("2E3")]) },
	{ key: "assets", value: Object([]) },
])

expect JsonValue.to_str(release) == Ok("{\"name\":\"roc-parser\",\"sizes\":[1.50,2E3],\"assets\":{}}")
expect JsonValue.to_str_with(Array([Number("1")]), { indent: 2 }) == Ok("[\n  1\n]")
expect JsonValue.to_str(Array([Number("0x10")])) == Err(InvalidNumber("0x10"))
expect JsonValue.to_str(Object([{ key: "a", value: Null }, { key: "a", value: Null }])) == Err(DuplicateKey("a"))
expect JsonValue.to_str(Array([Number("NaN")])) == Err(InvalidNumber("NaN"))

# --- Inside a larger parser --------------------------------------------------
#
# `JsonValue.parser` and `parser_with(options)` are `Parser(Utf8.Bytes, JsonValue)`
# values. This reads JSON Lines, one document per line.
json_lines : Str -> Try(List(JsonValue), [ParseError({ message : Str, offset : U64 })])
json_lines = |text| Utf8.parse_str(Parser.many(JsonValue.parser), text)

expect json_lines("{\"e\": 1}\n{\"e\": 2}\n").map_ok(List.len) == Ok(2)

# For a literal that is known at build time, annotate it with `JsonValue`
# and the compiler checks it (the parser_compile_time topic). In a Roc string,
# write each backslash of a JSON escape twice: `\\u00e9`.
lock : JsonValue
lock =
	\\{"name": "app", "greeting": "caf\\u00e9"}

expect lock.get("greeting") == Ok(String("café"))

print_components! : Str => Try({}, _)
print_components! = |text| {
	match components(text) {
		Ok(lines) =>
			for line in lines {
				Stdout.line!(line)?
			}

		Err(problem) => Stdout.line!("cannot read the SBOM: ${Str.inspect(problem)}")?
	}
	Ok({})
}

main! = |_args| print_components!(sbom_text)
