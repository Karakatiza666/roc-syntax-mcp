# Type annotations and constraints.
#
# Type annotations are optional, because Roc infers every type. You write them
# to document or restrict a value's type.

# A simple annotation.
name : Str
name = "Sam"

# Parameterized types: `List(a)`, `Try(a, b)`, etc. This compiler uses
# `List(U8)` where the old compiler used `List U8`.
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

# A `where` alias names one such constraint so signatures can cite it instead of
# repeating the method list. The `where` keyword after the `:` is required, and
# the alias may take parameters. Upstream declares one, `Encoding.Json.Encodable`.
# Cite an alias from another module by its full path, as the `json` topic shows.
a.Showable :  where [a.to_str : a -> Str]

announce : a -> Str where [a.Showable]
announce = |value| "value: ${stringify(value)}"

expect announce(1.U8) == "value: 1"

# Inline record type:
distance : { x : F64, y : F64 } -> F64
distance = |p| (p.x * p.x + p.y * p.y).sqrt()

# The wildcard `_` in a type signature means "infer this part".
number_op : I64, I64 -> _
number_op = |a, b| { sum: a + b, diff: a - b }

# A record field can carry a default or be optional:
#   field : Type ?? default   always present when read, so `.field` works
#   field ?: Type             may be absent, so read it with `.?field`
# Both let the field be omitted at construction. A default is only allowed on a
# nominal (`:=`) declaration's backing record, never on a structural record
# type, so this is `:=` and not `:`. See the `record_fields` topic.
ServerConfig := { host : Str, port : U16 ?? 8080, timeout_ms ?: U64 }

# `Type.{ fields }` destructures a nominal type's backing record in a pattern
# position, including a function parameter.
NominalTypeRecord := { x : U64 }

destructure_nominal_type : NominalTypeRecord -> U64
destructure_nominal_type = |NominalTypeRecord.{ x }| x
