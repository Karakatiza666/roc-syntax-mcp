# Type annotations and constraints.
#
# Type annotations are optional — Roc infers every type. You only write
# annotations to document or restrict a value's type.

# A simple annotation.
name : Str
name = "Sam"

# Parameterized types: `List(a)`, `Try(a, b)`, etc. The old `List U8` syntax
# is replaced by `List(U8)` in the new compiler.
strings : List(Str)
strings = ["a", "b", "c"]

# Pure (`->`) vs effectful (`=>`) function arrows.
average : Dec, Dec -> Dec
average = |a, b| (a + b) / 2

# read_str! : Path => Try(Str, ReadFileErr)
# read_str! = |path| ...

# Type variables let a function work with any type.
# Lowercase names (like `a`, `b`, `elem`) are type variables.
type_var : List(a) -> List(a)
type_var = |lst| lst

# `where` clauses constrain a type variable to types that have specific methods.
# This function accepts any type with a `.to_str()` method.
stringify : a -> Str where [a.to_str : a -> Str]
stringify = |value| value.to_str()

# Inline record type:
distance : { x : F64, y : F64 } -> F64
distance = |p| (p.x * p.x + p.y * p.y).sqrt()

# The wildcard `_` in a type signature means "infer this part".
number_op : I64, I64 -> _
number_op = |a, b| { sum: a + b, diff: a - b }
