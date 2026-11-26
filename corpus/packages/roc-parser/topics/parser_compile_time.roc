## Check a document while the program compiles, with roc-parser 6.0: annotate
## a string literal with the type of its format (`Yaml.Decoded`, `CSV`, `Xml`,
## `JsonValue`, `Markdown.Document`, `AsciiDoc`, `RocSyntax`, `HTTP.Request`,
## `Html.Fragment`, ...) and the compiler calls that type's `from_quote`. A bad
## document is a compile error that names the line, and a good one is a
## constant with nothing to parse at run time.
##
## `Parser.Quotation.require` does the same for an imported file, and
## `Parser.Quotation.check` gives your own type the same behavior. There is no
## `Literal` module and no `Utf8.parse_quote`. The ordinary `parse_str`
## functions are for input that arrives at run time.
##
## Full manual: all quotation types, adjacent files, props and lint checks, and
## error messages:
## https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/compile-time-parsing.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import pf.Stdout
import parser.CSV
import parser.HTTP
import parser.JsonValue
import parser.Markdown
import parser.Parser
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
#   HTTP.Request                the request (`HTTP.Response` too)
#   RocSyntax                   `.source`, `.tokens`, `.nodes`, ...
#   Html, Svg, MathML           checked markup (the parser_markup topic)
#
# A multi-line string is `\\` lines. If a quotation is wrong, the program does
# not build, and the compiler reports "invalid string" with the problem tag:
# `<literal>:2:7: YAML: IntegerOutOfRange({ target: U16, value: "99999" })`.

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

health : HTTP.Request
health = "GET /health HTTP/1.1\r\nHost: example.com\r\n\r\n"

# JSON escapes need two backslashes in a Roc string: `\\u00e9`, not `\u00e9`.
lock : JsonValue
lock =
	\\{"name": "app", "version": "6.0.0"}

expect people.value == [{ name: "Ada", age: 36 }]
expect table.records.len() == 2
expect settings.value == { name: "app", port: 8080 }
expect feed.root.children_named("entry").len() == 1
expect doc.blocks.len() == 2
expect health.target == "/health"
expect lock.get("version") == Ok(String("6.0.0"))

# --- Imported files, props and lint checks -----------------------------------
#
# Each format has `validate`, and YAML and CSV also `validate_as` (decode into
# the type that the annotation names). They take a props record: `source` is
# required, `name` (default "<literal>") goes into the error's `path`, the
# rest has defaults. They return the format's own typed failure, such as
# `Try(_, [InvalidYaml(Yaml.Error)])`, so they also work at run time.
# `Parser.Quotation.require` unwraps the `Ok`, or fails the build with the
# error. In a top-level constant it runs during compilation. With dynamic
# input, keep the `Try`: a failing `require` at run time is a crash.
#
# For a file next to the source, import it as a `Str` and validate that:
#
#   import "settings.yaml" as settings_text : Str
#
#   config : { name : Str, port : U16 }
#   config = Parser.Quotation.require(Yaml.validate_as({ source: settings_text, name: "settings.yaml" }))
#
# Lint checks are on by default and each is a `Bool` you set to `False`:
#   YAML      legacy_booleans    unquoted yes / no / on / off
#   CSV       duplicate_headers, empty_headers   (when a header mode is chosen)
#   XML       non_utf8_declaration
#   Markdown  unclosed_fences
#   AsciiDoc  unexpanded_includes
#   HTTP      repeated_content_length
#   RocSyntax placeholders       the `...` expression
# JSON has no lints; its props take `options`, the same record as the props
# of `JsonValue.parse_str`.
answer = Parser.Quotation.require(
	Yaml.validate({
		source: "answer: yes",
		lints: { legacy_booleans: False },
	}),
)

expect answer.get("answer") == Ok(Text("yes"))

# Without the override, the same text is a typed lint failure, and the name
# is in the path.
expect
	match Yaml.validate({ source: "answer: yes", name: "answer.yaml" }) {
		Err(InvalidYaml({ problem: LegacyBoolean("yes"), path, .. })) => path == [Source("answer.yaml")]
		_ => False
	}

# Typed YAML takes `keys` (`SnakeCase`, `KebabCase`, `CamelCase`) and
# `unknown_keys` (`Skip` or `Reject`).
strict_settings : Try({ name : Str }, [InvalidYaml(Yaml.Error)])
strict_settings = Yaml.validate_as({ source: "name: app\nextra: 1", unknown_keys: Reject })

expect strict_settings.is_err()

# CSV's `header` is `Absent` (raw default), `Exact` (typed default) or
# `Normalized`.
expect CSV.validate({ source: "name,name\n", header: Exact }).is_err()
expect CSV.validate({ source: "name,name\n" }).is_ok()

# --- Your own quotation type -------------------------------------------------
#
# Give a nominal type a `from_quote : Str -> Try(T, [BadQuotedBytes(Str)])`.
# `Parser.Quotation.check({ parser, source })` runs a combinator parser,
# requires it to consume everything, and reports the furthest error as
# `BadQuotedBytes`.
Count := { value : U64 }.{
	from_quote : Str -> Try(Count, [BadQuotedBytes(Str)])
	from_quote = |source| Parser.Quotation.check({ parser: Parser.Utf8.digits({}), source }).map_ok(|value| Count.{ value })
}

count : Count
count = "42"

expect count.value == 42

# Errors from `Parser.Quotation.error({ name, format, message, line, column })`
# read the same way as the built-in ones. A zero line or column means "not
# known".
expect Parser.Quotation.error({ name: "a.cfg", format: "CFG", message: "bad", line: 2, column: 3 }) == BadQuotedBytes("a.cfg:2:3: CFG: bad")

main! = |_args| {
	person = people.value.first() ?? { name: "", age: 0 }
	Stdout.line!("${settings.value.name} on port ${settings.value.port.to_str()}")?
	Stdout.line!("${person.name} is ${person.age.to_str()}")?
	Stdout.line!("${count.value.to_str()} from a custom parser")
}
