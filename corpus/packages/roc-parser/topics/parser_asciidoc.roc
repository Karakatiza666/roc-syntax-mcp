## Read AsciiDoc with the `AsciiDoc` module of lukewilliamboswell/roc-parser
## 3.0: `AsciiDoc.parse_str` into a title and blocks, `AsciiDoc.render` into an
## embedded HTML document, and `select_include` for the lines that an
## `include::` directive picks.
##
## It is pure Roc and never reads a file: supply include sources as a list
## and turn expansion on with `expand_includes: True`. Compatibility with
## Asciidoctor is tested but not complete, so check the manual's AsciiDoc chapter
## for what is covered before you rely on a feature.
##
## Full manual: blocks, rendering, preprocessing and includes, attributes, and
## what is unsupported:
## https://github.com/lukewilliamboswell/roc-parser/blob/3.0.0/docs/asciidoc.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/3.0.0/6xsRdRqenJrAb4wG7HaST4Xh349vD5sHAJDsKTK6E3dr.tar.zst",
}

import pf.Stdout
import parser.AsciiDoc

# --- Parse a document --------------------------------------------------------
#
# `AsciiDoc.parse_str` gives `Try(Document, [Unsupported(Error), InvalidAsciiDoc(Error)])`.
# A `Document` is `{ title, blocks }`. `Error` is `{ offset, line, message }`:
# a UTF-8 byte offset and a one-based line. `Unsupported` is a construct the
# parser knows and does not read. Match on both tags.
source = "= Guide\n\nIntroduction\n\n== Getting started\n\nHello\n"

describe : Str -> Str
describe = |text| {
	match AsciiDoc.parse_str(text) {
		Ok(document) => "${document.title}: ${document.blocks.len().to_str()} top-level blocks"
		Err(Unsupported(error)) => "Unsupported on line ${error.line.to_str()}: ${error.message}"
		Err(InvalidAsciiDoc(error)) => "Invalid on line ${error.line.to_str()}: ${error.message}"
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
	document = AsciiDoc.parse_str(source)?
	match document.blocks {
		[Paragraph("Introduction"), Section({ level: 1, title: "Getting started", blocks: [Paragraph("Hello")] })] => True
		_ => False
	}
}

# --- Render to HTML ----------------------------------------------------------
#
# `render` gives an embedded HTML document. `render_inline(text, attributes)`
# applies the inline substitutions alone, and takes the attributes to expand.
expect AsciiDoc.render_inline("*bold* and `code`", []) == "<strong>bold</strong> and <code>code</code>"
expect AsciiDoc.render_inline("{name} here", [{ name: "name", value: "Ada" }]) == "Ada here"
expect AsciiDoc.parse_str(source).map_ok(|document| AsciiDoc.render(document).contains("Getting started")) == Ok(True)

# --- Includes: supply the sources, enable expansion --------------------------
#
# By default an `include::` directive is not expanded. `parse_with` takes
# `Options`: `includes` (a list of `{ path, source }`), `attributes`,
# `max_depth` (16) and `expand_includes`. Start from `default_options`.
with_includes : AsciiDoc.Options
with_includes = { ..AsciiDoc.default_options, expand_includes: True, includes: [{ path: "intro.adoc", source: "Included text\n" }] }

expect {
	document = AsciiDoc.parse_with("= Doc\n\ninclude::intro.adoc[]\n", with_includes)?
	document.blocks == [Paragraph("Included text")]
}

# --- Choose the lines of an include ------------------------------------------
#
# `select_include(source, attributes)` applies `lines=`, `tag=`, `tags=` (with
# `*`, `**` and `!` negation) and `indent=` exactly as Asciidoctor 2.0.23 does,
# so a tool that expands includes itself need not copy the rules. It gives
# `{ text, lines, problems }`, where `lines` are the one-based source lines.
# Problems are `MissingTag`, `UnclosedTag`, `UnmatchedEnd`, `InvalidLines` and
# `EmptySelection` (a missing tag selects nothing, so it reports both). Asciidoctor warns only about the first three, so a strict
# caller can also reject the other two.
expect AsciiDoc.select_include("one\ntwo\nthree\n", "lines=2..3") == { text: "two\nthree", lines: [2, 3], problems: [] }
expect AsciiDoc.select_include("a\n// tag::x[]\nb\n", "tag=x").problems == [UnclosedTag("x")]
expect AsciiDoc.select_include("a\nb\n", "tag=nope").problems == [MissingTag("nope"), EmptySelection]

# `indent=0` removes the common indentation. A tab counts as one character.
tabbed = "\t// tag::x[]\n\tfn = |x|\n\n\t\tx\n\t// end::x[]\n"

expect AsciiDoc.select_include(tabbed, "tag=x,indent=0") == { text: "fn = |x|\n\n\tx", lines: [2, 3, 4], problems: [] }

# `tag=a;b` is one tag named `a;b`. Use `tags=a;b` for two.
expect AsciiDoc.select_include("// tag::a[]\n1\n// end::a[]\n// tag::b[]\n2\n// end::b[]\n", "tags=a;b").text == "1\n2"

# For a document that sets `tabsize`, `select_include_with` takes the context.
expect AsciiDoc.select_include_with("\t\tx\n\t  y", "indent=0", { tabsize: 4 }).text == "  x\ny"

strict : Str, Str -> Str
strict = |text, attributes| {
	selection = AsciiDoc.select_include(text, attributes)
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
