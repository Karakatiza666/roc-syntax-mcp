## CSV text into your own Roc types with lukewilliamboswell/roc-parser 2.0:
## `CSV.parse` into records chosen by the annotation, `parse_normalized` for
## loose header spelling, `parse_headerless` into tuples, `parse_records` and
## `split_header` for raw bytes, and `parse_with` for a hand-built row parser.
##
## Every call returns `Try(_, [InvalidCsv(CSV.Error), ..])`. `CSV.Error` is
## `{ record, field, line, column, message }`, all one-based.
##
## `CSV.Format.*` and `CSV.State` are the decoding protocol that `CSV.parse`
## uses through static dispatch. Never call them. 2.0 has no `CSV.parse_str`.
##
## Full manual: rows into records, optional columns, files without a header,
## raw fields, hand-built row parsers, error reports, and which files are
## accepted: https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/csv.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst",
}

import pf.Stdout
import parser.CSV
import parser.Parser

# --- Rows into records -------------------------------------------------------
#
# The first row names the columns. Each field reads the column with exactly its
# name, in any order. Other columns are ignored.

Product : { name : Str, quantity : U64, price : Dec }

# The annotation picks the row type. Without one, `CSV.parse` fails to
# compile: "dispatch a method named parser_for on an unresolved type variable".
#
# The compiler adds `MissingRequiredField(Str)` to the error of any record with
# a required field. A closed error row without it is a compile error. Name it,
# or write the error row as `_`.
products : Str -> Try(List(Product), [InvalidCsv(CSV.Error), MissingRequiredField(Str)])
products = |text| CSV.parse(text)

expect products("price,name,quantity\n0.15,bolt,250\n") == Ok([{ name: "bolt", quantity: 250, price: 0.15 }])

# Header names match exactly: case counts, and a byte order mark is kept as
# part of the first name. Both show up as a missing column.
expect products("Name,quantity,price\nbolt,1,1\n") == Err(MissingRequiredField("name"))
expect products("\u(FEFF)name,quantity,price\nbolt,1,1\n") == Err(MissingRequiredField("name"))

# The separator is always `,`. A `;` file is one column named "name;quantity;price".
expect products("name;quantity;price\nbolt;1;1\n") == Err(MissingRequiredField("name"))

# --- Cells -------------------------------------------------------------------
#
# Nothing is trimmed. A `Str` keeps its spaces, and a number with a space fails.
# Numbers use a data grammar, not Roc literals: `1_000` and `0x10` fail, `+40`
# and `.5` pass. Tags are matched by exact name, and `Bool` takes only
# `true` or `false` in any case.

cell_error : Str -> Str
cell_error = |text|
	match products(text) {
		Err(InvalidCsv({ message, .. })) => message
		_ => "no error"
	}

expect cell_error("name,quantity,price\nbolt, 250,1\n") == "expected a U64, found ` 250`"
expect cell_error("name,quantity,price\nbolt,1_000,1\n") == "expected a U64, found `1_000`"

# An empty cell is not zero. It fails for a number unless the field allows it.
expect cell_error("name,quantity,price\nbolt,,1\n") == "expected a U64, found ``"

# --- Optional columns and empty cells ----------------------------------------
#
# `Try(a, [Missing])` is `Err(Missing)` when the column is absent.
# `Try(a, [Null])` is `Err(Null)` when the cell is empty.
# `parse_normalized` matches `First Name`, `first-name` and `FIRST_NAME` to
# `first_name`.

Contact : { first_name : Str, email : Try(Str, [Missing]), age : Try(U64, [Null]), status : [Active, Inactive] }

contacts : Str -> Try(List(Contact), [InvalidCsv(CSV.Error), MissingRequiredField(Str)])
contacts = |text| CSV.parse_normalized(text)

expect
	contacts("First Name,Age,Status\nAda,,Active\n")
	== Ok([{ first_name: "Ada", email: Err(Missing), age: Err(Null), status: Active }])

# --- Row width ---------------------------------------------------------------
#
# Every row must have as many fields as the header, so a stray comma cannot
# shift values into the wrong column. Blank lines are skipped.

expect cell_error("name,quantity,price\nbolt,1,1,extra\n") == "the record has 4 fields, more than the 3 columns"
expect products("name,quantity,price\n\nbolt,1,1\n\n").map_ok(List.len) == Ok(1)

# --- No header: tuples -------------------------------------------------------

points : Str -> Try(List((Str, F64, F64)), [InvalidCsv(CSV.Error)])
points = |text| CSV.parse_headerless(text)

expect points("home,-33.87,151.21\n") == Ok([("home", -33.87, 151.21)])

# --- Raw fields --------------------------------------------------------------
#
# `CSV.Record` is `List(List(U8))`. Quoted fields may hold `,`, line breaks
# and `""`. Here a blank line is a record with one empty field.

expect CSV.parse_records("a,\"b,c\"\n\nd\n") == Ok([["a".to_utf8(), "b,c".to_utf8()], [[]], ["d".to_utf8()]])

# --- A hand-built row parser -------------------------------------------------
#
# For a cell that needs custom handling. `CSV.record` takes one curried
# argument per column, and each `.keep(CSV.field(...))` reads the next column by
# position. A field parser is any `Parser(Utf8.Bytes, a)`.

Movie : { title : Str, year : U64, cast : List(Str) }

movie : Parser(CSV.Record, Movie)
movie =
	CSV.record(|title| |year| |actors| { title, year, cast: actors })
		.keep(CSV.field(CSV.string))
		.keep(CSV.field(CSV.u64))
		.keep(CSV.field(CSV.string.map(|text| text.split_on(";"))))

expect CSV.parse_with(movie, "Airplane!,1980,Robert Hays;Julie Hagerty\n") == Ok([{ title: "Airplane!", year: 1980, cast: ["Robert Hays", "Julie Hagerty"] }])

# `parse_with` treats every row as data, so a header row fails as a value.
# Split it off first, then `CSV.decode` the rest. `decode` cannot see the
# text, so its `line` and `column` are 0.
with_header : Str -> Try(List(Movie), [InvalidCsv(CSV.Error)])
with_header = |text| {
	{ header: _, rows } = CSV.split_header(CSV.parse_records(text)?)
	CSV.decode(movie, rows)
}

expect with_header("title,year,cast\nAirplane!,1980,Robert Hays\n").map_ok(List.len) == Ok(1)

# A row with more fields than `.keep` calls is an error, not ignored.
expect
	match CSV.parse_with(movie, "Airplane!,1980,Robert Hays,extra\n") {
		Err(InvalidCsv({ message, .. })) => message == "the record has 4 fields, but the parser read only 3"
		_ => Bool.False
	}

report : Str -> Str
report = |text|
	match products(text) {
		Ok(found) => "${found.len().to_str()} products"
		Err(InvalidCsv({ line, column, message, .. })) => "line ${line.to_str()}, column ${column.to_str()}: ${message}"
		Err(MissingRequiredField(name)) => "no column named ${name}"
	}

main! = |_args| Stdout.line!(report("name,quantity,price\nbolt,250,0.15\nnut,x,0.05\n"))
