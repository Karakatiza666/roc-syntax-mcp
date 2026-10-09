# `!x` on a type that defines `not` does not dispatch to `not`.
#
# Run:      roc check not-operator-custom-type.roc
# Expected: No errors. langref operators.md:118: "Unary `!x` dispatches to
#           `x.not()`. The operand and result have the same type."
# Actual:   "type mismatch" at `!flag`. `!` accepts only a `Bool`.
#
# Nightly: nightly-2026-10-06-c34079d.

Flag := [On, Off].{
	not : Flag -> Flag
	not = |flag|
		match flag {
			On => Off
			Off => On
		}
}

flip : Flag -> Flag
flip = |flag| !flag

main! = |_args| Ok({})
