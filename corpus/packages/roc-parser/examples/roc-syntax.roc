app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/3.0.0/6xsRdRqenJrAb4wG7HaST4Xh349vD5sHAJDsKTK6E3dr.tar.zst",
}

import cli.Stdout
import parser.RocSyntax

main! = |_args| {
	source = "# Example Roc source\nanswer = 1 + 2 * 3\n"
	parsed = RocSyntax.parse_str(source)
	Stdout.line!("parse: ${Str.inspect(parsed.status)}, ${parsed.nodes.len().to_str()} syntax nodes")?
	lexed = RocSyntax.tokenize_str(source)
	for token in lexed.tokens {
		category = RocSyntax.highlight_category(token.kind)
		if category != Trivia {
			text = Str.from_utf8(lexed.source.sublist({ start: token.start, len: token.end - token.start })) ?? ""
			Stdout.line!("${Str.inspect(category)} ${token.start.to_str()}..${token.end.to_str()}: ${text}")?
		}
	}
	Ok({})
}
