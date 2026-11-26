## Read an XML document with lukewilliamboswell/roc-parser 6.0:
## `Xml.parse_str(text, props)` gives a tree, the `Xml.Node` helpers
## `children_named`, `attribute` and `text` find data in it, and a `match` on
## `Element` and `Text` does the rest. `Xml.Namespaced` resolves namespaces,
## `limits` bounds an untrusted document, and `Xml.reader` reads one element
## at a time.
##
## The parser checks that the document is well-formed XML 1.0. It does not
## validate against a schema or a DTD. HTML, SVG and MathML are in their own
## modules (the parser_markup topic). An `Xml` literal is checked at build
## time (parser_compile_time). An XML file too large for memory is read with
## `Xml.decoder` (parser_streaming).
##
## Full manual: parsing and finding elements, what the tree contains,
## namespaces, the pull reader, limits, error reports, and what is not
## supported: https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/xml.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import pf.Stdout
import parser.Xml

# --- Parse, then walk --------------------------------------------------------
#
# `Xml.parse_str(text, {})` returns `Try(Xml, [InvalidXml(Xml.Error)])`. The
# props argument is required. The document element is `xml.root`, an
# `Xml.Node`. The declaration is `xml.declaration`.

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
	Xml.parse_str(feed_text, {}).map_ok(|xml| xml.root.children_named("entry").map(describe))
	== Ok(["2: Fish & Chips", "?: <Hello>"])

expect Xml.parse_str("<a><b><c/></b></a>", {}).map_ok(|xml| xml.root.children_named("c")) == Ok([])

expect Xml.parse_str("<a/>", {}).map_ok(|xml| xml.declaration) == Ok(Err(Missing))

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

expect Xml.parse_str("<a><b/><c><d/></c>x</a>", {}).map_ok(|xml| count_elements(xml.root)) == Ok(4)

