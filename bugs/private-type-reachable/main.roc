# A second top-level type in a type module is usable from outside the module.
#
# Run:      roc private-type-reachable/main.roc
# Expected: An error for `Url.Hidden`. langref modules.md:31: "if `Url` defines
#           a separate top-level nominal type of `Foo :=` then that `Foo` type
#           will only be visible inside `Url.roc`."
# Actual:   No errors. The program prints "built a Url.Hidden".
#
# Nightly: nightly-2026-10-06-c34079d.

import Url

secret : Url.Hidden
secret = Url.Hidden.(7)

main! = |_args| {
	_url = Url.parse("https://roc-lang.org")
	echo!("built a Url.Hidden\n")
	Ok({})
}
