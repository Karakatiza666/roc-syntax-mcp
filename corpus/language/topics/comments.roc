# Comments and doc comments: `#`, `##`, Markdown, code blocks and autolinks in
# docs, `roc docs`, shebang lines, and the ban on bidirectional controls.
#
# A comment starts with `#` and ends at the end of the line. Roc has no block
# or multi-line comment syntax. The compiler gives a comment no meaning, so a
# change to a comment does not change what the program does.

answer = 42 # A comment can also end a line of code.

# A doc comment is a run of `##` lines just before a definition. `roc docs`
# shows it with the item. It works at the top level and inside a `.{ }` block,
# before the annotation or the assignment. The text is Markdown. `[Name]` or
# `[Type.item]` alone in brackets is an autolink to that item. It works for
# items of this module, of other modules in the package, and of the builtins.
# A Markdown link `[text](url)` stays an ordinary link.
Greeting :: { text : Str }.{
	## Converts a [Greeting] to a [Str]. To go the other way, use
	## [Greeting.from_str]. See [the tutorial](https://roc-lang.org/tutorial).
	##
	## ```roc
	## expect Greeting.from_str("hi").to_str() == "hi"
	## ```
	to_str : Greeting -> Str
	to_str = |greeting| greeting.text

	## Makes a [Greeting] from any text.
	from_str : Str -> Greeting
	from_str = |text| { text: text }
}

# The compiler does not check or run a code block in a doc comment. So `roc
# test` does not run the `expect` above. Write the example as a top-level
# `expect` too:
expect Greeting.from_str("hi").to_str() == "hi"

# `roc docs main.roc` builds an HTML site for a package or platform into
# ./generated-docs (`--output=<dir>` to change it, `--serve` to view it on
# http://localhost:8080). It has one page per exposed module, with the types
# and doc comments of its public items. A top-level helper of a type module is
# private, so its doc comment is not in the site.
#
# A shebang on line 1 is an ordinary comment to Roc, so a script with one
# still compiles, and a shell can run the file with it:
#
#   #!/usr/bin/env roc
#
# Comments and doc comments must not contain a literal Unicode bidirectional
# control, e.g. U+202E (RIGHT-TO-LEFT OVERRIDE). Such a character can make
# source look different from what Roc runs (CVE-2021-42574). The error is
# "bidirectional control in source". Write the code point as text, as here. A
# string literal can hold the control as the escape `\u(202E)`. Arabic and
# Hebrew text is allowed.
right_to_left_override = "\u(202E)"

expect right_to_left_override.count_utf8_bytes() == 3
