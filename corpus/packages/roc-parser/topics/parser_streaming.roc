## Input too large to hold in memory, with lukewilliamboswell/roc-parser 6.0:
## build a decoder (`CSV.decoder`, `CSV.typed_decoder`,
## `JsonValue.record_decoder`, `QIF.transaction_decoder`, `OFX.decoder`,
## `Xml.decoder`, `HTTP.Request.decoder`), feed it chunks of bytes with
## `read_iter` or `read_stream`, and write with an encoder's `write_stream`.
## The package does no I/O: basic-cli's `Stdin.chunks()` and
## `File.open_reader!` give the chunks.
##
## A chunk may end anywhere: inside a UTF-8 character, a quoted CSV field or a
## JSON string. An empty chunk does not end the input. Only the end of the
## source does, and then the decoder checks that the document is complete.
##
## Full manual: decoders, completion, error policies and memory limits:
## https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/streaming.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import pf.OsStr
import pf.Stdin
import pf.Stdout
import parser.CSV
import parser.JsonValue
import parser.QIF

# Chunks as a pure `Iter(List(U8))`, cut in awkward places on purpose: inside
# the quoted field and between `\r` and `\n`.
csv_chunks : Iter(List(U8))
csv_chunks = ["name,note\r\nbolt,\"a, ", "b\"\r", "\nnut,c\r\n"].map(Str.to_utf8).iter()

# --- Pull events until Finished ----------------------------------------------
#
# `decoder.read_iter(chunks)` is an `Iter` of `Try` events: `Ok(Value(item))`,
# `Ok(Rejected(problem))` (only when the error policy reports), and one final
# `Ok(Finished(report))`. A terminal failure is one `Err` with the format's
# own tag, such as `InvalidCsv`. Read through `Finished`: stopping early
# leaves the rest unchecked. Keep only the newest state; do not collect what
# you can process and drop.
count_records : Iter(List(U8)) -> Try(U64, _)
count_records = |chunks| {
	var $count = 0
	for event in CSV.decoder({}).read_iter(chunks) {
		match event? {
			Value(_record) => {
				$count = $count + 1
			}

			Rejected(_) => {}
			Finished(_report) => return Ok($count)
		}
	}
	Err(MissingFinished)
}

# The raw decoder gives `CSV.Record` rows, the header included.
expect count_records(csv_chunks) == Ok(3)

# `collect(chunks)` gathers every value, and fails on a rejection or a missing
# `Finished`. It keeps all output in memory, so use it for tests and small
# input.
expect CSV.decoder({}).collect(csv_chunks).map_ok(|rows| rows.map(|row| row.map(Str.from_utf8_lossy))) == Ok([["name", "note"], ["bolt", "a, b"], ["nut", "c"]])

# --- Typed rows, and an error policy -----------------------------------------
#
# `CSV.typed_decoder(props)` decodes rows into the annotated record, as
# `CSV.decode_str` does. `errors: { policy: ReportInvalidRecords }` turns a row
# that fails to decode into a `Rejected` event and goes on; the default
# `FailFast` stops. Broken CSV syntax is terminal under every policy.
# `collect_report` keeps the values, the rejections and the counts.
Part : { name : Str, qty : U64 }

parts : Str -> Try({ values : List(Part), errors : List(_), report : _ }, _)
parts = |text| CSV.typed_decoder({ errors: { policy: ReportInvalidRecords } }).collect_report([text.to_utf8()].iter())

expect parts("name,qty\nbolt,4\nnut,many\nwasher,9\n").map_ok(|r| (r.values.len(), r.errors.len(), r.report.rejected_records)) == Ok((2, 1, 1))

# --- JSON Lines and arrays ---------------------------------------------------
#
# `JsonValue.record_decoder({})` emits one `JsonValue` per NDJSON line;
# `framing: Array` emits the items of one top-level array instead.
expect JsonValue.record_decoder({}).collect(["{\"e\":1}\n{\"e\"", ":2}\n"].map(Str.to_utf8).iter()).map_ok(List.len) == Ok(2)
expect JsonValue.record_decoder({ framing: Array }).collect(["[1, 2", ", 3]"].map(Str.to_utf8).iter()).map_ok(List.len) == Ok(3)

# --- Banking files -----------------------------------------------------------
#
# QIF and OFX have the same shape. Amounts stay text, exactly as written.
qif = "!Type:Bank\nD27/08/2024\nT-12.3400\nPCafe\n^\n"

payees : Str -> Try(List(Str), _)
payees = |text| {
	var $found = []
	for event in QIF.transaction_decoder({}).read_iter([text.to_utf8()].iter()) {
		match event? {
			Value(Transaction(row)) => {
				$found = $found.append("${row.payee} ${row.amount}")
			}

			_ => {}
		}
	}
	Ok($found)
}

expect payees(qif) == Ok(["Cafe -12.3400"])

# --- From stdin to stdout, in bounded memory ---------------------------------
#
# `Stdin.chunks()` is an effectful `Stream`, so use `read_stream` or
# `values_stream`, and loop with `for!`. `values_stream` gives the values
# alone and fails at the end unless the decoder reached `Finished`. An
# encoder's `write_stream` turns values into output chunks of at most
# `chunk_bytes` (64 KiB by default). This canonicalizes CSV from a pipe:
#
#   roc streaming.roc < in.csv > out.csv
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	for! chunk in CSV.encoder({ line_ending: Lf }).write_stream(CSV.decoder({}).values_stream(Stdin.chunks())) {
		Stdout.write_bytes!(chunk?)?
	}
	Ok({})
}