# The whitespace between elements stays in the tree as `Text` nodes. Here
# `<a>` has three children, not one. `children_named` skips them, but a loop
# over `children` and `text()` do not.
expect {
	xml = Xml.parse_str("<a>\n  <b>x</b>\n</a>", {})?
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
	Xml.parse_str("<p class='a\tb'>x &lt; y\r\n<![CDATA[<z>]]><!-- gone -->!</p>", {}).map_ok(|xml| xml.root)
	== Ok(Element({ name: "p", attributes: [{ name: "class", value: "a b" }], children: [Text("x < y\n<z>!")] }))

# --- Errors are typed --------------------------------------------------------
#
# `Xml.Error` is `{ problem, location, path }`. Match the problem tag. The
# location is `Text({ offset, line, column })`. Lines and columns start at 1,
# and a column counts UTF-8 bytes, not characters.
check : Str -> Str
check = |text|
	match Xml.parse_str(text, {}) {
		Ok(_) => "well-formed"
		Err(InvalidXml({ problem, location: Text({ line, column, .. }), .. })) => "${line.to_str()}:${column.to_str()}: ${Str.inspect(problem)}"
		Err(InvalidXml({ problem, .. })) => Str.inspect(problem)
	}

expect check("<a>é</b>") == "1:6: EndTagMismatch({ actual: \"b\", expected: \"a\" })"

# Only the 5 predefined entities exist. HTML entities such as `&nbsp;` are an
# error, so replace them with character references (`&#160;`) first.
expect check("<a>&nbsp;</a>") == "1:4: UnknownEntity(\"nbsp\")"
expect Xml.parse_str("<a>&#160;</a>", {}).map_ok(|xml| xml.root.text()) == Ok("\u(a0)")

# A DOCTYPE is always rejected, even an empty one.
expect check("<!DOCTYPE html><html/>") == "1:1: DoctypeUnsupported"

# One root element. A second one is an error, not a list.
expect check("<a/><b/>") == "1:5: TrailingContent"

# --- Namespaces --------------------------------------------------------------
#
# In `Xml.parse_str` a prefix is part of the name, and `xmlns` is an attribute.
expect
	Xml.parse_str("<svg:svg xmlns:svg='u'><svg:rect/></svg:svg>", {}).map_ok(|xml| (xml.root.attribute("xmlns:svg"), xml.root.children_named("rect").len(), xml.root.children_named("svg:rect").len()))
	== Ok((Ok("u"), 0, 1))

# `Xml.Namespaced.parse_str` resolves them. Its `children_named` takes the
# namespace and the local name, so the prefix the author chose does not
# matter. An undeclared prefix is `InvalidNamespace`, a second error tag.
atom : Xml.Namespaced.Namespace
atom = Uri("http://www.w3.org/2005/Atom")

atom_titles : Str -> Try(List(Str), _)
atom_titles = |text| {
	doc = Xml.Namespaced.parse_str(text, {})?
	Ok(doc.root.children_named(atom, "title").map(|title| title.text()))
}

expect atom_titles("<feed xmlns='http://www.w3.org/2005/Atom'><title>News</title></feed>") == Ok(["News"])
expect atom_titles("<a:feed xmlns:a='http://www.w3.org/2005/Atom'><a:title>News</a:title></a:feed>") == Ok(["News"])
expect atom_titles("<feed><x:title/></feed>").is_err()

# --- An untrusted document ---------------------------------------------------
#
# Without limits, any depth and size is accepted. `limits: Bounded(...)` fails
# with `LimitExceeded` at the tag that goes over.
bounded : Str -> Str
bounded = |text|
	match Xml.parse_str(text, { limits: Bounded({ max_depth: 3, max_elements: 100 }) }) {
		Ok(_) => "accepted"
		Err(InvalidXml({ problem: LimitExceeded({ resource, max, .. }), .. })) => "more than ${max.to_str()} (${Str.inspect(resource)})"
		Err(InvalidXml({ problem, .. })) => Str.inspect(problem)
	}

expect bounded("<a><b><c/></b></a>") == "accepted"
expect bounded("<a><b><c><d/></c></b></a>") == "more than 3 (Depth)"

# --- One element at a time ---------------------------------------------------
#
# `Xml.reader(text, props)` is a pull reader: `next()` gives
# `Event(event, reader)`, `Done` or `Failed(error)`. At a `Start` event,
# `element()` reads that whole element as a tree and returns the reader after
# it, so only one entry is ever a tree. Keep the newest reader in a `var`.
entry_titles : Str -> Try(List(Str), Xml.ReadError)
entry_titles = |text| {
	var $reader = Xml.reader(text, {})?
	var $titles = []
	while True {
		match $reader.next() {
			Event(Start({ name: "entry", .. }), at_entry) =>
				match at_entry.element() {
					Element(entry, after) => {
						$titles = $titles.concat(entry.children_named("title").map(|title| title.text()))
						$reader = after
					}

					Failed(error) => return Err(error)
					NotAfterStart => return Ok($titles)
				}

			Event(_, rest) => {
				$reader = rest
			}

			Done => return Ok($titles)
			Failed(error) => return Err(error)
		}
	}
}

expect entry_titles("<feed><entry><title>One</title></entry><entry><title>Two</title></entry></feed>") == Ok(["One", "Two"])

# --- Inside a larger parser --------------------------------------------------
#
# `Xml.parser({})` is the same parser as a `Parser(Parser.Utf8.Bytes, Xml, _)`.
# `run_str` stops after the document and leaves the rest for the next parser.
expect Xml.parser({}).run_str("<a/> <b/>").map_ok(|r| r.rest) == Ok("<b/>")

# `parse_str` must consume all input, so the same text fails there.
expect Xml.parser({}).parse_str("<a/> <b/>").is_err()

print_entries! : Str => Try({}, _)
print_entries! = |text| {
	match Xml.parse_str(text, {}) {
		Ok(xml) =>
			for entry in xml.root.children_named("entry") {
				Stdout.line!(describe(entry))?
			}

		Err(InvalidXml({ problem, location, .. })) => Stdout.line!("${Str.inspect(location)}: ${Str.inspect(problem)}")?
	}
	Ok({})
}

main! = |_args| print_entries!(feed_text)
