## SQLite: one call per shape of result, row decoders built by hand, and
## prepared statements when the same query runs many times.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst" }

import pf.OsStr
import pf.Path
import pf.Sqlite
import pf.Stdout

Todo : { id : I64, task : Str, done : Bool }

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	db : Path
	db = "todos.db"

	# Writes: `execute!`. It fails with `RowsReturnedUseQueryInstead` if the
	# statement returns rows. This catches a query sent to `execute!` by mistake.
	Sqlite.execute!({
		path: db,
		query: "INSERT INTO todos (task, done) VALUES (:task, :done);",
		bindings: [
			{ name: ":task", value: String("write the topic") },
			{ name: ":done", value: Integer(0) },
		],
	})?

	# Exactly one row: `query!`, with a `row` decoder. `query!` and `query_many!`
	# have no annotation upstream, so the decoder does not give the result its
	# type. Annotate the binding, or no method call on the result can dispatch.
	count : U64
	count = Sqlite.query!({
		path: db,
		query: "SELECT COUNT(*) AS \"n\" FROM todos;",
		bindings: [],
		row: Sqlite.u64("n"),
	})?
	Stdout.line!("${count.to_str()} todos")?

	# Many rows: `query_many!`, with a `rows` decoder.
	todos : List(Todo)
	todos = Sqlite.query_many!({
		path: db,
		query: "SELECT id, task, done FROM todos WHERE done = :done;",
		bindings: [{ name: ":done", value: Integer(0) }],
		rows: decode_todo,
	})?
	for todo in todos {
		Stdout.line!("  ${todo.id.to_str()} ${todo.task}")?
	}

	# One column, many rows: a leaf decoder is already a row decoder.
	tasks : List(Str)
	tasks = Sqlite.query_many!({
		path: db,
		query: "SELECT task FROM todos;",
		bindings: [],
		rows: Sqlite.str("task"),
	})?
	Stdout.line!("${tasks.len().to_str()} tasks")?

	prepared!(db)?
	Ok({})
}

## A row decoder takes the column names, then the statement, and yields one
## decoded row. Do not annotate it. The type of the inner stage uses a host-side
## handle that an app cannot name, so you cannot write the type. `Sqlite` has
## no `map2`, so the record builder `{ ... }.Sqlite` does not compile. Combine
## the leaf decoders by hand and build the record yourself.
decode_todo = |cols|
	|stmt| {
		id = Sqlite.i64("id")(cols)(stmt)?
		task = Sqlite.str("task")(cols)(stmt)?
		done = Sqlite.i64("done")(cols)(stmt)?
		Ok({ id, task, done: done != 0 })
	}

## Leaf decoders: `str`, `bytes`, `f64`, and every integer width, each with a
## `nullable_` twin that decodes to `[NotNull(a), Null]` instead of failing on a
## NULL column.
maybe_note = Sqlite.nullable_str("note")

## Prepare once, execute many. Each execution starts fresh, so bindings from the
## previous run never leak into the next one. Results are not cached.
prepared! : Path => Try({}, _)
prepared! = |db| {
	stmt = Sqlite.prepare!({ path: db, query: "UPDATE todos SET done = 1 WHERE id = :id;" })?
	stmt.execute!([{ name: ":id", value: Integer(1) }])?
	stmt.execute!([{ name: ":id", value: Integer(2) }])?

	rows = Sqlite.prepare!({ path: db, query: "SELECT task FROM todos;" })?
	first : List(Str)
	first = rows.query_many!([], Sqlite.str("task"))?
	again : List(Str)
	again = rows.query_many!([], Sqlite.str("task"))?
	expect first.len() == again.len()
	Ok({})
}

## `Sqlite.Value` is the binding type: `Null`, `Real(F64)`, `Integer(I64)`,
## `String(Str)`, `Bytes(List(U8))`. A binding pairs it with the `:name` the
## query uses, colon included.
bindings : List(Sqlite.Binding)
bindings = [
	{ name: ":id", value: Integer(7) },
	{ name: ":label", value: String("urgent") },
	{ name: ":score", value: Real(0.5) },
	{ name: ":blob", value: Bytes([1, 2, 3]) },
	{ name: ":nothing", value: Null },
]

## Failures are `SqliteErr(ErrCode, Str)` for the database's own errors and
## `NoSuchField(Str)` when a decoder names a column the query did not select.
explain : Sqlite.DecodeErr -> Str
explain = |err|
	match err {
		NoSuchField(name) => "the query returned no column named ${name}"
		SqliteErr(code, message) => "${Str.inspect(code)}: ${message}"
	}

expect explain(NoSuchField("task")) == "the query returned no column named task"
