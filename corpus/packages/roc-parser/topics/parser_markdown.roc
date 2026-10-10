## Markdown to your own output with lukewilliamboswell/roc-parser 2.0:
## `Markdown.parse_str` gives a list of blocks, and two functions that call each
## other (one for `Markdown` blocks, one for `Markdown.Inline`) walk the tree to
## HTML, a table of contents or plain text. A leading `---` block is frontmatter,
## and `Yaml.parse_str` reads it.
##
## The tree is CommonMark 0.31.2 plus the GFM tables, task lists, strikethrough
## and autolinks. It is a syntax tree, not HTML: your renderer decides the HTML.
##
## Full manual:
##
## - Blocks, inline content, reference links, frontmatter, walking the tree to
##   produce output, and conformance limits: https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/markdown.adoc
## - The YAML that frontmatter holds, decoded into a record or read as a tree:
##   https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/yaml.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst",
}

import pf.Stdout
import parser.Markdown
import parser.Yaml

# --- Parse -------------------------------------------------------------------
#
# Markdown has no syntax errors, so `Markdown.parse_str` returns
# `List(Markdown)` and not a `Try`. `Markdown.parse_str(text)?` does not compile.
# The type is `Markdown`, the same name as the module.

expect Markdown.parse_str("## Setup").first() == Ok(Heading({ level: Two, content: [Text("Setup")] }))

# A soft line break stays as "\n" inside `Text`. Only two trailing spaces or a
# backslash give `HardBreak`.
expect Markdown.parse_str("one\ntwo") == [Paragraph([Text("one\ntwo")])]

# Entities are decoded, so `Text` holds "<", not "&lt;". Escape what you emit.
expect Markdown.parse_inlines("1 &lt; 2") == [Text("1 < 2")]

# Raw HTML passes through as written. Drop or sanitise it for input you did not
# write: the parser does not filter tags or check `javascript:` links.
expect Markdown.parse_inlines("a <b>x</b>") == [Text("a "), HtmlInline("<b>"), Text("x"), HtmlInline("</b>")]

# A reference link resolves only with its definition in the same parse.
# `parse_inlines` sees one fragment, so the brackets stay text.
expect Markdown.parse_inlines("[docs][d]") == [Text("[docs][d]")]
expect
	Markdown.parse_str("[docs][d]\n\n[d]: /docs")
	== [Paragraph([Link({ label: [Text("docs")], target: { href: "/docs", title: Err(Missing) } })])]

# A tight list still wraps each item's text in `Paragraph`. Read `loose` to
# decide if the HTML gets `<p>` tags.
expect {
	match Markdown.parse_str("- a\n- b") {
		[ListBlock({ loose, items, .. })] => !loose and items.map(|item| item.blocks) == [[Paragraph([Text("a")])], [Paragraph([Text("b")])]]
		_ => False
	}
}

# --- Render ------------------------------------------------------------------

escape : Str -> Str
escape = |text| text.replace_each("&", "&amp;").replace_each("<", "&lt;").replace_each(">", "&gt;").replace_each("\"", "&quot;")

inlines_html : List(Markdown.Inline) -> Str
inlines_html = |inlines| Str.join_with(inlines.map(inline_html), "")

# Every variant is matched, or a `_` branch is needed: a match that leaves one
# out is a "non exhaustive match" error.
inline_html : Markdown.Inline -> Str
inline_html = |inline| {
	match inline {
		Text(text) => escape(text)
		Strong(children) => "<strong>${inlines_html(children)}</strong>"
		Emphasis(children) => "<em>${inlines_html(children)}</em>"
		Strikethrough(children) => "<del>${inlines_html(children)}</del>"
		InlineCode(code) => "<code>${escape(code)}</code>"
		# `title` is `Try(Str, [Missing])`. The href is not checked: escape it.
		Link({ label, target }) => "<a href=\"${escape(target.href)}\">${inlines_html(label)}</a>"
		Image({ alt, target }) => "<img src=\"${escape(target.href)}\" alt=\"${escape(plain(alt))}\" />"
		HardBreak => "<br />\n"
		# Untrusted input: drop it.
		HtmlInline(_) => ""
	}
}

