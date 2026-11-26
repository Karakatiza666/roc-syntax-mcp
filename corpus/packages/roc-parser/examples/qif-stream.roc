app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}
import cli.Stdin
import cli.Stdout
import parser.QIF
import parser.Parser

## Canonicalize QIF from stdin to stdout without retaining the document.
## Full success requires consuming the parser's Finished event.

main! = |_| {
	for! chunk in (QIF.encoder({})).write_stream((QIF.decoder({})).values_stream(Stdin.chunks())) {
		Stdout.write_bytes!(chunk?)?
	}
	Ok({})
}
