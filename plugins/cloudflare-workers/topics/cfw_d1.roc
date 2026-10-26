## D1: typed reads, writes, batches, constraint errors, sessions and 64-bit ids.
##
## A D1 binding is a constant: `D1.binding("DB")`, with the binding name of the Wrangler config. The read functions are
## generic in the row type. The type comes from the annotation at the call (MC7), not from the SQL. So annotate each
## binding that holds rows. With no annotation, a value that only goes to `Response.from_json` gives "never resolved to
## a concrete type", and a field that is only used with a method (`row.n.to_str()`) gives "requires the parser_for method".
##
## Rows cross as CBOR objects and parse into the record by column name, so a column name is a snake_case field name
## (`SELECT 1 AS firstName` into `first_name` is `BadData("column first_name: missing")`: write `AS first_name`).
## A column that the record does not name is ignored. A field with no column is `BadData("column z: missing")`.
## Each read stops at 1 MiB with `Err(Infra(TooLarge))`. The `_with` forms take `{ max_bytes }`.
## `NotFound` of `first!` and `Constraint` (a failed constraint) are flat tags. Every other platform error is inside
## `Infra(..)`. A pattern `Err(Infra(Constraint(_)))` never matches. It compiles when the error type is `_`, and it is a
## type mismatch when the error type is closed. Write `Err(Constraint(_))`.
##
## What a field type reads (checked on a local D1; `Object.Self.sql!` has the same rules):
##   Str, I64, F64 ...  A TEXT column reads into `Str`. An INTEGER column reads into an integer type, and also into `F64`.
##                      A REAL column reads into an integer type only when it has no fraction (`2.0` yes, `2.5` is BadData).
##                      An INTEGER column does not read into `Str`.
##   NULL               Only a field of the type `Try(Str, [Null])` reads a NULL. Every other type is `BadData`, and
##                      its text names the fix ("NULL, read it into a Try(a, [Null]) item"): `Str`,
##                      `Try(Str, [Missing])`, `[Null, Some(Str)]` and an optional field `name ?: Str` too.
##   Bool               A Bool field is `BadData` for 0 and for 1. The text says to read an `I64` or `U8` item. SQLite
##                      has no Bool: read an `I64` and compare it with 0.
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.D1
import pf.Sql
import pf.Id64

db = D1.binding("DB")

## A BLOB column reads into a `List(U8)` field or a `Cbor.Bytes` field (D1 gives a BLOB as an array of numbers).
User : { id : I64, name : Str, avatar : List(U8) }

list_users! : () => Try(List(User), _)
list_users! = || {
	# The annotation names the whole result: `List(User)`, not `User`.
	users : List(User)
	users = db.all!("SELECT id, name, avatar FROM users", Sql.none)?
	Ok(users)
}

## An id of 64 bits. D1 gives each number as a JS `Number`, so an INTEGER of 2^53 or more comes back rounded. A typed
## read of such a number is `BadData("column id: integer of 2^53 or more, read it with CAST(x AS TEXT) ...")`. Read it
## as text with `CAST(id AS TEXT)`: an `I64`, a `U64` or an `Id64` field reads the text and keeps every bit.
## `Id64` has no number methods and no order. A bare `Id64` does not encode to JSON ("encode_bytes ... JsonEncoding"):
## write `id.to_web()` (the U64 text), and read it back with `Id64.from_web`.
Event : { id : Id64, kind : Str }

events! : () => Try(List(Event), _)
events! = || {
	events : List(Event)
	events = db.all!("SELECT CAST(id AS TEXT) AS id, kind FROM events", Sql.none)?
	Ok(events)
}

## Parameters: one bare value (`"ann"`, `5`) is one parameter, the same as `[x]`. Write `(a, b)` for two or more and
## `Sql.none` for none. A bare `[]` does not compile ("encoder_for ... item ... never resolved").
## `("ann")` is not a tuple: it is the text, so it is one parameter too.
## The old `Sql` tag form (`Text("ann")`, `Int(5)`, `[Text("ann")]`) compiles, but it is `BadParam` at run time. The text
## names the new form: `Text("ann") is the old Sql tag form, write "ann"`. A record is `BadParam` too.
## A `List(U8)` is a list of integer parameters, not one blob: use `Sql.blob(list)`.
## `Sql.null` is NULL. `Sql.or_null(try)` is the value of an `Ok`, else NULL. `Sql.blob(list)` is a BLOB.
## An integer outside I64 (a U64 above 2^63-1) is `BadParam`, never a wrap. A `Bool` is `BadParam`: write 0 or 1.
## A parameter is text in SQL when it is text in Roc. It becomes an integer only in an insert into an INTEGER column, in a
## compare with an INTEGER column, or in arithmetic: `? = ? + 0` compares text with an integer and is false.
## An integer parameter binds as a JS number, so a column with no type (`CREATE TABLE t (v)`) stores it as REAL.
## Use typed columns or STRICT tables.
add_user! : Str, Try(List(U8), [NoAvatar]) => Try(I64, _)
add_user! = |name, avatar| {
	info = db.run!("INSERT INTO users (name, avatar) VALUES (?, ?)", (name, Sql.or_null(avatar.map_ok(Sql.blob))))?
	# `last_row_id` is a `Try`: `Err(Rounded)` when the row id is 2^53 or more.
	info.last_row_id.map_err(|Rounded| Infra(BadData("rowid above 2^53")))
}

