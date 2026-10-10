## Every code snippet in corpus/platforms/basic-cli/overview.md, in one app. If
## the page stops matching the pinned platform,
## scripts/check-platform-examples.sh fails.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Cmd
import pf.Http
import pf.OsStr
import pf.Path
import pf.Sqlite
import pf.Stderr
import pf.Stdout
import http.Request
import http.Response

main! : List(OsStr) => Try({}, _)
main! = |args| {
	Stdout.line!("Hello, World!")?
	Stdout.line!("${args.len().to_str()} args")?
	Ok({})
}

## The paths section.
paths! : () => Try({}, _)
paths! = || {
	config : Path
	config = "app/config.toml"

	text = config.read_utf8!()?
	config.write_utf8!(text)?
	kids = Path.utf8("app").list!()?

	Stdout.line!("${kids.len().to_str()} entries")?
	Ok({})
}

## The error section: the error holds the failing path.
report! : Path => Try({}, _)
report! = |missing|
	match missing.read_utf8!() {
		Err(PathErr(NotFound, path)) => Stderr.line!("no such file: ${path.display()}")
		Err(err) => Err(ReadFailed(err))
		Ok(content) => Stdout.line!(content)
	}

## The commands section.
head_of_git! : () => Try({}, _)
head_of_git! = || {
	out = Cmd.new("git").args(["rev-parse", "HEAD"]).exec_output!()?
	Stdout.line!(out.stdout_utf8)?
	Ok({})
}

## The HTTP client section.
fetch! : () => Try({}, _)
fetch! = || {
	body = Http.get_utf8!("https://example.com")?
	res = Http.send!(Request.from_method(GET).with_uri("https://example.com"))?
	code = Response.status(res)
	Stdout.line!("${body} ${code.to_str()}")?
	Ok({})
}

## The SQLite section.
todos! : () => Try({}, _)
todos! = || {
	rows = Sqlite.query_many!({
		path: "todos.db",
		query: "SELECT id, task FROM todos WHERE status = :status;",
		bindings: [{ name: ":status", value: String("todo") }],
		rows: |cols| |stmt| Ok({ id: Sqlite.i64("id")(cols)(stmt)?, task: Sqlite.str("task")(cols)(stmt)? }),
	})?
	Stdout.line!("${rows.len().to_str()} rows")?
	Ok({})
}