blocks_html : List(Markdown) -> Str
blocks_html = |blocks| Str.join_with(blocks.map(block_html), "")

block_html : Markdown -> Str
block_html = |block| {
	match block {
		# `level` is `One` to `Six`. `to_str` gives "1" to "6".
		Heading({ level, content }) => "<h${level.to_str()}>${inlines_html(content)}</h${level.to_str()}>\n"
		Paragraph(inlines) => "<p>${inlines_html(inlines)}</p>\n"
		Blockquote(children) => "<blockquote>\n${blocks_html(children)}</blockquote>\n"
		ListBlock({ kind, loose, items }) => {
			tag =
				match kind {
					Unordered => "ul"
					Ordered(_) => "ol"
				}
			lis = items.map(
				|item| {
					inner =
						match item.blocks {
							[Paragraph(inlines)] if !loose => inlines_html(inlines)
							_ => blocks_html(item.blocks)
						}
					"<li>${inner}</li>\n"
				},
			)
			"<${tag}>\n${Str.join_with(lis, "")}</${tag}>\n"
		}

		# `pre` is the literal content and ends in a newline. `info` is the text
		# after the opening fence, empty for indented code.
		Code({ info, pre }) => "<pre><code class=\"language-${escape(info)}\">${escape(pre)}</code></pre>\n"
		ThematicBreak => "<hr />\n"
		# `Table`, `HtmlBlock` and `Frontmatter` are left out of this sketch.
		_ => ""
	}
}

plain : List(Markdown.Inline) -> Str
plain = |inlines| {
	pieces = inlines.map(
			|inline| {
				match inline {
					Text(text) | InlineCode(text) => text
					Strong(c) | Emphasis(c) | Strikethrough(c) => plain(c)
					Link({ label, .. }) => plain(label)
					Image({ alt, .. }) => plain(alt)
					HardBreak => " "
					HtmlInline(_) => ""
				}
			},
		)
	Str.join_with(pieces, "")
}

expect blocks_html(Markdown.parse_str("# A *b*\n\n- x\n- y")) == "<h1>A <em>b</em></h1>\n<ul>\n<li>x</li>\n<li>y</li>\n</ul>\n"

# --- Frontmatter -------------------------------------------------------------
#
# A first line of exactly `---` and a later `---` line give `Frontmatter(raw)`
# as the first block. `Markdown.frontmatter` returns that raw text, with its
# last newline, or `Err(Missing)`. It does not parse the text. Give the text to
# `Yaml.parse_str`.

post =
	\\---
	\\title: Hello
	\\---
	\\# Hello
	\\
	\\First **post**.

expect Markdown.frontmatter(Markdown.parse_str(post)) == Ok("title: Hello\n")

# With no closing `---`, the opening line is a thematic break.
expect Markdown.parse_str("---\nhi") == [ThematicBreak, Paragraph([Text("hi")])]

# `Yaml.parse_str` fails with `InvalidYaml(...)`, the lookups with `Missing` and
# `WrongType`. `?` passes each one up, so the error type is their union.
page : Str -> Try(Str, [InvalidYaml(Yaml.Error), Missing, WrongType])
page = |text| {
	blocks = Markdown.parse_str(text)
	title =
		match Markdown.frontmatter(blocks) {
			Ok(raw) => Yaml.parse_str(raw)?.get_path(["title"])?.as_str()?
			Err(Missing) => "untitled"
		}
	# The `Frontmatter` block stays in the list. `block_html` renders it as "".
	Ok("<title>${escape(title)}</title>\n${blocks_html(blocks)}")
}

expect page("Hi") == Ok("<title>untitled</title>\n<p>Hi</p>\n")
expect page(post) == Ok("<title>Hello</title>\n<h1>Hello</h1>\n<p>First <strong>post</strong>.</p>\n")

main! = |_args| {
	Stdout.line!(page(post)?)?
	Ok({})
}
