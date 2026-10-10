## Scripting with Roc: one .roc file that does a job, run straight from a shell.
##
##   roc tool.roc csv sales.csv      # run it. Arguments follow the file
##   roc tool.roc -- --verbose       # `--` when an argument looks like a roc flag
##   roc test tool.roc               # run every `expect` in the file
##   roc fmt tool.roc                # format in place
##   roc build tool.roc              # standalone binary. The target needs no roc
##   roc bundle tool.roc             # .tar.zst others `roc install NAME URL`
##
## Put `#!/usr/bin/env roc` on line 1 and `chmod +x` to run it as `./tool.roc`:
## `#` starts a Roc comment, so a shebang is invisible to the compiler.
##
## The language and the standard library are elsewhere: see the `idioms`,
## `error_design`, `try_operator`, `strings` and `json` topics. Each effect API
## has its own topic too (`cli_app`, `cli_files`, `cli_http`, `cli_command`,
## `cli_terminal`). This topic connects them: from the arguments to the exit
## code, and the formats that a script reads and writes.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdin
import pf.Stdout
import parser.CSV
import parser.Parser
import parser.Utf8
import parser.Yaml

# One entry point, one dispatch, one place that turns a failure into a message
# and an exit code. The platform reads `Exit(code)` and does not print it. It
# prints every other Err with `Str.inspect` and exits 1.
main! : List(OsStr) => Try({}, _)
main! = |args| {
	result = match args.map(OsStr.display) {
		["csv", file] => report_csv!(Path.utf8(file))
		["config", file] => show_config!(Path.utf8(file))
		["grep", needle] => grep_stdin!(needle)
		["release"] => announce_release!()
		_ => Err(Usage)
	}
	match result {
		Ok({}) => Ok({})
		Err(err) => {
			(message, code) = explain(err)
			Stderr.line!(message)?
			Err(Exit(code))
		}
	}
}

# Matching a list of arguments is enough for subcommands and a positional or
# two. For real flags, use the weaver package. It turns a record of `Opt`
# fields into a typed config and writes `--help` for you.

# The union stays open (`..`) because every effect called above adds its own
# tag to it. The match names the tags that this script raises and inspects the
# rest, so it is exhaustive and does not list every platform error.
explain : [Usage, BadCsv(Str), BadConfig(Str), MissingKey(Str), ..] -> (Str, I32)
explain = |err|
	match err {
		Usage => ("usage: tool (csv FILE | config FILE | grep NEEDLE | release)", 2)
		BadCsv(why) => ("malformed CSV: ${why}", 1)
		BadConfig(why) => ("malformed config: ${why}", 1)
		MissingKey(key) => ("config is missing ${key}", 1)
		other => (Str.inspect(other), 1)
	}

expect explain(MissingKey("name")).0 == "config is missing name"

# --- CSV in, report out ------------------------------------------------------
#
# `CSV.parse` matches the header row to the record fields by name, and the
# annotation says which record. A field the header lacks is
# `MissingRequiredField`, so that tag must be in the annotation too. The
# `parser_csv` topic has the rest of the module.

Sale : { region : Str, units : U64 }

parse_sales : Str -> Try(List(Sale), [InvalidCsv(CSV.Error), MissingRequiredField(Str)])
parse_sales = |text| CSV.parse(text)

expect parse_sales("region,units\nnorth,3\nsouth,4\n") == Ok([{ region: "north", units: 3 }, { region: "south", units: 4 }])

report_csv! : Path => Try({}, _)
report_csv! = |path| {
	rows = parse_sales(path.read_utf8!()?) ? |err| BadCsv(Str.inspect(err))
	total = rows.map(|row| row.units).sum()

	# Annotate a list whose type the interpolation alone does not fix. A `${...}`
	# literal calls `from_interpolation` on an unknown type until something makes it Str.
	lines : List(Str)
	lines = rows
		.sort_by(|row| row.units)
		.map(|row| "${row.region}\t${row.units.to_str()}")
	Stdout.line!(Str.join_with(lines, "\n"))?
	Stdout.line!("total\t${total.to_str()}")?

	# Write through a temporary file and rename, so a reader of the report never
	# sees half of one. `rename!` within a directory is atomic.
	dest = Path.utf8("report.tsv")
	tmp = Path.utf8("report.tsv.tmp")
	tmp.write_utf8!(Str.join_with(lines, "\n").concat("\n"))?
	tmp.rename!(dest)
}

# --- YAML config -------------------------------------------------------------
#
# `Yaml.decode` builds the annotated record. A required key that is absent is
# `MissingRequiredField`. A key that may be absent is `Try(_, [Missing])`, and
# `??` gives its default. The `parser_yaml` topic also shows how to walk a tree.

Config : { name : Str, port : Try(U64, [Missing]) }

parse_config : Str -> Try(Config, [InvalidYaml(Yaml.Error), MissingRequiredField(Str)])
parse_config = |text| Yaml.decode(text)

expect parse_config("name: api\n").map_ok(|config| config.port ?? 8080) == Ok(8080)
expect parse_config("port: 1\n") == Err(MissingRequiredField("name"))

show_config! : Path => Try({}, _)
show_config! = |path| {
	config = parse_config(path.read_utf8!()?) ? |err|
		match err {
			# `err` also carries a one-based `line` and `column` for the message.
			InvalidYaml(problem) => BadConfig(problem.message)
			MissingRequiredField(key) => MissingKey(key)
		}
	Stdout.line!("${config.name} on ${(config.port ?? 8080).to_str()}")
}

# The package also parses XML (`parser.Xml`), Markdown with frontmatter
# (`parser.Markdown`), and raw HTTP messages (`parser.HTTP`). Each has a
# `parser_*` topic. JSON is not in this package. It is in the standard library,
# with derived codecs. See the `json` topic.

# For a format that has no module, build the parser from
# `parser.Parser` combinators over `parser.Utf8`. See `parser_combinators`.
duration : Parser(Utf8.Bytes, U64)
duration =
	Parser.const(|amount| |per_unit| amount * per_unit)
		.keep(Utf8.digits)
		.keep(Parser.one_of([Utf8.string("m").map(|_| 60), Utf8.string("s").map(|_| 1)]))

expect Utf8.parse_str(duration, "90s") == Ok(90)
expect Utf8.parse_str(duration, "2m") == Ok(120)

# --- stdin to stdout ---------------------------------------------------------
#
# A script in a pipeline reads all of stdin, transforms, and writes. `Stdin.line!`
# (see `cli_terminal`) is for prompting a person. This code is for a pipe.

grep_stdin! : Str => Try({}, _)
grep_stdin! = |needle| {
	text = Str.from_utf8_lossy(Stdin.read_to_end!()?)
	for line in text.split_on("\n") {
		if line.contains(needle) {
			Stdout.line!(line)?
		}
	}
	Ok({})
}

# --- the outside world -------------------------------------------------------

announce_release! : () => Try({}, _)
announce_release! = || {
	# A subprocess for a fact that only that program can give. See `cli_command`.
	tag = Cmd.new("git").args(["describe", "--tags"]).exec_output!()?.stdout_utf8.trim()

	# A JSON API. The annotation tells the decoder what to build, so it is
	# required. See `cli_http`.
	latest : { tag_name : Str }
	latest = Http.get!("https://api.github.com/repos/roc-lang/roc/releases/latest")?

	# Environment variables are OsStr, because an OS does not promise text.
	# `??` is all you need for "optional with a default".
	channel = Env.var_str!("CHANNEL") ?? "stable"

	Stdout.line!("${tag} -> ${latest.tag_name} on ${channel}")
}
