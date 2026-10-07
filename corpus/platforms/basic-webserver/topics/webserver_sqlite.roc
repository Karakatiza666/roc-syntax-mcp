## SQLite: open the pool once in `init!`, then query with derived codecs.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.17.0/AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Sqlite
import pf.Path
import http.Response

# `Db` is a connection pool. Open it once. Every request shares the context,
# so this is also where shared mutable state belongs.
Context : { db : Sqlite.Db }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || {
	db = Sqlite.open!(Sqlite.default_config(Path.utf8("./todos.db"))) ? |_| Exit(2)
	Ok({ config: Server.default_config, context: { db } })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |_request, { db }| {
	todos = list_todos!(db) ? |err| ServerErr("query failed: ${Str.inspect(err)}")
	body = Str.join_with(todos.map(|t| Str.inspect(t)), "\n")
	Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(body))))
}

Todo : { id : I64, task : Str, status : Str }

# Params are a record, bound by `:name`. Rows decode into an inferred type
# through a derived `parser_for`, so the column order in the SQL must match the
# field order the annotation declares.
list_todos! : Sqlite.Db => Try(List(Todo), Sqlite.QueryError)
list_todos! = |db|
	Sqlite.query_many!({
		db,
		query: "SELECT id, task, status FROM todos WHERE status = :status;",
		params: { status: "completed" },
		limits: Sqlite.default_query_limits,
	})

# A write that returns no rows is `execute!`. Several statements that must
# succeed or fail together go inside `begin!` / `commit!`.
add_todo! : Sqlite.Db, Str => Try({}, Sqlite.QueryError)
add_todo! = |db, task| {
	transaction = Sqlite.begin!(db, Immediate)?
	transaction.execute!({
		query: "INSERT INTO todos (task, status) VALUES (:task, 'todo');",
		params: { task },
	})?
	transaction.commit!()
}

# A statement reused across requests is prepared once and kept in the context.
count_todos! : Sqlite.Db => Try(I64, Sqlite.QueryError)
count_todos! = |db| {
	stmt = Sqlite.prepare!({ db, query: "SELECT count(*) FROM todos;" })?
	stmt.query!({}, Sqlite.default_query_limits)
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})
