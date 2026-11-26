## Read AsciiDoc with the `AsciiDoc` module of lukewilliamboswell/roc-parser
## 6.0: `AsciiDoc.parse_str(text, props)` into a title and blocks,
## `document.render_html()` into an embedded HTML document, and
## `select_include` for the lines that an `include::` directive picks.
##
## It is pure Roc and never reads a file: supply include sources in the props
## and turn expansion on with `expand_includes: True`. Compatibility with
## Asciidoctor is tested but not complete, so check the manual's AsciiDoc chapter
## for what is covered before you rely on a feature.
##
## Full manual: blocks, rendering, preprocessing and includes, attributes, and
## what is unsupported:
## https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/asciidoc.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import pf.Stdout
import parser.AsciiDoc

# --- Parse a document --------------------------------------------------------
#
# `AsciiDoc.parse_str(text, {})` gives
# `Try(AsciiDoc, [Unsupported(AsciiDoc.Error), InvalidAsciiDoc(AsciiDoc.Error)])`.
# The document type is `AsciiDoc` itself, `{ title, blocks }`; there is no
# `AsciiDoc.Document`. `Error` is `Parser.Diagnostic(problem)`: a `problem`
# tag, a `location` and a `path`. `Unsupported` is a construct the parser
# knows and does not read. Match on both tags.
source = "= Guide\n\nIntroduction\n\n== Getting started\n\nHello\n"

describe : Str -> Str
describe = |text| {
	match AsciiDoc.parse_str(text, {}) {
		Ok(document) => "${document.title}: ${document.blocks.len().to_str()} top-level blocks"
		Err(Unsupported(error)) => "Unsupported at ${Str.inspect(error.location)}: ${Str.inspect(error.problem)}"
		Err(InvalidAsciiDoc(error)) => "Invalid at ${Str.inspect(error.location)}: ${Str.inspect(error.problem)}"
	}
}

expect describe(source) == "Guide: 2 top-level blocks"

# --- The block tree ----------------------------------------------------------
#
# A `Block` is `Paragraph(Str)`, `Section({ level, title, blocks })`,
# `Listing(Str)`, `Literal(Str)`, `ThematicBreak`, or `Rich({ context, source,
# title, style, id, attrs, blocks, level })` for everything that carries
# metadata or nests (lists, tables, admonitions, delimited blocks). Sections
# hold the blocks beneath them, so the introduction above is a `Paragraph`
# and the second block is a `Section`.
expect {
	document = AsciiDoc.parse_str(source, {})?
	match document.blocks {
		[Paragraph("Introduction"), Section({ level: 1, title: "Getting started", blocks: [Paragraph("Hello")] })] => True
		_ => False
	}
}

# --- Render to HTML ----------------------------------------------------------
#
# `document.render_html()` gives an embedded HTML document; there is no
# `AsciiDoc.render`. `render_inline(text, attributes)` applies the inline
# substitutions alone, and takes the attributes to expand.
expect AsciiDoc.render_inline("*bold* and `code`", []) == "<strong>bold</strong> and <code>code</code>"
expect AsciiDoc.render_inline("{name} here", [{ name: "name", value: "Ada" }]) == "Ada here"
expect AsciiDoc.parse_str(source, {}).map_ok(|document| document.render_html().contains("Getting started")) == Ok(True)

# --- Includes: supply the sources, enable expansion --------------------------
#
# By default an `include::` directive is not expanded. The props of
# `parse_str` are `includes` (a list of `{ path, source }`), `attributes`,
# `max_depth` (16) and `expand_includes`; leave out the ones you do not set.
# There is no `parse_with`, `Options` or `default_options`.
with_includes : AsciiDoc.Props
with_includes = { expand_includes: True, includes: [{ path: "intro.adoc", source: "Included text\n" }] }

expect {
	document = AsciiDoc.parse_str("= Doc\n\ninclude::intro.adoc[]\n", with_includes)?
	document.blocks == [Paragraph("Included text")]
}

# --- Choose the lines of an include ------------------------------------------
#
# `select_include(source, attributes, props)` applies `lines=`, `tag=`, `tags=` (with
# `*`, `**` and `!` negation) and `indent=` exactly as Asciidoctor 2.0.23 does,
# so a tool that expands includes itself need not copy the rules. It gives
# `{ text, lines, problems }`, where `lines` are the one-based source lines.
# Problems are `MissingTag`, `UnclosedTag`, `UnmatchedEnd`, `InvalidLines` and
# `EmptySelection` (a missing tag selects nothing, so it reports both). Asciidoctor warns only about the first three, so a strict
# caller can also reject the other two.
expect AsciiDoc.select_include("one\ntwo\nthree\n", "lines=2..3", {}) == { text: "two\nthree", lines: [2, 3], problems: [] }
expect AsciiDoc.select_include("a\n// tag::x[]\nb\n", "tag=x", {}).problems == [UnclosedTag("x")]
expect AsciiDoc.select_include("a\nb\n", "tag=nope", {}).problems == [MissingTag("nope"), EmptySelection]

# `indent=0` removes the common indentation. A tab counts as one character.
tabbed = "\t// tag::x[]\n\tfn = |x|\n\n\t\tx\n\t// end::x[]\n"

expect AsciiDoc.select_include(tabbed, "tag=x,indent=0", {}) == { text: "fn = |x|\n\n\tx", lines: [2, 3, 4], problems: [] }

# `tag=a;b` is one tag named `a;b`. Use `tags=a;b` for two.
expect AsciiDoc.select_include("// tag::a[]\n1\n// end::a[]\n// tag::b[]\n2\n// end::b[]\n", "tags=a;b", {}).text == "1\n2"

# For a document that sets `tabsize`, pass it in the props.
expect AsciiDoc.select_include("\t\tx\n\t  y", "indent=0", { tabsize: 4 }).text == "  x\ny"

strict : Str, Str -> Str
strict = |text, attributes| {
	selection = AsciiDoc.select_include(text, attributes, {})
	if selection.problems.is_empty() {
		"${attributes} selects lines ${Str.inspect(selection.lines)}"
	} else {
		"${attributes} is rejected"
	}
}

expect strict("a\nb\nc\n", "lines=1..2") == "lines=1..2 selects lines [1, 2]"
expect strict("a\nb\nc\n", "tag=missing") == "tag=missing is rejected"

main! = |_args| {
	Stdout.line!(describe(source))?
	Stdout.line!(strict("a\nb\nc\n", "lines=2..3"))
}
