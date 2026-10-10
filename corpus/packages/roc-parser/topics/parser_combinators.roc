## A parser for your own text format, from lukewilliamboswell/roc-parser 2.0
## combinators, when no module parses the format. JSON is `Json.parse` in the
## standard library. The formats this package ships are in parser_csv,
## parser_yaml, parser_xml, parser_markdown and parser_http.
##
## Full manual:
##
## - A first parser, step by step, from one key to every line with errors:
##   https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/combinator-primer.adoc
## - Every combinator by task: running, sequencing, alternatives, repetition,
##   recursion, bytes against characters, and input that is not text:
##   https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/combinators.adoc
## - A format of your own, from the result types to a tested parser, line-based
##   or not: https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/custom-format.adoc
## - Error reports for each format and for your own parsers, with the location:
##   https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/errors.adoc
## - Speed and memory, why the package is fast or slow, and tips for your own
##   parsers: https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/performance.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst",
}

import pf.Stdout
import parser.Parser
import parser.Utf8

# --- Pieces ---

# Parsers read bytes (`Utf8.Bytes` is `List(U8)`), not characters. Build a
# `ByteClass` once, at the top level, for `span_class` to scan with. A span
# can be empty: validate with `map` to a `Try(_, Str)`, then `flatten`.
name_char : Utf8.ByteClass
name_char = Utf8.ByteClass.from_predicate(|b| (b >= 'a' and b <= 'z') or b == '_')

name : Parser(Utf8.Bytes, Str)
name =
	Utf8.span_class(name_char)
		.map(|bytes| if bytes.is_empty() Err("expected a name") else Ok(Str.from_utf8_lossy(bytes)))
		.flatten()

expect Utf8.parse_str(name, "") == Err(ParseError({ message: "expected a name", offset: 0 }))

# --- Sequencing ---

# `const` holds a curried constructor, one argument per `keep`: write
# `|key| |found| ...`, because `|key, found| ...` is a type mismatch on
# `keep`. `skip` runs a parser and drops its value.
Value : [Num(U64), Text(Str), Flag]

value : Parser(Utf8.Bytes, Value)
value = Parser.one_of([Utf8.digits.map(|n| Num(n)), name.map(|s| Text(s))])

# `maybe` gives `Try(a, [Missing])`, so `??` gives the default.
setting : Parser(Utf8.Bytes, { key : Str, value : Value })
setting =
	Parser.const(|key| |found| { key, value: found ?? Flag })
		.keep(name)
		.keep(Parser.const(|v| v).skip(Utf8.codeunit('=')).keep(value).maybe())

settings : Parser(Utf8.Bytes, List({ key : Str, value : Value }))
settings = setting.sep_by(Utf8.string("; "))

expect Utf8.parse_str(settings, "os=mac; port=80; v") == Ok([{ key: "os", value: Text("mac") }, { key: "port", value: Num(80) }, { key: "v", value: Flag }])

# --- Choice is ordered ---

# `one_of` keeps the first alternative that succeeds. "in" matches the
# start of "int", and the leftover "t" fails the parse. Put the longer keyword first.
expect Utf8.parse_str(Parser.one_of([Utf8.string("in"), Utf8.string("int")]), "int").is_err()
expect Utf8.parse_str(Parser.one_of([Utf8.string("int"), Utf8.string("in")]), "int") == Ok("int")

# --- Repetition ---

numbers : Parser(Utf8.Bytes, List(U64))
numbers = Utf8.digits.sep_by(Utf8.codeunit(','))

# `sep_by` rejects a trailing separator. `many` stops at the first element
# that fails, and the parse reports that failure.
expect Utf8.parse_str(numbers, "1,2,").is_err()
expect Utf8.parse_str(Utf8.codeunit('a').many(), "aab") == Err(ParseError({ message: "expected char `a`", offset: 2 }))

# --- The whole input, or a prefix ---

