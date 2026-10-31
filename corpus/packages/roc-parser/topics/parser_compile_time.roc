## Check a document while the program compiles, with roc-parser 3.0: annotate
## a string literal with the type of its format (`Yaml.Decoded`, `CSV`, `Xml`,
## `JsonValue`, `Markdown.Document`, `AsciiDoc`, `RocSyntax`, ...) and the
## compiler calls that type's `from_quote`. A bad document is a compile error
## that names the line, and a good one is a constant with nothing to parse at
## run time.
##
## `Literal.require` does the same for an imported file, and `Utf8.parse_quote`
## gives your own type the same behavior. The ordinary `parse_str` functions
## are unchanged; they are for input that arrives at run time.
##
## Full manual: all quotation types, adjacent files, props and lint checks, and
## error messages:
## https://github.com/lukewilliamboswell/roc-parser/blob/3.0.0/docs/compile-time-parsing.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/3.0.0/6xsRdRqenJrAb4wG7HaST4Xh349vD5sHAJDsKTK6E3dr.tar.zst",
}

import pf.Stdout
import parser.CSV
import parser.JsonValue
import parser.Literal
import parser.Markdown
import parser.Utf8
import parser.Xml
import parser.Yaml

# --- A quotation is an annotated string --------------------------------------
#
# The annotation picks the format and the access to the result:
#
#   Yaml                        the tree itself
#   Yaml.Decoded(a)             `.value`, decoded as `a`
#   CSV                         `.records`, raw rows of bytes (the header too)
#   CSV.Decoded(row)            `.value`, a list of rows
#   Xml                         `.root` and `.declaration`
#   JsonValue                   the value itself
#   Markdown.Document           `.blocks`
#   AsciiDoc                    `.title` and `.blocks`
#   HTTP.RequestLiteral         `.value`   (HTTP.ResponseLiteral too)
#   RocSyntax                   `.source`, `.tokens`, `.nodes`, ...
#
# A multi-line string is `\\` lines. If a quotation is wrong, the compiler
# reports `name:line:column: FORMAT: message` and the program does not build.

Person : { name : Str, age : U8 }

people : CSV.Decoded(Person)
people =
	\\name,age
	\\Ada,36

# Raw CSV never guesses that the first row is a header.
table : CSV
table =
	\\name,age
	\\Ada,36

settings : Yaml.Decoded({ name : Str, port : U16 })
settings =
	\\name: app
	\\port: 8080

feed : Xml
feed =
	\\<feed><entry/></feed>

doc : Markdown.Document
doc =
	\\# Title
	\\
	\\Body

# JSON escapes need two backslashes in a Roc string: `\\u00e9`, not `\u00e9`.
lock : JsonValue
lock =
	\\{"name": "app", "version": "3.0.0"}

expect people.value == [{ name: "Ada", age: 36 }]
expect table.records.len() == 2
expect settings.value == { name: "app", port: 8080 }
expect feed.root.children_named("entry").len() == 1
expect doc.blocks.len() == 2
expect lock.get("version") == Ok(String("3.0.0"))

# --- Props and lint checks ---------------------------------------------------
#
# Each format has `validate`, and YAML and CSV also `validate_as` (decode into
# the type that the annotation names). HTTP has `validate_request` and
# `validate_response`. They take a props record: `source` is required,
# `name` (default "<literal>") appears in errors, the rest has defaults. They
# return `Try(_, [BadQuotedBytes(Str)])`, and `Literal.require` unwraps that or
# fails the build with the message. In a top-level constant it runs during
# compilation. With dynamic input, keep the `Try`: a failing `require` at run
# time is a crash.
#
# Lint checks are on by default and each is a `Bool` you set to `False`:
#   YAML      legacy_booleans    unquoted yes / no / on / off
#   CSV       duplicate_headers, empty_headers   (when a header mode is chosen)
#   XML       non_utf8_declaration
#   Markdown  unclosed_fences
#   AsciiDoc  unexpanded_includes
#   HTTP      repeated_content_length
#   RocSyntax placeholders       the `...` expression
# JSON has no lints; its props take `options`, the same record as
# `JsonValue.parse_with`.
answer = Literal.require(
	Yaml.validate({
		source: "answer: yes",
		lints: { legacy_booleans: False },
	}),
)

expect answer.get("answer") == Ok(Text("yes"))

# Without the override, the same text is an error that suggests quoting it.
expect
	match Yaml.validate({ source: "answer: yes", name: "answer.yaml" }) {
		Err(BadQuotedBytes(message)) => message.starts_with("answer.yaml:") and message.contains("legacy_booleans")
		Ok(_) => False
	}

# Typed YAML takes `keys` (`SnakeCase`, `KebabCase`, `CamelCase`) and
# `unknown_keys` (`Skip` or `Reject`).
strict_settings : Try({ name : Str }, [BadQuotedBytes(Str)])
strict_settings = Yaml.validate_as({ source: "name: app\nextra: 1", unknown_keys: Reject })

expect strict_settings.is_err()

# CSV's `header` is `Absent` (raw default), `Exact` (typed default) or
# `Normalized`.
expect CSV.validate({ source: "name,name\n", header: Exact }).is_err()
expect CSV.validate({ source: "name,name\n" }).is_ok()

# --- Your own quotation type -------------------------------------------------
#
# Give a nominal type a `from_quote : Str -> Try(T, [BadQuotedBytes(Str)])`.
# `Utf8.parse_quote({ parser, source })` runs a combinator parser, requires it
# to consume everything, and reports the furthest error as `BadQuotedBytes`.
Count := { value : U64 }.{
	from_quote : Str -> Try(Count, [BadQuotedBytes(Str)])
	from_quote = |source| Utf8.parse_quote({ parser: Utf8.digits, source }).map_ok(|value| Count.{ value })
}

count : Count
count = "42"

expect count.value == 42

# Errors from `Literal.error({ name, format, message, line, column })` read the
# same way as the built-in ones. A zero line or column means "not known".
expect Literal.error({ name: "a.cfg", format: "CFG", message: "bad", line: 2, column: 3 }) == BadQuotedBytes("a.cfg:2:3: CFG: bad")

main! = |_args| {
	person = people.value.first() ?? { name: "", age: 0 }
	Stdout.line!("${settings.value.name} on port ${settings.value.port.to_str()}")?
	Stdout.line!("${person.name} is ${person.age.to_str()}")?
	Stdout.line!("${count.value.to_str()} from a custom parser")
}
