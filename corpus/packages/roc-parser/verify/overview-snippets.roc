## Every snippet on overview.md, in one app, so that the page always matches
## code that compiles. It does not import Yaml, so the gate checks it against
## the release as published.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst",
}

import pf.Stdout
import parser.Parser
import parser.Utf8
import parser.CSV
import parser.HTTP
import parser.Markdown
import parser.Xml

setting : Parser(Utf8.Bytes, { key : Str, port : U64 })
setting = Parser.const(|key| |port| { key, port }).keep(Utf8.string("port")).skip(Utf8.codeunit('=')).keep(Utf8.digits)

Row : { name : Str, qty : U64 }

rows : Try(List(Row), [InvalidCsv(CSV.Error), MissingRequiredField(Str)])
rows = CSV.parse("name,qty\nbolt,4\n")

expect Utf8.parse_str(setting, "port=80") == Ok({ key: "port", port: 80 })
expect rows == Ok([{ name: "bolt", qty: 4 }])

main! = |_args| {
	_doc = Xml.parse_str("<a/>")?
	blocks = Markdown.parse_str("# Hi")
	req = HTTP.parse_request("GET / HTTP/1.1\r\nHost: x\r\n\r\n".to_utf8())?
	Stdout.line!("${blocks.len().to_str()} ${req.request.target}")?
	Ok({})
}
