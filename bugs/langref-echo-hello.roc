# The Hello World of langref modules.md:685 does not compile.
#
# Run:      roc check langref-echo-hello.roc
# Expected: No errors.
# Actual:   "type mismatch". The Echo platform's `main!` must return a `Try`,
#           so the body needs `Ok({})` after `echo!`.
#
# Nightly: nightly-2026-10-06-c34079d.

main! = |_args| echo!("Hello, World!")
