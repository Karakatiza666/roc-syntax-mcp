## A parser for your own text format, from lukewilliamboswell/roc-parser 6.0:
## combinators, for when no module parses the format. The formats this package
## ships are in parser_csv, parser_yaml, parser_json, parser_xml, parser_markup,
## parser_markdown, parser_asciidoc, parser_roc_syntax and parser_http.
## `Parser.Quotation.check` turns a combinator parser into a build-time check
## (parser_compile_time).
##
## Full manual:
##
## - A first parser, step by step, from one key to every line with errors:
##   https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/combinator-primer.adoc
## - Every combinator by task: running, sequencing, alternatives, repetition,
##   recursion, bytes against characters, and input that is not text:
##   https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/combinators.adoc
## - A format of your own, from the result types to a tested parser:
##   https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/custom-format.adoc
## - Locations, logical paths and problem tags of every format:
##   https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/errors.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import pf.Stdout
import parser.Parser

# --- The type and the imports ------------------------------------------------
#
# `import parser.Parser` is the only import. The byte primitives are in
# `Parser.Utf8`, which is not a module of its own: `import parser.Utf8` is an
# error. `Parser(input, value, problem)` has three arguments. The third is the
# open union of failure tags, and `_` lets the compiler fill it in.
#
# Primitives that take nothing are factories, so call them: `digits({})`,
# `any_codeunit({})`, `rest({})`. A bare `Parser.Utf8.digits` is a function,
# and `.keep(Parser.Utf8.digits)` is a type mismatch.

Bytes : Parser.Utf8.Bytes

port : Parser(Bytes, U64, _)
port = Parser.const(|n| n).skip(Parser.Utf8.string("port=")).keep(Parser.Utf8.digits({}))

# A parser is run with a method on it. `parse_str` must consume all the input.
# `run_str` parses a prefix and gives `{ value, rest }`, with `rest` a `Str`.
expect port.parse_str("port=80") == Ok(80)
expect port.run_str("port=80;x") == Ok({ value: 80, rest: ";x" })

# --- Errors are typed --------------------------------------------------------
#
# A failure is `ParseError(Parser.Diagnostic(problem))`, a record of `problem`,
# `location` and `path`. The problem is a tag, not a message string: match it.
# `parse_str` gives a `Text` location with a zero-based byte `offset` and a
# one-based `line` and `column`.
expect port.parse_str("port=x") == Err(ParseError(Parser.Diagnostic.{ problem: ExpectedDigit, location: Text({ offset: 5, line: 1, column: 6 }), path: [] }))
expect port.parse_str("port=80x") == Err(ParseError(Parser.Diagnostic.{ problem: UnexpectedInput, location: Text({ offset: 7, line: 1, column: 8 }), path: [] }))

# Validate a value with `map` to a `Try`, then `flatten`. The `Err` payload is
# your own tag. It joins the problem union, so a caller can match it.
small_port : Parser(Bytes, U64, _)
small_port =
	port
		.map(|n| if n <= 65535 Ok(n) else Err(PortOutOfRange(n)))
		.flatten()

describe : Str -> Str
describe = |text|
	match small_port.parse_str(text) {
		Ok(n) => "port ${n.to_str()}"
		Err(ParseError({ problem: PortOutOfRange(n), .. })) => "${n.to_str()} is too big"
		Err(ParseError({ problem, location, .. })) => "${Str.inspect(location)}: ${Str.inspect(problem)}"
	}

expect describe("port=70000") == "70000 is too big"

# --- Sequencing --------------------------------------------------------------
#
# `const` holds a curried constructor, one argument per `keep`: write
# `|key| |found| ...`, because `|key, found| ...` is a type mismatch on
# `keep`. `skip` runs a parser and drops its value.
name : Parser(Bytes, Str, _)
name =
	Parser.Utf8.codeunit_satisfies(|b| (b >= 'a' and b <= 'z') or b == '_')
		.one_or_more()
		.map(Str.from_utf8_lossy)

Value : [Num(U64), Text(Str), Flag]

value : Parser(Bytes, Value, _)
value = Parser.one_of([Parser.Utf8.digits({}).map(|n| Num(n)), name.map(|s| Text(s))])

# `maybe` gives `Try(a, [Missing])`, so `??` gives the default.
setting : Parser(Bytes, { key : Str, value : Value }, _)
setting =
	Parser.const(|key| |found| { key, value: found ?? Flag })
		.keep(name)
		.keep(Parser.const(|v| v).skip(Parser.Utf8.codeunit('=')).keep(value).maybe())

settings : Parser(Bytes, List({ key : Str, value : Value }), _)
settings = setting.sep_by(Parser.Utf8.string("; "))

expect settings.parse_str("os=mac; port=80; v") == Ok([{ key: "os", value: Text("mac") }, { key: "port", value: Num(80) }, { key: "v", value: Flag }])

# --- Choice is ordered -------------------------------------------------------

