## HTML, SVG and MathML as checked Roc values with lukewilliamboswell/roc-parser
## 6.0: `Html.parse_str` and `parse_fragment` for runtime markup, a literal
## annotated `Html.Fragment` or `Svg.Fragment` checked while the program
## compiles, `Svg.Template(Str)` for a fixed template with `${...}` holes, and
## the shared `Markup.Tree` to walk the result.
##
## These modules parse and check. They render nothing: there is no HTML
## serializer and no `to_str`, and binding a template does not build a string.
## A consumer walks the tree (a DOM builder, a virtual DOM, a renderer of its
## own). For a page served as text, build the text with your own code. For
## plain XML, use `Xml` (the parser_xml topic).
##
## Full manual:
##
## - Documents and fragments, HTML against XML syntax, template holes,
##   validation, error handling, and the source tree:
##   https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/markup.adoc
## - Computed element and attribute names, and their vocabulary queries:
##   https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/dom-names.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import pf.Stdout
import parser.Html
import parser.Markup
import parser.Svg

# --- Runtime markup is strict by default -------------------------------------
#
# `Html.parse_str(text, {})` reads a whole document and
# `Html.parse_fragment(text, {})` the children of a `body`. Both return
# `Try(_, [InvalidMarkup(Markup.Error)])`. Strict means: no browser repair, and
# the authoring checks are on (known elements and attributes, content models,
# attribute values). A browser would accept every input below; this parser
# does not.
problem : Str -> Str
problem = |text|
	match Html.parse_fragment(text, {}) {
		Ok(_) => "ok"
		Err(InvalidMarkup({ problem: p, .. })) => Str.inspect(p)
	}

expect problem("<p>Hello <b>world</b></p>") == "ok"
expect problem("<div><span></div>") == "HtmlSyntax(MisnestedEndTag)"
expect problem("<blink>old</blink>") == "UnknownElement(\"blink\")"
expect problem("<input type=\"nope\">").starts_with("InvalidValue(")

# Optional end tags that the HTML standard allows are fine in strict mode.
expect problem("<ul><li>one<li>two</ul>") == "ok"

# For markup from the web, turn on what a browser does, one prop at a time:
# `recovery: Browser` repairs the tree and keeps what it repaired in
# `parsed.diagnostics`. An unknown element still needs its own prop.
lenient : Html.Props
lenient = { recovery: Browser, allow_unknown_elements: True, allow_unknown_attributes: True }

expect
	match Html.parse_fragment("<div><span></div><blink>x</blink>", lenient) {
		Ok(fragment) => !fragment.parsed.diagnostics.is_empty()
		Err(_) => False
	}

# --- Walk the tree -----------------------------------------------------------
#
# A parsed value holds `parsed : { source, tree, diagnostics }`. The tree is
# flat: `tree.nodes` is a list, `tree.roots` and each node's `children` are
# indexes into it. A node's `kind` is `Element(name)`, `Text(str)`, `Comment`,
# `Doctype` or `ProcessingInstruction`. An element name is a record of
# `namespace`, `local` and `prefix`, not a `Str`. Entities are decoded.
links : Str -> Try(List(Str), [InvalidMarkup(Markup.Error)])
links = |text| {
	fragment = Html.parse_fragment(text, {})?
	tree = fragment.parsed.tree
	hrefs = tree.nodes.keep_oks(
		|node|
			match node.kind {
				Element({ local: "a", .. }) =>
					node.attributes
						.find_first(|attr| attr.name.local == "href")
						.map_ok(|attr| attr.value)

				_ => Err(NotALink)
			},
	)
	Ok(hrefs)
}

expect links("<p>See <a href=\"/docs?a=1&amp;b=2\">docs</a> and <a href=\"/faq\">FAQ</a>.</p>") == Ok(["/docs?a=1&b=2", "/faq"])

# `tree.single_root()` is the one element root, and `tree.text(index)` its
# text, children included.
expect
	Html.parse_fragment("<p>Hello <b>world</b></p>", {}).map_ok(|f| f.parsed.tree.single_root().map_ok(|root| f.parsed.tree.text(root)))
	== Ok(Ok("Hello world"))

# --- Literals are checked while the program compiles -------------------------
#
# Annotate a string with `Html.Fragment`, `Html`, `Svg.Fragment`, `Svg`,
# `MathML.Fragment` or `MathML`, and the compiler parses it with the strict
# defaults. A mistake is an "invalid string" compile error such as
# `<literal>:1:12: HTML: HtmlSyntax(MisnestedEndTag)`.
panel : Html.Fragment
panel = "<section hidden='until-found'><p>Find this panel</p></section>"

# An `Svg.Fragment` starts with the SVG namespace in scope, so a lone `<path>`
# needs no `<svg xmlns=...>` around it. The path data is checked too.
arrow : Svg.Fragment
arrow = "<path d='M0 0L10 10'/>"

expect panel.single_element().is_ok()
expect arrow.single_element().map_ok(|node| node.kind == Element({ namespace: Uri("http://www.w3.org/2000/svg"), local: "path", prefix: Unprefixed })) == Ok(True)

# --- Templates: typed holes, never markup ------------------------------------
#
# A string with `${...}` annotated `Svg.Template(a)` (or `Html.Template(a)`) is
# parsed once, during compilation, with holes where the values go. A hole may
# be text or a whole quoted attribute value, and not a tag or attribute name.
# The values are kept apart from the markup and are never parsed, so a value
# that looks like a tag stays text. All holes have the one type `a`.
cx = "42"

caption = "<path/> stays text"

drawing : Svg.Template(Str)
drawing =
	\\<svg viewBox="0 0 100 100">
	\\  <circle cx="${cx}" cy="50" r="4" />
	\\  <text>${caption}</text>
	\\</svg>

# `drawing.bound.metadata()` gives the `values` and the `plan`; the plan's
# `metadata()` gives the parsed tree and the `slots`, each a node (and
# attribute) index with the index of its value. A consumer puts each value at
# its slot while it walks the tree.
expect drawing.bound.metadata().values == ["42", "<path/> stays text"]

slots : Markup.Template.Bound(Str) -> List(Markup.Template.Slot)
slots = |bound| bound.metadata().plan.metadata().slots

expect slots(drawing.bound).len() == 2

main! = |_args| {
	Stdout.line!(problem("<div><span></div>"))?
	Stdout.line!(Str.inspect(links("<a href=\"/faq\">FAQ</a>")))
}
