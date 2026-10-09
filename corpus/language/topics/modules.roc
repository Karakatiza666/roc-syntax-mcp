# Modules: type modules, what they hide, nested types, void modules, import
# cycles and the kinds of module header.
#
# Every .roc file is a module. A topic is one file, so the rules that need
# more than one file are comments here. Each error title in quotes is what the
# compiler printed in a multi-file test.
#
#   kind       first line of the file                  what other modules see
#   type       no header. The file name decides         one type and its `.{ }` items
#   package    package [Parser, Encoder] { json: "..." } the type modules it lists
#   platform   platform "name" requires ...             the modules in `exposes`
#   app        app [main!] { pf: platform "..." }       the entrypoints in `[...]`
#
# See the `packages`, `platforms` and `app_header` topics for those headers.
#
# A type module Url.roc must declare a top-level nominal type `Url := ...` or
# an opaque one, `Url :: ...`:
#   - no type named Url              "type module missing matching type"
#   - a type alias `Url : ...`       "type module requires nominal type"
# Alias modules (ParseErr.roc that holds `ParseErr : Url.ParseErr`) are
# planned. This compiler rejects them with the second error.
#
# The public API of Url.roc is the type Url and the items in its `.{ }` block.
# Other modules reach them as `Url.from_str` and `Url.ParseErr`. A top-level
# function or value stays private to the file. From another module,
# `Url.has_scheme(s)` is "does not exist". Roc has no `pub` and no private
# methods: every `.{ }` item is public, so a private helper goes at the top
# level. Put every public type in the `.{ }` block too. `import Url.Hidden` of
# a second top-level type fails with "type not exposed".

Url :: { self : Str }.{
	# Nested types can nest again: other modules write Url.ParseErr.Reason, or
	# `import Url.ParseErr.Reason as Reason` to drop the prefix.
	ParseErr := [Empty, NoScheme(Str)].{
		Reason := [Short].{
			describe : Reason -> Str
			describe = |_| "too short"
		}
	}

	from_str : Str -> Try(Url, [ParseErr(Url.ParseErr)])
	from_str = |text|
		if text.is_empty() {
			Err(ParseErr(Empty))
		} else if has_scheme(text) {
			Ok({ self: text })
		} else {
			Err(ParseErr(NoScheme(text)))
		}

	to_str : Url -> Str
	to_str = |url| url.self
}

# Private: not reachable from other modules.
has_scheme : Str -> Bool
has_scheme = |text| text.contains("://")

expect Url.from_str("https://roc-lang.org").map_ok(Url.to_str).ok_or("") == "https://roc-lang.org"
expect Url.from_str("roc-lang.org").is_err()
expect Url.ParseErr.Reason.describe(Short) == "too short"

# A void module is a namespace for functions and constants that belong to no
# type, the Util.roc of other languages. Back it with `[]`, the empty tag union:
# `[]` has no values, so not even Util.roc can make a `Util` value. A `{}`
# backing would allow one.
Util :: [].{
	clamp : I64, I64, I64 -> I64
	clamp = |n, low, high| n.max(low).min(high)

	max_retries : U64
	max_retries = 3
}

expect Util.clamp(15, 0, 10) == 10
expect Util.max_retries == 3

# @rejects type mismatch
# no_util : Util
# no_util = {}

# Import cycles are rejected, a module that imports itself included ("import
# cycle detected"). The compiler caches each module, and a cycle would force
# every module in it to rebuild together. Code that must refer both ways goes
# in one file, e.g. mutually recursive types in one void module (see the
# `imports` topic). Packages cannot form a cycle either ("package cycle").
