## SQLite: a `Db` connection you hold, interpolated queries that bind their
## values, and decoders that are ordinary values.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.OsStr
import pf.Path
import pf.Sqlite
import pf.Sqlite.Decoder
import pf.Sqlite.Query
import pf.Stdout

Todo : { id : I64, task : Str, done : Bool }

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	path : Path
	path = "todos.db"

	# `open!` returns a `Db` that you pass around and can `close!`. `{}` takes the
	# defaults: create the file if it is missing, and wait up to five seconds for
	# a lock. `{ mode: ReadOnly }` opens an existing file without writing.
	db = Sqlite.open!(path, {})?

	# Writes: `execute!`. A statement that returns rows is rejected before it runs.
	#
	# Each `${...}` in a query is a bound parameter, never pasted into the SQL.
	# The value names its storage class: `Integer(n)`, `String(s)`, `Real(x)`,
	# `Bytes(b)` or `Null`. An interpolation inside quotes or a comment is a
	# compile error.
	task = "write the topic"
	db.execute!("INSERT INTO todos (task, done) VALUES (${String(task)}, ${Integer(0)})")?

	# Exactly one row: `query_one!`. A column is named, or numbered from 0.
	count = db.query_one!("SELECT COUNT(*) FROM todos", Decoder.i64(0))?
	Stdout.line!("${count.to_str()} todos")?

	# Many rows: `query_all!`.
	todos = db.query_all!("SELECT id, task, done FROM todos WHERE done = ${Integer(0)}", decode_todo)?
	for todo in todos {
		Stdout.line!("  ${todo.id.to_str()} ${todo.task}")?
	}

	# A large table: `rows` is a lazy stream. Leaving the loop ends the query.
	for! item in db.rows("SELECT id, task, done FROM todos", decode_todo) {
		match item {
			Ok(todo) if todo.id > 100 => break
			Ok(todo) => Stdout.line!(todo.task)?
			Err(BadRow(_)) => {}
			Err(Interrupted) => { return Err(Interrupted) }
			Err(SqliteErr(err)) => { return Err(SqliteErr(err)) }
			Err(Closed) => { return Err(Closed) }
		}
	}

	# A transaction commits when the body returns `Ok` and rolls back on `Err`.
	db.transaction!(|| {
		db.execute!("UPDATE todos SET done = ${Integer(1)} WHERE id = ${Integer(1)}")?
		db.execute!("UPDATE todos SET done = ${Integer(1)} WHERE id = ${Integer(2)}")?
		Ok({})
	})?

	# A query assembled at run time: SQL text with `?` markers and the values in
	# order. The connection keeps the statements it has prepared by their SQL text.
	wanted_ids = [1, 3]
	markers = Str.join_with(wanted_ids.map(|_| "?"), ", ")
	picked = db.query_all!(
		Query.new("SELECT task FROM todos WHERE id IN (${markers})", wanted_ids.map(|id| Integer(id))),
		Decoder.str("task"),
	)?
	Stdout.line!("${picked.len().to_str()} picked")?

	db.close!()?
	Ok({})
}

## A decoder is an ordinary value: a record of column decoders, turned into a
## decoder of records by the record-builder suffix `.Decoder`. You can annotate
## it, share it between queries, and name a column by name or by position. The
## second type argument is what can go wrong with a row, and `_` infers it.
decode_todo : Decoder(Todo, _)
decode_todo = {
	id: Decoder.i64("id"),
	task: Decoder.str("task"),
	done: Decoder.i64("done").map(|n| n != 0),
}.Decoder

## Leaf decoders: `i64`, `f64`, `str`, `bytes`, `bool` and `value`. SQLite
## integers are `I64`. For a narrower width, `map_try` and a checked conversion:
## its error fails the row like any other decoding error.
narrow : Decoder(U8, _)
narrow = Decoder.i64("n").map_try(|n| n.to_u8_try().map_err(|OutOfRange| OutOfRange))

## `nullable` turns a decoder into one that accepts NULL, as `Err(Null)`.
maybe_note : Decoder(Try(Str, [Null]), _)
maybe_note = Decoder.str("note").nullable()

## Failures arrive under one tag, `SqliteErr(Sqlite.Err)`, and `Sqlite.Err` can be
## compared with `==`. A constraint violation has a code to match on, with no
## message text to search. `NoRows` and `TooManyRows` are `query_one!` outcomes,
## and a row that fails to decode is `BadRow(err)`.
add_label! : Sqlite.Db, Str => Try([Added, AlreadyExists], _)
add_label! = |db, name|
	match db.execute!("INSERT INTO labels (name) VALUES (${String(name)})") {
		Ok({}) => Ok(Added)
		Err(SqliteErr(Failed({ code: Constraint(Unique), .. }))) => Ok(AlreadyExists)
		Err(other) => Err(other)
	}