## One bare `Str` is the one parameter of this query.
user_by_name! : Str => Try(User, _)
user_by_name! = |name| {
	user : User
	user = db.first!("SELECT id, name, avatar FROM users WHERE name = ?", name)?
	Ok(user)
}

## A failed constraint is its own flat tag, `Constraint({ kind, message })`, with the kind from the SQLite extended
## code. It is not inside `Infra`. A primary key conflict is `PrimaryKey`, not `Unique`. Match the kinds before the
## general arm, and let the other errors go on.
create! : Str => Try(Response, _)
create! = |name| match add_user!(name, Err(NoAvatar)) {
	Ok(id) => Ok(Response.from_text(201, id.to_str()))
	Err(Constraint({ kind, message })) if kind == Unique or kind == PrimaryKey => Ok(Response.from_text(409, message))
	Err(Constraint({ kind: Trigger, message })) => Ok(Response.from_text(422, message))
	Err(e) => Err(e)
}

## `batch!` is one transaction and one crossing. D1 has no `BEGIN` from a Worker, and a batch cannot branch: a trigger
## with `RAISE(ABORT, 'text')` rolls back the whole batch and gives `Constraint({ kind: Trigger, message: "text" })`.
## Each statement gives one `D1.Result`, in order. A read in a batch is typed at its use, because each statement can
## have another row type. Each `Sql.stmt` has its own parameter types.
transfer! : I64, I64, I64 => Try(I64, _)
transfer! = |from, to, amount| {
	results = db.batch!(
		[
			Sql.stmt("UPDATE acct SET n = n - ? WHERE id = ?", (amount, from)),
			Sql.stmt("UPDATE acct SET n = n + ? WHERE id = ?", (amount, to)),
			Sql.stmt("SELECT n FROM acct WHERE id = ?", [to]),
		],
	)?
	match results {
		[_, _, last] => {
			balance : { n : I64 }
			balance = last.first()?
			Ok(balance.n)
		}
		_ => Err(Infra(BadData("the batch gave no result")))
	}
}

## `all_tuples!` reads rows as arrays into tuples, in the column order of the SELECT. It is faster than records. A
## record type here type-checks, and each read is `BadData("row 0: the row does not fit the type")`.
names! : () => Try(List((I64, Str)), _)
names! = || {
	pairs : List((I64, Str))
	pairs = db.all_tuples!("SELECT id, name FROM users", Sql.none)?
	Ok(pairs)
}

## Sessions (read replicas). `with_session!` gives a `D1.Session`, which holds a ref, so it is good for one request: keep
## the bookmark, not the session. Give the bookmark of the last request to `After` for reads that see its writes.
## `bookmark!` is `NotFound` before the first query.
session_read! : Request => Try(Response, _)
session_read! = |req| {
	session = match req.header("x-d1-bookmark") {
		Ok(mark) => db.with_session!(After(mark))?
		Err(NotFound) => db.with_session!(Any)?
	}
	user : User
	user = session.first!("SELECT id, name, avatar FROM users LIMIT 1", Sql.none)?
	mark = session.bookmark!() ?? ""
	Ok(Response.from_json(200, { id: user.id, name: user.name }).with_header("x-d1-bookmark", mark))
}

## `rows!` gives `Sql` values with no types, for columns that are not known at compile time (a SQL console, an
## export). A number of 2^53 or more is a `Real` there.
columns! : Str => Try(Response, _)
columns! = |table| {
	raw = db.rows!("SELECT * FROM ${table} LIMIT 1", Sql.none)?
	Ok(Response.from_text(200, Str.join_with(raw.columns, ",")))
}

fetch! : Request => Try(Response, _)
fetch! = |req| match (req.method(), req.segments()) {
	(GET, ["users"]) => {
		users = list_users!()?
		Ok(Response.from_json(200, users.map(|u| { id: u.id, name: u.name })))
	}
	(POST, ["users", name]) => create!(name)
	(GET, ["users", name]) => {
		user = user_by_name!(name)?
		Ok(Response.from_json(200, { id: user.id, name: user.name }))
	}
	(POST, ["transfer"]) => {
		n = transfer!(1, 2, 10)?
		Ok(Response.from_text(200, n.to_str()))
	}
	(GET, ["names"]) => {
		pairs = names!()?
		Ok(Response.from_text(200, pairs.len().to_str()))
	}
	(GET, ["events"]) => {
		es = events!()?
		Ok(Response.from_json(200, es.map(|e| { id: e.id.to_web(), kind: e.kind })))
	}
	(GET, ["session"]) => session_read!(req)
	(GET, ["columns", table]) => columns!(table)
	_ => Ok(Response.from_status(404))
}

worker = Worker.new({ fetch!: fetch!, bindings: [db.declare()] })

event! = |e| worker.event!(e)
