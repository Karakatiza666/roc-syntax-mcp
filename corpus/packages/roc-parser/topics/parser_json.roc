## Read and write JSON of any shape with the `JsonValue` module of
## lukewilliamboswell/roc-parser 6.0: `JsonValue.parse_str(text, props)` into a
## lossless value, `get`, `at` and `get_path` to walk it, props to choose how
## strict to be, and `value.encode(props)` to write it back as bytes.
##
## The module is `JsonValue`, not `Json`, because Roc auto-imports a builtin
## `Json`. Use the builtin to decode a document into a record whose shape you
## know. Use `JsonValue` when a record cannot describe the document (keys such
## as `bom-ref`, items of different shapes, JSON Schema) or when the data must
## pass through unchanged: member order, every digit of a number, repeated keys.
##
## The error tag is `InvalidJsonValue(Parser.Diagnostic(JsonValue.Problem))`,
## so that one function can use `?` on both the builtin (`InvalidJson(Str)`)
## and this module. JSON Lines too large for memory are read with
## `JsonValue.record_decoder` (the parser_streaming topic).
##
## Full manual: walking a value, error positions, numbers, repeated keys, every
## option, writing, compile-time checks, and use inside a larger grammar:
## https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/json.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import pf.Stdout
import parser.JsonValue
import parser.Parser

# --- Parse, then walk --------------------------------------------------------
#
# A `JsonValue` is `Null`, `Bool(Bool)`, `Number(Str)`, `String(Str)`,
# `Array(List(JsonValue))` or `Object(List({ key, value }))`. An object keeps
# its members in source order. `get(key)`, `at(index)` and `get_path(path)`
# give `Try(JsonValue, [Missing])`. A path segment on an array is a decimal
# string such as "0". `as_str`, `as_bool`, `as_list` and `as_object` give
# `Err(WrongType)` for another variant. `parse_str` takes props: pass `{}`.

