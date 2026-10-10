# Type annotations, type variables, generalization, `where` clauses, and
# aliases.
#
# Type annotations are optional, because Roc infers every type. You write them
# to document or restrict a value's type. The compiler checks every annotation.

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
# Lowercase names (like `a`, `b`, `elem`) are type variables. One name used
# twice in an annotation is one type.
type_var : List(a) -> List(a)
type_var = |lst| lst

# `_` or a `_name` type variable is a type that is not related to any other.
# `_` alone also asks the compiler to infer that part.
count_any : List(_elem) -> U64
count_any = |lst| lst.len()

number_op : I64, I64 -> _
number_op = |a, b| { sum: a + b, diff: a - b }

# The type system is Hindley-Milner, so inference needs no annotations. It has
# these limits:
#   1. No higher-rank types. A function argument has one type inside the call,
#      so the body cannot apply an `(a -> a)` argument to a `U8` and a `Str`.
#   2. No higher-kinded types. A type variable stands for a type such as
#      `List(U64)`, never for `List` itself, so `m(a)` does not parse.
#   3. No subtyping. Types unify. An open record or tag union (`..`) gives the
#      width flexibility.
#
# @rejects type mismatch
# apply_both = |f| (f(1.U8), f("x"))
#
# @rejects unexpected statement
# map_any : m(a) -> m(b)

# Generalization: the compiler makes a definition reusable at many types only
# in these cases:
#   1. A function. Each call site gets its own types.
#   2. A name that only refers to a generalized function (`shorthand = f`),
#      because the copy does no work.
# Every other value has one type, so a value, its `dbg` or its `expect` never
# runs again for each type. A number literal with no other type is a `Dec`.
same_type = type_var

expect (same_type([1.U8]), same_type(["a"])) == ([1], ["a"])

# An annotation can make a type more specific, but never more general. So a
# type variable in the annotation of a value is an error. Write one type, or
# `List(_)`. To use the value at many types, make it a function that takes `{}`.
#
# @rejects value is not polymorphic
# top_empty : List(a)
# top_empty = []
empty : {} -> List(a)
empty = |{}| []

expect (empty({}).append(1.U8), empty({}).append("a")) == ([1], ["a"])

# A value with no annotation also gets one type, from its first use.
#
# @rejects type mismatch
# one_type = || {
# 	xs = []
# 	(xs.append(1.U8), xs.append("a"))
# }

# `where` clauses constrain a type variable to types that have specific methods.
# This function accepts any type with a `.to_str()` method. The compiler checks
# each call site, and the call compiles to a direct call of that type's method.
stringify : a -> Str where [a.to_str : a -> Str]
stringify = |value| value.to_str()

# An annotated function that calls a method on a type variable must list the
# method. Without an annotation, the compiler infers the `where` clause.
#
# @rejects missing method
# no_where : a -> Str
# no_where = |value| value.to_str()
#
# A structural record has no `to_str` method.
#
# @rejects missing method
# record_str = stringify({ x: 1 })

# One `where` clause can list several constraints, on several type variables.
convert_all : List(a) -> List(b) where [a.to_b : a -> b, b.is_valid : b -> Bool]
convert_all = |items| items.map(|item| item.to_b()).keep_if(|b| b.is_valid())

# Inside a function, the annotation of a value can use a type variable of the
# function's own annotation, because the function is what is generalized.
where_on_value : List(a) -> List(Str) where [a.to_str : a -> Str]
where_on_value = |items| {
	labels : List(a)
	labels = items
	labels.map(|label| label.to_str())
}

# A method that takes no value of the type, such as a constructor, needs a name
# for the type. `Thing : thing` in the body gives the type variable an uppercase
# name, and `Thing.default()` calls the method of the caller's type.
make_default : {} -> thing where [thing.default : () -> thing]
make_default = |_| {
	Thing : thing
	Thing.default()
}

Meters := U64.{
	default : () -> Meters
	default = || Meters.(0)
	is_eq : _
}

expect make_default({}) == Meters.(0)

# A `where` alias names a group of constraints so signatures can cite it instead
# of repeating the method list. The `where` keyword after the `:` is required.
# Any type with the methods satisfies the alias. No type declares that it
# implements one. Upstream declares one, `Encoding.Json.Encodable`. Cite an
# alias from another module by its full path, as the `json` topic shows.
a.Showable :  where [a.to_str : a -> Str]

announce : a -> Str where [a.Showable]
announce = |value| "value: ${stringify(value)}"

expect announce(1.U8) == "value: 1"

# An alias can combine other aliases and single constraints, and it can take
# parameters that its constraints use.
a.Comparable : where [a.is_lt : a, a -> Bool]
a.Sortable : where [a.Showable, a.Comparable]

smaller_str : a, a -> Str where [a.Sortable]
smaller_str = |x, y| if x < y x.to_str() else y.to_str()

expect smaller_str(3.U8, 2) == "2"

a.Encodable(fmt) : where [a.encode : a, fmt -> fmt]

encode_twice : a, fmt -> fmt where [a.Encodable(fmt)]
encode_twice = |value, fmt| value.encode(value.encode(fmt))

# A `where` alias is not a type, so it can only appear inside `where [...]`.
#
# @rejects where alias used as a type
# describe : Showable -> Str
# describe = |value| value.to_str()

# Inline record type:
distance : { x : F64, y : F64 } -> F64
distance = |p| (p.x * p.x + p.y * p.y).sqrt()

# An open record or tag union ends in `..`. Each anonymous `..` is a new type
# variable. A named one (`..r`) is the same rest in every place it appears.
keep_rest : { id : U64, ..r } -> { id : U64, ..r }
keep_rest = |record| { ..record, id: record.id + 1 }

expect keep_rest({ id: 1, label: "a" }) == { id: 2, label: "a" }

# A type alias (`:`) is another name for its definition. The two are the same
# type. The parameters of an alias must have names.
Pair(a) : (a, a)

swap : Pair(a) -> Pair(a)
swap = |(x, y)| (y, x)

# @rejects underscore in type alias
# Couple(_) : (U64, U64)
#
# An alias and a structural tag union cannot refer to themselves. A recursive
# type, or a group of types that refer to each other, must use `:=`.
#
# @rejects recursive alias
# BadTree : [Leaf, Node(BadTree, U64, BadTree)]
Tree := [Leaf, Node(Tree, U64, Tree)]
Expr := [Num(I64), Add(Expr, Expr), Block(List(Stmt))]
Stmt := [Let(Str, Expr), Print(Expr)]

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
