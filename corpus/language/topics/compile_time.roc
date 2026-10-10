# Compile-time evaluation: what the compiler runs while it builds, and what
# happens to crashes, effects, and empty collections there.

# The compiler evaluates every top-level constant at compile time and stores
# the result in the binary as a static constant. `area` costs the same at
# runtime as `area = 12`. This is safe because the code is pure: a pure
# function with fixed inputs gives the same result at compile time and at
# runtime. A `dbg` in a top-level constant prints during `roc check`.
width = 3
height = 4
area = width * height

# Functions are values. A top-level call that returns a function also runs at
# compile time, so `add_one` costs the same as `|num| num + 1`.
make_adder = |amount| |num| num + amount
add_one = make_adder(1)

expect add_one(area) == 13

# The compiler can also evaluate a pure call inside a function when its
# arguments are top-level constants, e.g. `area.to_str()` in
# `echo!("area is ${area.to_str()}")`. `echo!` itself runs at runtime.
#
# Effects never run at compile time. The result of an effectful call and a
# value that the platform provides are known only at runtime. The compiler does
# not run platform code, so `roc check` and `roc build` cannot do I/O, also for
# the code of a platform or a package.
#
# A crash during compile-time evaluation is a compile error, and an infinite
# loop hangs the compiler.
#
# @rejects compile time crash
# first_item : U64
# first_item = [].first() ?? crash "the list is empty"
#
# A condition on a top-level constant makes the compiler warn, because the
# branch is known at compile time:
#
# @warns unconditional condition
# verbose = False
# log_line = |msg| if verbose "debug: ${msg}" else msg

# Use top-level constants to do setup work once, at build time: lookup tables,
# dictionaries with known contents, and parsers. A parser from `parser_for` or
# `Json.parser_camel()` bound at the top level is built at compile time (see
# `json`).
squares : List(U64)
squares = List.from_iter((0..<10).iter().map(|n| n * n))

roman : Dict(Str, U64)
roman = Dict.from_list([("I", 1), ("V", 5), ("X", 10)])

expect squares.get(3) == Ok(9) and roman.get("V") == Ok(5)

# The program shares one copy of each compile-time value and never frees it.
# Such a value is never unique, so its first update at runtime copies it. The
# first `insert` into a compile-time `Dict` also rehashes every key, because
# the dict changes from a fixed hash seed to a random seed.

# With an embedded file, the compiler also parses the file. The program neither
# reads nor parses `config.json` at runtime, and the file need not exist then:
#   import "config.json" as config_text : Str
#   config : Try({ port : U16, host : Str }, _)
#   config = Json.parse(config_text)

# The binary does not store an empty `List`, `Str`, `Dict` or `Set`. A top-level
# `buffer = List.with_capacity(64)` has capacity 0 in the compiled program
# (`roc test` reports 64). Call `with_capacity` in the function that fills the
# collection.

# The binary stores only the values that the program uses. With
# `fives = List.repeat(5, 1_000_000)`, a program that reads `fives.len()` stores
# one number. A program that reads an element stores the list (8 MB), also when
# only a rare code path reads it.

# A program with compile errors still builds and runs. Code with an error
# crashes only when it runs. If compile-time evaluation reaches code with an
# error, the compiler reports the original error once, and the value crashes at
# runtime when the program uses it. A value that does not reach the error is
# evaluated as usual.
