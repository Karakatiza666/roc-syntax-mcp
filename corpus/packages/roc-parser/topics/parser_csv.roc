## CSV text into your own Roc types with lukewilliamboswell/roc-parser 6.0:
## `CSV.decode_str(text, props)` into records chosen by the annotation, the
## `header` prop for loose header spelling or no header, `CSV.parse_str` and
## `split_header` for raw fields, and `CSV.rows_parser` for a hand-built row.
##
## Every call returns `Try(_, [InvalidCsv(CSV.Error)])`, and a hand-built row
## adds `InvalidRow`. `CSV.Error` is `Parser.Diagnostic(problem)`: a record of
## `problem` (a tag), `location` and `path`. A missing column is the problem
## `MissingRequiredField(name)` inside it, not a tag of its own.
##
## `CSV.Format.*` and `CSV.State` are the decoding protocol that `decode_str`
## uses through static dispatch. Never call them. A file too large for memory
## is read with `CSV.decoder` (the parser_streaming topic). A CSV literal can
## be checked at build time with `CSV.Decoded` (the parser_compile_time topic).
##
## Full manual: rows into records, optional columns, files without a header,
## raw fields, hand-built row parsers, error reports, and which files are
## accepted: https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/csv.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import pf.Stdout
import parser.CSV
import parser.Parser

# --- Rows into records -------------------------------------------------------
#
# The first row names the columns. Each field reads the column with exactly its
# name, in any order. Other columns are ignored. Pass `{}` for the defaults:
# the props argument is required.

Product : { name : Str, quantity : U64, price : Dec }

# The annotation picks the row type. The error row is `[InvalidCsv(CSV.Error)]`
# and nothing else: a record with required fields adds no tag of its own.
products : Str -> Try(List(Product), [InvalidCsv(CSV.Error)])
products = |text| CSV.decode_str(text, {})

expect products("price,name,quantity\n0.15,bolt,250\n") == Ok([{ name: "bolt", quantity: 250, price: 0.15 }])

# Match the problem, not a message string. `location` is `Text` with a
# zero-based byte `offset` and a one-based `line` and `column`.
csv_problem : Str -> Str
csv_problem = |text|
	match products(text) {
		Ok(_) => "ok"
		Err(InvalidCsv({ problem: MissingRequiredField(column), .. })) => "no column ${column}"
		Err(InvalidCsv({ problem: other, .. })) => Str.inspect(other)
	}

# Header names match exactly: case counts, and a byte order mark is kept as
# part of the first name. Both show up as a missing column.
expect csv_problem("Name,quantity,price\nbolt,1,1\n") == "no column name"
expect csv_problem("\u(FEFF)name,quantity,price\nbolt,1,1\n") == "no column name"

# The separator is always `,`. A `;` file is one column named "name;quantity;price".
expect csv_problem("name;quantity;price\nbolt;1;1\n") == "no column name"

# --- Cells -------------------------------------------------------------------
#
# Nothing is trimmed. A `Str` keeps its spaces, and a number with a space fails.
# Numbers use a data grammar, not Roc literals: `1_000` fails, `+40` and `.5`
# pass. An empty cell is not zero. The problem holds the expected type and an
# excerpt of the cell's bytes.
expect csv_problem("name,quantity,price\nbolt, 250,1\n") == "ExpectedValue({ expected: U64, source: { bytes: [32, 50, 53, 48], total_bytes: 4 } })"
expect csv_problem("name,quantity,price\nbolt,1_000,1\n").starts_with("ExpectedValue({ expected: U64")
expect products("name,quantity,price\nbolt,+40,.5\n") == Ok([{ name: "bolt", quantity: 40, price: 0.5 }])
expect csv_problem("name,quantity,price\nbolt,,1\n").starts_with("ExpectedValue({ expected: U64")

# Every row must have as many fields as the header, so a stray comma cannot
# shift values into the wrong column.
expect csv_problem("name,quantity,price\nbolt,1,1,extra\n") == "WidthMismatch({ expected: 3, found: 4 })"

# --- Optional columns and empty cells ----------------------------------------
#
# `Try(a, [Missing])` is `Err(Missing)` when the column is absent.
# `Try(a, [Null])` is `Err(Null)` when the cell is empty.
# `header: Normalized` matches `First Name`, `first-name` and `FIRST_NAME` to
# `first_name`. A tag column matches the tag name exactly.

Contact : { first_name : Str, email : Try(Str, [Missing]), age : Try(U64, [Null]), status : [Active, Inactive] }

