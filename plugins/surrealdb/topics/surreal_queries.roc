## Queries and writes: every clause is a Roc function over the row, taken as a
## `Code(f)` and translated to SurrealQL. This app has no platform and prints
## the statement of each call. `prepare` gives a `Surreal.Prepared(out)` that
## knows the type of its result (topic `surreal_session` runs it).
app [main!] {
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.1/7MmdAaAt5bThg6ih3nR9ewVgw4CtNGvuK5HNQhEgZoSV.tar.zst",
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

# A call that has no SurrealQL form is not a compile error. `prepare` returns
# `Err(Unsupported("in `select`: ..."))` that names the clause, so read the
# `Try`. `show` prints either side.
show : Try(Surreal.Prepared(out), Surreal.Error) -> Str
show = |prepared| match prepared {
	Ok(p) => p.statement().to_script()
	Err(e) => "refused: ${Str.inspect(e)}"
}

# A value from the program's scope cannot be read inside a clause. A function
# that does it is the compile error "reified function captures a value".
# Pass the value in a parameter record instead: the record is the first
# argument of the clause (`filter_by`), and `prepare` takes its value. Write the
# field out, `prepare({ city: city })`: `{ city }` is a block that returns the
# `Str`, so the compiler says it is not a record.
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
by_city : Try(Surreal.Prepared(List(OwnerCard)), Surreal.Error)
by_city = Surreal.from(owners).filter_by(in_city).select(owner_card).order_by(|r| r.id, Asc).start(2).limit(2).prepare({ city: "Oslo" })

# `select` of a bare value is refused ("a result row is a record"). Use
# `select_value`.
pet_names : Try(Surreal.Prepared(List(Str)), Surreal.Error)
pet_names = Surreal.from(pets).select_value(|p| p.name).prepare({})

# Reading through a link keeps the query in one statement.
lines : Try(Surreal.Prepared(List(PetLine)), Surreal.Error)
lines = Surreal.from(pets).select(pet_line).prepare({})

# A group is a key and an aggregate. `totals` is `GROUP ALL`: one row, also
# for no rows.
Ledger : { pet : Str, visits : I64, revenue : Dec }

ledger_line : Str, List(Visit) -> Ledger
ledger_line = |pet, rows| { pet, visits: rows.len().to_i64_wrap(), revenue: rows.map(|v| v.fee).sum() }

ledger : Try(Surreal.Prepared(List(Ledger)), Surreal.Error)
ledger = Surreal.from(visits).group_by(|v| v.pet.get().name).aggregate(ledger_line).order_by(|r| r.revenue, Desc).prepare({})

Totals : { visits : I64, revenue : Dec }

totals : Try(Surreal.Prepared(Totals), Surreal.Error)
totals = Surreal.from(visits).totals(|rows| { visits: rows.len().to_i64_wrap(), revenue: rows.map(|v| v.fee).sum() }).prepare({})

# A value that exists only at run time goes in with `select_where` and
# `bind_captured`: it becomes a `LET` variable. Only these two take a captured
# value; every other clause takes a parameter record.
dearer_than : Dec -> Try(Surreal.Prepared(List(Visit)), Surreal.Error)
dearer_than = |limit| Surreal.bind_captured(Surreal.select_where(visits, |v| v.fee > limit))

# Writes. `create` and `insert` return the `Try(Prepared(..), Error)` of their
# statement, but `update_at`, `set_at` and `delete_at` return a `Write` with no
# `Try`: its `prepare` gives the `Try`. A key is an `Id` of the table, made with
# `owners.id("ann")`.
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

main! = |_args| {
	statements = [
		show(by_city),
		show(pet_names),
		show(lines),
		show(ledger),
		show(totals),
		show(dearer_than(12.5)),
		show(owners.create(ann)),
		show(owners.update_at(owners.id("ann"), renamed).prepare({})),
		show(owners.set_at(owners.id("ann"), moved).prepare({})),
		show(owners.delete_at(owners.id("ann")).prepare({})),
	]
	echo!(Str.join_with(statements, "\n"))
	Ok({})
}