sbom_text =
	\\{
	\\  "components": [
	\\    { "bom-ref": "pkg:roc/parser@6.0.0", "name": "roc-parser", "licenses": [{ "license": { "id": "UPL-1.0" } }] },
	\\    { "bom-ref": "pkg:roc/unicode@4.3.3", "name": "unicode", "licenses": [{ "expression": "UPL-1.0 OR MIT" }] }
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
	bom = JsonValue.parse_str(text, {})?
	list = bom.get("components")?.as_list()?
	Ok(list.map(|component| "${(component.get("name") ?? Null).as_str() ?? "?"}: ${licence(component)}"))
}

expect components(sbom_text) == Ok(["roc-parser: UPL-1.0", "unicode: UPL-1.0 OR MIT"])

expect JsonValue.parse_str("{\"b\": 1, \"a\": 2}", {}).map_ok(JsonValue.keys) == Ok(["b", "a"])
expect JsonValue.parse_str("[10, 20]", {}).map_ok(|v| v.at(1)) == Ok(Ok(Number("20")))
expect JsonValue.parse_str("{}", {}).map_ok(|v| v.get("x")) == Ok(Err(Missing))
expect JsonValue.parse_str("[]", {}).map_ok(|v| v.as_str()) == Ok(Err(WrongType))

# --- Errors are typed --------------------------------------------------------
#
# The payload is `{ problem, location, path }`. The problem is a tag. The
# location is `Text({ offset, line, column })`: lines and columns start at 1,
# and a column counts UTF-8 bytes, so the `é` moves the column by 2.
problem : Str -> Str
problem = |text|
	match JsonValue.parse_str(text, {}) {
		Ok(_) => "valid"
		Err(InvalidJsonValue({ problem: p, location: Text({ line, column, .. }), .. })) => "${line.to_str()}:${column.to_str()}: ${Str.inspect(p)}"
		Err(InvalidJsonValue({ problem: p, .. })) => Str.inspect(p)
	}

expect problem("[\"café\", tru]") == "1:11: InvalidLiteral"

# Strict means RFC 8259 and nothing else: no comments, no trailing comma, no
# single quotes, and exactly one value in the document.
expect problem("[1, 2,]") == "1:6: TrailingComma"
expect problem("// note\n{}") == "1:1: CommentsNotAllowed"
expect problem("{\"a\": 1} {\"b\": 2}") == "1:10: UnexpectedContent"

# --- Numbers keep their text -------------------------------------------------
#
# A `Number` holds the text as written, so no digit is lost and `1.50` is not
# `1.5`. Convert when you need arithmetic. `as_i64` and `as_u64` accept only
# integers, `as_dec` any number that fits a `Dec`. For an `F64`, use
# `F64.from_str` on the text.
expect JsonValue.parse_str("1.50", {}) != JsonValue.parse_str("1.5", {})
expect JsonValue.parse_str("18446744073709551615", {}).map_ok(JsonValue.as_u64) == Ok(Ok(18446744073709551615))
expect JsonValue.parse_str("1e3", {}).map_ok(JsonValue.as_i64) == Ok(Err(WrongType))
expect JsonValue.parse_str("1.50", {}).map_ok(JsonValue.as_dec) == Ok(Ok(1.5))
expect JsonValue.parse_str("18446744073709551616", {}).map_ok(JsonValue.as_u64) == Ok(Err(OutOfRange))

# --- Repeated keys are an error by default ------------------------------------
#
# Readers disagree about `{"id": 1, "id": 2}`, so `parse_str` rejects it. The
# `duplicates` prop is `Reject`, `CollapseIdentical` (equal copies only),
# `KeepFirst` or `KeepLast`.
repeated = "{\"id\": 1, \"name\": \"web\", \"id\": 2}"

expect problem(repeated) == "1:26: DuplicateKey(\"id\")"
expect JsonValue.parse_str(repeated, { duplicates: KeepLast }).map_ok(|v| v.get("id")) == Ok(Ok(Number("2")))
expect JsonValue.parse_str(repeated, { duplicates: KeepFirst }).map_ok(|v| v.get("id")) == Ok(Ok(Number("1")))
expect JsonValue.parse_str(repeated, { duplicates: CollapseIdentical }).is_err()

# --- Props: pass only the fields you change ----------------------------------
#
# There is no `parse_with`: every option is a prop of `parse_str`. Limits:
# `max_depth`, `max_items`, `max_string_bytes`, `max_number_digits`,
# `max_bytes`. Relaxations, all off by default: `comments` and
# `trailing_commas` (JSONC), `bom`, `non_finite` (`NaN`, `Infinity`). Checks:
# `duplicates`, `top_level` (`Any`, `ObjectOrArray` or `Object`) and
# `interoperable_numbers` (I-JSON).
read_jsonc : Str -> Try(JsonValue, [InvalidJsonValue(JsonValue.Error)])
read_jsonc = |text| JsonValue.parse_str(text, { comments: True, trailing_commas: True })

expect read_jsonc("{\n  // target\n  \"strict\": true, /* on */\n}").map_ok(|v| v.get("strict")) == Ok(Ok(Bool(True)))

# `/*` inside a string is text, not a comment.
expect read_jsonc("[\"src/**/*.ts\"]") == Ok(Array([String("src/**/*.ts")]))

# Props held in a value, for a document from the network. Fields you leave
# out keep their defaults.
untrusted : JsonValue.Props
untrusted = { max_depth: 32, max_items: 1000, max_string_bytes: 4096, top_level: Object, interoperable_numbers: True }

expect JsonValue.parse_str("[1, 2, 3]", untrusted).is_err()
expect JsonValue.parse_str("{\"id\": 9007199254740993}", untrusted).is_err()
expect JsonValue.parse_str("{\"ids\": [1, 2, 3]}", untrusted).is_ok()

# --- Write it back -----------------------------------------------------------
#
# `value.encode(props)` writes compact JSON as `List(U8)`, not a `Str`; props
# take `indent` and `sort_keys`. It returns a `Try`, because a value built in
# code can hold what JSON cannot say: a bad number or a repeated key is an
# `InvalidJsonValue` with location `Unavailable(GeneratedValue)`. Numbers are
# written as their text. There is no `to_str`.
release : JsonValue
release = Object([
	{ key: "name", value: String("roc-parser") },
	{ key: "sizes", value: Array([Number("1.50"), Number("2E3")]) },
	{ key: "assets", value: Object([]) },
])

write : JsonValue, JsonValue.WriteProps -> Try(Str, [InvalidJsonValue(JsonValue.Error)])
write = |value, props| value.encode(props).map_ok(Str.from_utf8_lossy)

expect write(release, {}) == Ok("{\"name\":\"roc-parser\",\"sizes\":[1.50,2E3],\"assets\":{}}")
expect write(Array([Number("1")]), { indent: 2 }) == Ok("[\n  1\n]")

write_problem : JsonValue -> Str
write_problem = |value|
	match write(value, {}) {
		Ok(text) => text
		Err(InvalidJsonValue({ problem: p, .. })) => Str.inspect(p)
	}

expect write_problem(Array([Number("0x10")])) == "InvalidNumber({ bytes: [48, 120, 49, 48], total_bytes: 4 })"
expect write_problem(Object([{ key: "a", value: Null }, { key: "a", value: Null }])) == "DuplicateKey(\"a\")"

# --- Inside a larger parser --------------------------------------------------
#
# `JsonValue.parser(props)` is a `Parser(Parser.Utf8.Bytes, JsonValue, _)`.
# This reads JSON Lines, one document per line.
json_lines : Str -> Try(List(JsonValue), _)
json_lines = |text| Parser.many(JsonValue.parser({})).parse_str(text)

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

		Err(err) => Stdout.line!("cannot read the SBOM: ${Str.inspect(err)}")?
	}
	Ok({})
}

main! = |_args| print_components!(sbom_text)