contacts : Str -> Try(List(Contact), [InvalidCsv(CSV.Error)])
contacts = |text| CSV.decode_str(text, { header: Normalized })

expect
	contacts("First Name,Age,Status\nAda,,Active\n")
	== Ok([{ first_name: "Ada", email: Err(Missing), age: Err(Null), status: Active }])

# --- No header: tuples -------------------------------------------------------

points : Str -> Try(List((Str, F64, F64)), [InvalidCsv(CSV.Error)])
points = |text| CSV.decode_str(text, { header: Absent })

expect points("home,-33.87,151.21\n") == Ok([("home", -33.87, 151.21)])

# --- Raw fields --------------------------------------------------------------
#
# `CSV.parse_str` returns a `CSV` document, not a list. Its `.records` are
# `List(List(U8))`, and the header is an ordinary first record. Rows may differ
# in width here. Quoted fields may hold `,`, line breaks and `""`. A blank line
# is a record with one empty field.
expect CSV.parse_str("a,\"b,c\"\n\nd\n", {}).map_ok(|doc| doc.records) == Ok([["a".to_utf8(), "b,c".to_utf8()], [[]], ["d".to_utf8()]])

# `parse_string_records` gives the same records as `Str`.
expect CSV.parse_string_records("name,note\nAda,\"said \"\"hi\"\"\"\n", {}) == Ok([["name", "note"], ["Ada", "said \"hi\""]])

# `split_header` is a method of the document.
columns : Str -> Try(List(Str), [InvalidCsv(CSV.Error)])
columns = |text| Ok(CSV.parse_str(text, {})?.split_header().header)

expect columns("sku,count\nA1,3\n") == Ok(["sku", "count"])

# --- A hand-built row parser -------------------------------------------------
#
# For a cell that needs custom handling. `CSV.record` takes one curried
# argument per column, and each `.keep(CSV.field(...))` reads the next column
# by position. A field parser is any `Parser(Parser.Utf8.Bytes, a, _)`.
# `CSV.string({})` and `CSV.u64({})` are factories: call them.

Movie : { title : Str, year : U64, cast : List(Str) }

movie : Parser(CSV.Record, Movie, _)
movie =
	CSV.record(|title| |year| |actors| { title, year, cast: actors })
		.keep(CSV.field(CSV.string({})))
		.keep(CSV.field(CSV.u64({})))
		.keep(CSV.field(CSV.string({}).map(|text| text.split_on(";"))))

# `CSV.rows_parser({ row })` runs it over every row. It is a `Parser`, so its
# error is `ParseError` with `InvalidCsv` (bad CSV) or `InvalidRow` (a row the
# row parser rejected) inside the problem. A header row fails as a value.
movies : Str -> Str
movies = |text|
	match CSV.rows_parser({ row: movie }).parse_str(text) {
		Ok(found) => "${found.len().to_str()} movies"
		Err(ParseError({ problem: InvalidRow(row), .. })) => "${Str.inspect(row.path)}: ${Str.inspect(row.problem)}"
		Err(ParseError({ problem, .. })) => Str.inspect(problem)
	}

expect movies("Airplane!,1980,Robert Hays;Julie Hagerty\n") == "1 movies"

# With a header, parse the document, split the header off, and run
# `decode_rows` on a document of the remaining rows.
with_header : Str -> Try(List(Movie), _)
with_header = |text| {
	rows = CSV.parse_str(text, {})?.split_header().rows
	CSV.{ records: rows }.decode_rows({ row: movie })
}

expect with_header("title,year,cast\nAirplane!,1980,Robert Hays\n").map_ok(List.len) == Ok(1)

# A row with more fields than `.keep` calls is an error, not ignored.
expect movies("Airplane!,1980,Robert Hays,extra\n") == "[Record(1), Field(4)]: UnreadFields({ found: 4, read: 3 })"

report : Str -> Str
report = |text|
	match products(text) {
		Ok(found) => "${found.len().to_str()} products"
		Err(InvalidCsv({ problem: MissingRequiredField(column), .. })) => "no column named ${column}"
		Err(InvalidCsv({ location: Text({ line, column, .. }), problem: other, .. })) => "line ${line.to_str()}, column ${column.to_str()}: ${Str.inspect(other)}"
		Err(InvalidCsv({ problem: other, .. })) => Str.inspect(other)
	}

main! = |_args| Stdout.line!(report("name,quantity,price\nbolt,250,0.15\nnut,x,0.05\n"))
