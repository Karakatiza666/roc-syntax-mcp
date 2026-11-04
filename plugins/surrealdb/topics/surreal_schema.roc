## Row types, tables and the schema: a row is a plain Roc record, a table is a
## `Surreal.Table(row)` over it, and the `DEFINE` statements come from the row
## type and from constraint functions. This app has no platform (it runs with
## `roc file.roc` on the reify compiler) and prints the schema.
app [main!] {
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.1/7MmdAaAt5bThg6ih3nR9ewVgw4CtNGvuK5HNQhEgZoSV.tar.zst",
}

import surreal.Surreal

Address : { city : Str, zip ?: Str }

# A default (`??`) is allowed only on the backing record of a nominal type.
# On an alias the compiler says "default not allowed in structural record".
#
# A nominal row also has to opt in to the codecs: without `encoder_for : _` and
# `parser_for : _` a write (`create`, `insert`) is a missing-method error. An
# alias row needs neither.
Owner := { id : Str, name : Str, email : Str, address : Address, tags : List(Str) ?? [] }.{
	encoder_for : _
	parser_for : _
}

# `U8` becomes `TYPE int` with `ASSERT >= 0 AND <= 255`. A tag union becomes a
# literal union. A field of a union arm may not be named `kind`: that is the
# tag in SurrealQL, and `Surreal.schema` returns `BadSchema` for it.
Species : [Dog, Cat, Bird({ wingspan_cm : U8 })]

# `Surreal.Link(row)` is a record link. The table of `row` has to be in the
# schema list, or `Surreal.schema` returns `BadSchema` ("no table holds the row
# type"). Two tables with an equal row type cannot be told apart as link
# targets: make one of the rows a nominal.
Pet : { id : Str, name : Str, species : Species, age : U8, owner : Surreal.Link(Owner), seen : Surreal.Datetime }

# An edge row names its ends `from` and `to`, because `in` is a keyword. The
# database stores them as `in` and `out`.
Treats : { id : Str, from : Surreal.Link(Owner), to : Surreal.Link(Pet), since : I64 }

owners : Surreal.Table(Owner)
owners = Surreal.table("owner")

pets : Surreal.Table(Pet)
pets = Surreal.table("pet")

treats : Surreal.Table(Treats)
treats = Surreal.relation("treats", owners, pets)

valid_email : Str -> Bool
valid_email = |email| email.contains("@") and !email.starts_with("@")

# A constraint is a Roc function. The program can call `valid_email` on its own
# rows too, and test it with `expect`.
expect valid_email("ann@example.org")
expect !valid_email("@example.org")

owner_def : Surreal.Defined
owner_def =
	owners.define()
		.unique(|o| o.email)
		.assert(|o| o.email, valid_email)
		.assert_each(|o| o.tags, |t| t != "")
		.index(|o| o.address.city)
		.done()

# `on_delete` sets what a delete of the target does to the rows that link to it:
# `Cascade`, `Reject` or `Unset`. `check` over a single field is folded into
# that field's ASSERT. A check that reads several fields becomes an event.
pet_def : Surreal.Defined
pet_def =
	pets.define()
		.check("age is sane", |p| p.age > 0)
		.check("kittens are young", |p| p.age < 40 or p.name != "Kit")
		.on_delete(owners, Cascade)
		.done()

treats_def : Surreal.Defined
treats_def = treats.define().unique(|e| { from: e.from, to: e.to }).done()

# `Surreal.schema` gives `Try(Str, Surreal.Error)`: the whole script, with
# `DEFINE ... OVERWRITE`, in one string. Run it on a session with
# `Surreal.Unchecked.query!` (topic `surreal_session`).
schema_text : Str
schema_text = match Surreal.schema([owner_def, pet_def, treats_def]) {
	Ok(text) => text
	Err(e) => "bad schema: ${Str.inspect(e)}"
}

main! = |_args| {
	echo!(schema_text)
	Ok({})
}
