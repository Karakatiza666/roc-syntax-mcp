## Read an XML document with lukewilliamboswell/roc-parser 2.0: `Xml.parse_str`
## gives a tree, the `Xml.Node` helpers `children_named`, `attribute` and
## `text` find data in it, and a `match` on `Element` and `Text` does the rest.
##
## The parser checks that the document is well-formed XML 1.0. It does not
## validate against a schema or a DTD.
##
## Full manual: parsing and finding elements, what the tree contains, error
## reports, and what is not supported: https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/xml.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst",
}

import pf.Stdout
import parser.Utf8
import parser.Xml

# --- Parse, then walk --------------------------------------------------------
#
# `Xml.parse_str` returns `Try(Xml, [InvalidXml(Xml.Error)])`. The document
# element is `xml.root`, an `Xml.Node`. The declaration is `xml.declaration`.

feed_text =
	\\<?xml version="1.0" encoding="UTF-8"?>
	\\<feed lang="en">
	\\  <!-- newest first -->
	\\  <entry id="2"><title>Fish &amp; Chips</title></entry>
	\\  <entry><title><![CDATA[<Hello>]]></title></entry>
	\\</feed>

# `attribute` gives `Try(Str, [Missing])`, so `??` supplies a default.
# `children_named` gives only direct children, and only elements.
describe : Xml.Node -> Str
describe = |entry| {
	id = entry.attribute("id") ?? "?"
	titles = entry.children_named("title").map(|title| title.text())
	"${id}: ${Str.join_with(titles, "")}"
}

expect
	Xml.parse_str(feed_text).map_ok(|xml| xml.root.children_named("entry").map(describe))
	== Ok(["2: Fish & Chips", "?: <Hello>"])

expect Xml.parse_str("<a><b><c/></b></a>").map_ok(|xml| xml.root.children_named("c")) == Ok([])

expect Xml.parse_str("<a/>").map_ok(|xml| xml.declaration) == Ok(Err(Missing))

# --- The tree is a tag union -------------------------------------------------
#
# A node is `Element({ name, attributes, children })` or `Text(Str)`. There
# is no query language. Use a match for anything that the helpers do not do.

count_elements : Xml.Node -> U64
count_elements = |node| {
	match node {
		Element({ children, .. }) => 1 + children.map(count_elements).sum()
		Text(_) => 0
	}
}

expect Xml.parse_str("<a><b/><c><d/></c>x</a>").map_ok(|xml| count_elements(xml.root)) == Ok(4)

# The whitespace between elements stays in the tree as `Text` nodes. Here
# `<a>` has three children, not one. `children_named` skips them, but a loop
# over `children` and `text()` do not.
expect {
	xml = Xml.parse_str("<a>\n  <b>x</b>\n</a>")?
	match xml.root {
		Element({ children, .. }) => children.len() == 3 and xml.root.text() == "\n  x\n"
		Text(_) => False
	}
}

# --- What the parser changes -------------------------------------------------
#
# The tree is what an XML processor reports, not the source text:
# references become characters, CDATA becomes text, comments go away, and
# the text on both sides of them is merged into one `Text`. `\r\n` becomes
# `\n`. A tab or line break in an attribute value becomes a space.
expect
	Xml.parse_str("<p class='a\tb'>x &lt; y\r\n<![CDATA[<z>]]><!-- gone -->!</p>").map_ok(|xml| xml.root)
	== Ok(Element({ name: "p", attributes: [{ name: "class", value: "a b" }], children: [Text("x < y\n<z>!")] }))

# --- What it rejects ---------------------------------------------------------
#
# Only the 5 predefined entities exist. HTML entities such as `&nbsp;` are an
# error, so replace them with character references (`&#160;`) first.
expect Xml.parse_str("<a>&nbsp;</a>") == Err(InvalidXml({ line: 1, column: 4, message: "undeclared entity &nbsp;" }))
expect Xml.parse_str("<a>&#160;</a>").map_ok(|xml| xml.root.text()) == Ok("\u(a0)")

# A DOCTYPE is always rejected, even an empty one.
expect Xml.parse_str("<!DOCTYPE html><html/>") == Err(InvalidXml({ line: 1, column: 1, message: "document type declarations are not supported" }))

# No namespaces. A prefix is part of the name, and `xmlns` is an attribute.
expect
	Xml.parse_str("<svg:svg xmlns:svg='u'><svg:rect/></svg:svg>").map_ok(|xml| (xml.root.attribute("xmlns:svg"), xml.root.children_named("rect").len(), xml.root.children_named("svg:rect").len()))
	== Ok((Ok("u"), 0, 1))

# Lines and columns start at 1, and a column counts UTF-8 bytes, not
# characters. The `é` moves the column by 2.
expect Xml.parse_str("<a>e</b>") == Err(InvalidXml({ line: 1, column: 5, message: "end tag </b> does not match start tag <a>" }))
expect Xml.parse_str("<a>é</b>") == Err(InvalidXml({ line: 1, column: 6, message: "end tag </b> does not match start tag <a>" }))

# One root element. A second one is an error, not a list.
expect Xml.parse_str("<a/><b/>") == Err(InvalidXml({ line: 1, column: 5, message: "unexpected content after the root element" }))

# --- Inside a larger parser --------------------------------------------------
#
# `Xml.parser` is the same parser as a `Parser(Utf8.Bytes, Xml)`. It stops
# after the document, and leaves the rest for the next parser. Its error is
# `ParseError({ message, offset })` with a byte offset, not a line.
expect Utf8.parse_str_partial(Xml.parser, "<a/> <b/>").map_ok(|r| r.rest) == Ok("<b/>")

# `Utf8.parse_str` must consume all input, so the same text fails there.
expect Utf8.parse_str(Xml.parser, "<a/> <b/>") == Err(ParseError({ message: "unexpected input", offset: 5 }))

print_entries! : Str => Try({}, _)
print_entries! = |text| {
	match Xml.parse_str(text) {
		Ok(xml) =>
			for entry in xml.root.children_named("entry") {
				Stdout.line!(describe(entry))?
			}

		Err(InvalidXml({ line, column, message })) => Stdout.line!("${line.to_str()}:${column.to_str()}: ${message}")?
	}
	Ok({})
}

main! = |_args| print_entries!(feed_text)
