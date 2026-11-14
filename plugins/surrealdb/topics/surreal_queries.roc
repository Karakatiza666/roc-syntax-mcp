## Queries and writes: every clause is a Roc function over the row, taken as a
## `Code(f)` and translated to SurrealQL. This app has no platform and prints
## the statement of each call. `prepare` and `ready` give a `Surreal.Prepared(out)`
## that knows the type of its result and holds any error of the statement (topic
## `surreal_session` runs it).
app [main!] {
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.4/CkLUeGcqAc6kNLaDf5rMbQEaZAE7nxapCE4EsHnqh5HY.tar.zst",
}

import surreal.Surreal

Owner : { id : Str, name : Str, city : Str, phone ?: Str }
Pet : { id : Str, name : Str, age : U8, owner : Surreal.Link(Owner) }
Visit : { id : Str, pet : Surreal.Link(Pet), fee : Dec, seen : Surreal.Datetime }

owners : Surreal.Table(Owner)
owners = Surreal.table("owner")

pets : Surreal.Table(Pet)
pets = Surreal.table("pet")

visits : Surreal.Table(Visit)
visits = Surreal.table("visit")

# A call that has no SurrealQL form is not a compile error. The `Prepared` holds
# `Err(Unsupported("in `select`: ..."))`, which names the clause. There is no
# `Try` around a `Prepared`: `checked()`, `statement()` and `request()` give
# the error, and `run!` puts it in its result. `show` prints either side.
# `to_script()` is the readable form with `LET` lines; the server gets the values
# as the `vars` of the request.
show : Surreal.Prepared(out) -> Str
show = |prepared| match prepared.statement() {
	Ok(statement) => statement.to_script()
	Err(e) => "refused: ${Str.inspect(e)}"
}

# A parameter record is the first argument of the clause (`filter_by`), and
# `prepare` takes its value. Write the field out, `prepare({ city: city })`:
# `{ city }` is a block that returns the `Str`, so the compiler says it is not a
# record. A query with no parameter ends with `ready()`.
CityParam : { city : Str }

in_city : CityParam, Owner -> Bool
in_city = |p, o| o.city == p.city

# The same function runs in Roc.
expect in_city({ city: "Oslo" }, { id: "a", name: "Ann", city: "Oslo" })

# A projection is a function to a record. The result type is that record, and
# an optional field read with `.?` and `??` becomes `phone ?? 'none'`.
OwnerCard : { id : Str, name : Str, phone : Str }

owner_card : Owner -> OwnerCard
owner_card = |o| { id: o.id, name: o.name, phone: o.?phone ?? "none" }

# A link is read with `get()`, which is a traversal: `owner.name`.
PetLine : { id : Str, owner : Str, city : Str }

pet_line : Pet -> PetLine
pet_line = |p| { id: p.id, owner: p.owner.get().name, city: p.owner.get().city }

# After a projection the steps run in the order SurrealQL runs them: order,
# then start, then limit. A chain in another order, such as
# `.limit(2).order_by(..)`, is a compile error: `Surreal.Limited` has no
# `order_by`. `live` has the same rule, for `Limited` and `Started`.
by_city : Surreal.Prepared(List(OwnerCard))
by_city = Surreal.from(owners).filter_by(in_city).select(owner_card).order_by(|r| r.id, Asc).start(2).limit(2).prepare({ city: "Oslo" })

# `select` of a bare value is refused ("a result row is a record"). Use
# `select_value`.
pet_names : Surreal.Prepared(List(Str))
pet_names = Surreal.from(pets).select_value(|p| p.name).ready()

# Reading through a link keeps the query in one statement.
lines : Surreal.Prepared(List(PetLine))
lines = Surreal.from(pets).select(pet_line).ready()

# A group is a key and an aggregate. `totals` is `GROUP ALL`: one row, also
# for no rows. A count is `rows.len()`, a `U64`.
Ledger : { pet : Str, visits : U64, revenue : Dec }

ledger_line : Str, List(Visit) -> Ledger
ledger_line = |pet, rows| { pet, visits: rows.len(), revenue: rows.map(|v| v.fee).sum() }

ledger : Surreal.Prepared(List(Ledger))
ledger = Surreal.from(visits).group_by(|v| v.pet.get().name).aggregate(ledger_line).order_by(|r| r.revenue, Desc).ready()

Totals : { visits : U64, revenue : Dec }

totals : Surreal.Prepared(Totals)
totals = Surreal.from(visits).totals(|rows| { visits: rows.len(), revenue: rows.map(|v| v.fee).sum() }).ready()

# A chain inside a function whose result is a `Prepared` (or a `Watch`) reads
# the values of that function in any clause. Each one is a `$_1`, `$_2`, ..
# slot, sent in the `vars` of the request.
dearer_than : Dec -> Surreal.Prepared(List(Visit))
dearer_than = |limit| Surreal.from(visits).filter(|v| v.fee > limit).ready()

# Writes. `create` and `insert` return the `Prepared` of their statement, but
# `update_at`, `set_at` and `delete_at` return a `Write`: its `ready` (or
# `prepare` with a parameter record) gives the `Prepared`. A key is a
# `Code(Id(row))`, made with `owners.id("ann")`: a constant written in a
# top-level value, as below, or a value of the function around the chain.
renamed : Owner -> Owner
renamed = |o| { ..o, name: "Ann B." }

ann : Owner
ann = { id: "ann", name: "Ann", city: "Oslo" }

# `{ ..o, f: x }` has the type of `o`. A patch that has to change the type of a
# field is a record written out in full.
# `set_at` takes any record and checks its fields when the statement is built,
# not the compiler: a field the row does not have is `BadSchema`, and so is
# a number literal for an `I64` field, because it is a `Dec`: write `5.I64`.
moved : Owner -> { city : Str }
moved = |_| { city: "Rome" }

create_ann : Surreal.Prepared(List(Owner))
create_ann = owners.create(ann)

rename_ann : Surreal.Prepared(List(Owner))
rename_ann = owners.update_at(owners.id("ann"), renamed).ready()

move_ann : Surreal.Prepared(List(Owner))
move_ann = owners.set_at(owners.id("ann"), moved).ready()

delete_ann : Surreal.Prepared(List(Owner))
delete_ann = owners.delete_at(owners.id("ann")).ready()

main! = |_args| {
	statements = [
		show(by_city),
		show(pet_names),
		show(lines),
		show(ledger),
		show(totals),
		show(dearer_than(12.5)),
		show(create_ann),
		show(rename_ann),
		show(move_ann),
		show(delete_ann),
	]
	echo!(Str.join_with(statements, "\n"))
	Ok({})
}
