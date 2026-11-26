## Every snippet on overview.md, in one app, so that the page always matches
## code that compiles.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import pf.Stdout
import parser.Parser
import parser.CSV
import parser.HTTP
import parser.Markdown
import parser.Xml

setting : Parser(Parser.Utf8.Bytes, { key : Str, port : U64 }, _)
setting = Parser.const(|key| |port| { key, port }).keep(Parser.Utf8.string("port")).skip(Parser.Utf8.codeunit('=')).keep(Parser.Utf8.digits({}))

Row : { name : Str, qty : U64 }

rows : Try(List(Row), [InvalidCsv(CSV.Error)])
rows = CSV.decode_str("name,qty\nbolt,4\n", {})

expect setting.parse_str("port=80") == Ok({ key: "port", port: 80 })
expect setting.run_str("port=80;") == Ok({ value: { key: "port", port: 80 }, rest: ";" })
expect rows == Ok([{ name: "bolt", qty: 4 }])

main! = |_args| {
	_doc = Xml.parse_str("<a/>", {})?
	blocks = Markdown.parse_str("# Hi", {})
	req = HTTP.Request.parse_bytes("GET / HTTP/1.1\r\nHost: x\r\n\r\n".to_utf8(), {})?
	Stdout.line!("${blocks.len().to_str()} ${req.target}")?
	Ok({})
}