# `one_of` keeps the first alternative that succeeds. "in" matches the start
# of "int", and leaves "t". Put the longer keyword first.
expect Parser.one_of([Parser.Utf8.string("in"), Parser.Utf8.string("int")]).run_str("int").map_ok(|r| r.rest) == Ok("t")
expect Parser.one_of([Parser.Utf8.string("int"), Parser.Utf8.string("in")]).parse_str("int") == Ok("int")

# --- Repetition --------------------------------------------------------------

numbers : Parser(Bytes, List(U64), _)
numbers = Parser.Utf8.digits({}).sep_by(Parser.Utf8.codeunit(','))

# `sep_by` rejects a trailing separator. `many` stops before the first element
# that fails and leaves its input, so `parse_str` then reports that element.
expect numbers.parse_str("1,2,").is_err()
expect Parser.Utf8.codeunit('a').many().run_str("aab").map_ok(|r| r.rest) == Ok("b")

# `digits` gives a `U64`, with no sign and no decimal point. Too many digits is
# `IntegerOverflow`, not a wrapped number.
expect Parser.Utf8.digits({}).parse_str("99999999999999999999").is_err()

# `codeunit` matches one byte. 'é' compiles as the byte 0xE9, but "é" is two
# bytes in UTF-8. Use `Parser.Utf8.string` for text outside ASCII.
expect Parser.Utf8.codeunit('é').parse_str("é").is_err()
expect Parser.Utf8.string("é").parse_str("é") == Ok("é")

# A long run of bytes: build a `ByteClass` once, at the top level, and scan
# with `span_class`. It is faster than `chomp_while`, and both may be empty.
word_char : Parser.Utf8.ByteClass
word_char = Parser.Utf8.ByteClass.from_predicate(|b| b != ' ' and b != '\n')

expect Parser.Utf8.span_class(word_char).run_str("hello world").map_ok(|r| r.rest) == Ok(" world")

# --- A step that depends on a value ------------------------------------------

# `and_then` builds the next parser from the value just read, such as a
# length prefix. Use `keep` when the next parser is fixed.
sized : Parser(Bytes, Str, _)
sized = Parser.Utf8.digits({}).skip(Parser.Utf8.codeunit(':')).and_then(|n| Parser.Utf8.rest({}).map(|b| Str.from_utf8_lossy(b.take_first(n))))

expect sized.parse_str("3:abc") == Ok("abc")

# --- A hand-written step -----------------------------------------------------

# `Parser.custom` gets the input and returns `{ value, rest }`, or a
# `ParseError` whose `InputOffset` counts into that input.
bit : Parser(Bytes, Bool, _)
bit = Parser.custom(
	|input| {
		match input {
			['0', .. as rest] => Ok({ value: False, rest })
			['1', .. as rest] => Ok({ value: True, rest })
			_ => Err(ParseError(Parser.Diagnostic.{ problem: ExpectedBit, location: InputOffset(0), path: [] }))
		}
	},
)

expect bit.many().parse_str("101") == Ok([True, False, True])

# --- Recursion ---------------------------------------------------------------

# A grammar that contains itself needs `Parser.lazy`, and the parser must be a
# function: a top-level value that refers to itself is a "circular value
# definition" error, even inside `lazy`. A recursive type must be nominal
# (`:=`), not an alias (`:`).
Tree := [Leaf(U64), Node(List(Tree))]

tree : {} -> Parser(Bytes, Tree, _)
tree = |{}|
	Parser.one_of([
		Parser.Utf8.digits({}).map(|n| Leaf(n)),
		Parser.lazy(|_| tree({}))
			.sep_by(Parser.Utf8.codeunit(','))
			.between(Parser.Utf8.codeunit('['), Parser.Utf8.codeunit(']'))
			.map(|children| Node(children)),
	])

expect tree({}).parse_str("[1,[2,3],[]]").is_ok()

# No left recursion: `diff = diff "-" num` overflows the stack. Read the
# first operand, then `many` more, and fold.
diff : Parser(Bytes, I64, _)
diff =
	Parser.const(|first| |others| others.fold(first.to_i64_wrap(), |acc, n| acc - n.to_i64_wrap()))
		.keep(Parser.Utf8.digits({}))
		.keep(Parser.const(|n| n).skip(Parser.Utf8.codeunit('-')).keep(Parser.Utf8.digits({})).many())

expect diff.parse_str("10-3-2") == Ok(5)

# --- Errors with a line number -----------------------------------------------

# `parse_str` already counts lines, so parse the whole text at once and read
# `line` and `column` from the location.
lines : Parser(Bytes, List(List(U64)), _)
lines = numbers.sep_by(Parser.Utf8.codeunit('\n'))

report : Str -> Str
report = |text|
	match lines.parse_str(text) {
		Ok(rows) => "${rows.len().to_str()} rows"
		Err(ParseError({ location: Text({ line, column, .. }), problem, .. })) => "line ${line.to_str()}, column ${column.to_str()}: ${Str.inspect(problem)}"
		Err(ParseError({ problem, .. })) => Str.inspect(problem)
	}

expect report("1,2\n3,x") == "line 2, column 3: ExpectedDigit"

main! = |_args| {
	Stdout.line!(report("1,2\n3,x"))
}