# `parse_str` must consume all the input. The one error tag is
# `ParseError({ message, offset })`, with `offset` in bytes.
# `parse_str_partial` parses a prefix and gives `{ value, rest }`.
expect Utf8.parse_str(Utf8.digits, "12x") == Err(ParseError({ message: "unexpected input", offset: 2 }))
expect Utf8.parse_str_partial(Utf8.digits, "12x") == Ok({ value: 12, rest: "x" })

# `digits` gives a `U64`, with no sign and no decimal point.
expect Utf8.parse_str(Utf8.digits, "99999999999999999999").is_err()

# `codeunit` matches one byte. 'é' compiles as the byte 0xE9, but "é" is two
# bytes in UTF-8. Use `Utf8.string` for text outside ASCII.
expect Utf8.parse_str(Utf8.codeunit('é'), "é").is_err()
expect Utf8.parse_str(Utf8.string("é"), "é") == Ok("é")

# --- A step that depends on a value ---

# `and_then` builds the next parser from the value just read, such as a
# length prefix. Use `keep` when the next parser is fixed.
sized : Parser(Utf8.Bytes, Str)
sized = Utf8.digits.skip(Utf8.codeunit(':')).and_then(|n| Utf8.rest.map(|b| Str.from_utf8_lossy(b.take_first(n))))

expect Utf8.parse_str(sized, "3:abc") == Ok("abc")

# --- A hand-written step ---

# `Parser.custom` gets the input and returns `{ value, rest }`, or a
# `ParseError` whose offset counts into that input.
bit : Parser(Utf8.Bytes, Bool)
bit = Parser.custom(
	|input| {
		match input {
			['0', .. as rest] => Ok({ value: False, rest })
			['1', .. as rest] => Ok({ value: True, rest })
			_ => Err(ParseError({ message: "expected a bit", offset: 0 }))
		}
	},
)

expect Utf8.parse_str(bit.many(), "101") == Ok([True, False, True])

# --- Recursion ---

# A grammar that contains itself needs `Parser.lazy`. A recursive type must
# be nominal (`:=`), not an alias (`:`).
Tree := [Leaf(U64), Node(List(Tree))]

tree : Parser(Utf8.Bytes, Tree)
tree = Parser.one_of([
	Utf8.digits.map(|n| Leaf(n)),
	Parser.lazy(|_| tree)
		.sep_by(Utf8.codeunit(','))
		.between(Utf8.codeunit('['), Utf8.codeunit(']'))
		.map(|children| Node(children)),
])

expect Utf8.parse_str(tree, "[1,[2,3],[]]").is_ok()

# No left recursion: `diff = diff "-" num` overflows the stack. Read the
# first operand, then `many` more, and fold.
diff : Parser(Utf8.Bytes, I64)
diff =
	Parser.const(|first| |others| others.fold(first.to_i64_wrap(), |acc, n| acc - n.to_i64_wrap()))
		.keep(Utf8.digits)
		.keep(Parser.const(|n| n).skip(Utf8.codeunit('-')).keep(Utf8.digits).many())

expect Utf8.parse_str(diff, "10-3-2") == Ok(5)

# --- Errors with a line number ---

# Parse a line-based format line by line, and count lines.
parse_lines : Str -> Try(List(List(U64)), Str)
parse_lines = |text| {
	var $rows = []
	var $line = 1.U64
	for row in text.split_on("\n") {
		match Utf8.parse_str(numbers, row) {
			Ok(nums) => { $rows = $rows.append(nums) }
			Err(ParseError({ message, offset })) => return Err("line ${$line.to_str()}, column ${(offset + 1).to_str()}: ${message}")
		}
		$line = $line + 1
	}
	Ok($rows)
}

expect parse_lines("1,2\n3,x") == Err("line 2, column 3: Not a digit")

main! = |_args| {
	Stdout.line!(Str.inspect(parse_lines("1,2\n3,x")))
}
