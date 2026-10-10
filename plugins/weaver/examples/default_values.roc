## Defaults three ways: a literal `Value`, a computed `Generate`, and `NoDefault`.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.OsStr
import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param

DefaultValuesConfig : { alpha : U64, beta : Dec, file : Str }

main! : List(OsStr) => Try({}, _)
main! = |args| {
	match Cli.parse_or_display_message(cli_parser, args, OsStr.to_raw) {
		Err(Help(message)) => {
			Stdout.line!(message)?
			Ok({})
		}

		Err(Version(message)) => {
			Stdout.line!(message)?
			Ok({})
		}

		Err(InvalidUsage(message)) => {
			Stdout.line!(message)?
			Err(Exit(1))
		}

		Ok(data) => {
			Stdout.line!("Successfully parsed! Here's what I got:")?
			Stdout.line!("")?
			Stdout.line!(Str.inspect(data))?

			Ok({})
		}
	}
}

cli_parser : Cli.CliParser(DefaultValuesConfig)
cli_parser =
	Cli.assert_valid(
		Cli.finish(
			{
				alpha: Opt.u64({
					short: "a",
					long: "alpha",
					help: "Set the alpha level. [default: 123]",
					default: Value(123),
				}),
				beta: Opt.dec({
					short: "b",
					long: "beta",
					help: "Set the beta level. [default: 3.14]",
					default: Generate(|{}| 3.14),
				}),
				file: Cli.map(
					Param.maybe_str({
						name: "file",
						help: "The file to process. [default: NONE]",
					}),
					maybe_file_default,
				),
			}.Cli,
			{
				name: "default-values",
				version: "v0.0.1",
				authors: [],
				description: "",
				text_style: Color,
			},
		),
	)

maybe_file_default : Try(Str, [NoValue]) -> Str
maybe_file_default = |file|
	match file {
		Ok(path) => path
		Err(NoValue) => "NONE"
	}
