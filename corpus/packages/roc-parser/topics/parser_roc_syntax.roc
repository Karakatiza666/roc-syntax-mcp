## Roc source as tokens, a syntax tree and diagnostics, with the `RocSyntax`
## module of lukewilliamboswell/roc-parser 3.0: `RocSyntax.parse_str`,
## `tokenize_str` and `highlight_category` for a highlighter, `parse_expr_str`
## for one expression, and `validate` to check a file during compilation.
##
## It is for highlighters, linters and other source tools. It reads syntax
## only: no name resolution and no types, so a file that parses can still fail
## `roc check`. It follows the syntax of the current compiler (the manual names
## the compiler commit), so expect follow-up releases as the language changes.
## Roc's legacy Rust-compiler syntax is out of scope.
##
## Full manual: tokens, byte spans, trees, highlighting, lint rules, and how the
## parser is checked against the compiler:
## https://github.com/lukewilliamboswell/roc-parser/blob/3.0.0/docs/roc-syntax.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/3.0.0/6xsRdRqenJrAb4wG7HaST4Xh349vD5sHAJDsKTK6E3dr.tar.zst",
}

import pf.Stdout
import parser.RocSyntax

# --- Parse, then read the tokens ---------------------------------------------
#
# `parse_str` never fails. It returns `RocSyntax.Parsed`: `source` (bytes),
# `tokens`, `nodes`, `children`, `diagnostics`, `status`, `root` and `consumed`.
# Check `status` before you trust the tree: `Complete`, `Recovered`,
# `Unsupported` or `Limited`.
#
# A token or node spans `start` to `end` in UTF-8 bytes, `end` excluded, so slice it from
# `source`. Whitespace and comments are tokens too, so the tokens cover the
# whole input.

text_of : RocSyntax.Parsed, RocSyntax.Token -> Str
text_of = |parsed, token| Str.from_utf8(parsed.source.sublist({ start: token.start, len: token.end - token.start })) ?? ""

numbers : Str -> List(Str)
numbers = |source| {
	parsed = RocSyntax.parse_str(source)
	parsed.tokens.keep_if(|token| token.kind == Number).map(|token| text_of(parsed, token))
}

expect numbers("answer = 1 + 2 * 3\n") == ["1", "2", "3"]
expect RocSyntax.parse_str("answer = 1\n").status == Complete

# --- Malformed input still gives tokens --------------------------------------
#
# The parser recovers: you get the structure it could read, `diagnostics`
# with a code and a byte span, and `Recovered` as the status. That is what an
# editor needs while someone types.
expect {
	parsed = RocSyntax.parse_str("x = (1 + \n")
	parsed.status != Complete and !parsed.diagnostics.is_empty() and !parsed.tokens.is_empty()
}

# Invalid UTF-8 is kept as bytes, not dropped.
expect !RocSyntax.parse_bytes([0xFF, 0x0A]).diagnostics.is_empty()

# --- The tree is flat --------------------------------------------------------
#
# A node is `{ kind, start, end, children_start, children_len }`. Its children
# are `children_len` entries of `parsed.children` from `children_start`, and
# each entry is an index into `parsed.nodes`. Do not assume that adjacent
# nodes are siblings. `root` is the index of the file node.
child_kinds : RocSyntax.Parsed, RocSyntax.Node -> List(RocSyntax.NodeKind)
child_kinds = |parsed, node| {
	parsed.children
		.sublist({ start: node.children_start, len: node.children_len })
		.map(|index| (parsed.nodes.get(index) ?? node).kind)
}

expect {
	parsed = RocSyntax.parse_str("answer = 1\nname = \"x\"\n")
	root = parsed.nodes.get(parsed.root) ?? crash "no root"
	root.kind == File and child_kinds(parsed, root).len() == 2
}

# --- One expression, one statement, one header -------------------------------
#
# `parse_expr_str` also reports extra significant tokens as a diagnostic.
# `parse_statement_str` and `parse_header_str` exist too, each with a `_bytes`
# or `_str` form for the input type.
expect RocSyntax.parse_expr_str("1 + 2 * 3").status == Complete
expect RocSyntax.parse_expr_str("1 + 2 3").status != Complete

# --- Highlighting without a tree ---------------------------------------------
#
# `tokenize_str` and `tokenize_bytes` give `{ source, tokens, diagnostics,
# status }` without building a tree. `highlight_category` maps a token kind to
# `Trivia`, `CommentText`, `Name`, `TypeName`, `ReservedWord`, `NumericLiteral`,
# `StringText`, `Symbol` or `InvalidText`. It picks no colors, so one result
# serves an HTML, a PDF and a terminal writer.
categories : Str -> List(RocSyntax.HighlightCategory)
categories = |source| {
	tokenized = RocSyntax.tokenize_str(source)
	tokenized.tokens
		.map(|token| RocSyntax.highlight_category(token.kind))
		.keep_if(|category| category != Trivia)
}

expect categories("x = 1 # note") == [Name, Symbol, NumericLiteral, CommentText]

# The tokens give back the input exactly, so a highlighter can wrap pieces
# without changing the text.
expect {
	source = "# hi\nf = |x| x + 1\n"
	tokenized = RocSyntax.tokenize_str(source)
	tokenized.tokens.fold([], |bytes, token| bytes.concat(tokenized.source.sublist({ start: token.start, len: token.end - token.start }))) == source.to_utf8()
}

# --- Check a file during compilation -----------------------------------------
#
# `validate` returns `Try(Parsed, [BadQuotedBytes(Str)])`. It rejects recovery,
# unsupported syntax, limits and unread input, and by default the `...`
# placeholder expression (`lints: { placeholders: False }` allows it). It
# checks syntax only. The compile-time use is in the parser_compile_time topic.
expect RocSyntax.validate({ source: "answer = 1\n" }).is_ok()
expect RocSyntax.validate({ source: "answer = (1 +\n", name: "bad.roc" }).is_err()
expect RocSyntax.validate({ source: "todo = ...\n" }).is_err()
expect RocSyntax.validate({ source: "todo = ...\n", lints: { placeholders: False } }).is_ok()

report! : Str => Try({}, _)
report! = |source| {
	parsed = RocSyntax.parse_str(source)
	Stdout.line!("status: ${Str.inspect(parsed.status)}")?
	Stdout.line!("diagnostics: ${parsed.diagnostics.len().to_str()}")?
	for number in numbers(source) {
		Stdout.line!("number ${number}")?
	}
	Ok({})
}

main! = |_args| report!("answer = 1 + 2 * 3\n")
