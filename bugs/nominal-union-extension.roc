# A nominal tag union accepts an `..others` type parameter.
#
# Run:      roc check nominal-union-extension.roc
# Expected: An error. langref tag-unions.md:138: "nominal tag unions don't
#           have the optional `..others` type parameter".
# Actual:   No errors.
#
# Nightly: nightly-2026-10-06-c34079d.

Color(others) := [Red, Green, ..others]

red : Color([Blue])
red = Color.Red

main! = |_args| Ok({})
