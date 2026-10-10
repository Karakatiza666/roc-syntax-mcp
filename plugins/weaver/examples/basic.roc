## A flag, a number, an optional parameter and a list, in one record builder.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.OsStr
import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param

BasicConfig : {
	alpha : U64,
	force : Bool,
	file : Try(Str, [NoValue]),
	files : List(Str),
}

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

cli_parser : Cli.CliParser(BasicConfig)
cli_parser =
	Cli.assert_valid(
		Cli.finish(
			{
				alpha: Opt.u64({
					short: "a",
					long: "",
					help: "Set the alpha level.",
					default: NoDefault,
				}),
				force: Opt.flag({
					short: "f",
					long: "",
					help: "Force the task to complete.",
				}),
				file: Param.maybe_str({
					name: "file",
					help: "The file to process.",
				}),
				files: Param.str_list({
					name: "files",
					help: "The rest of the files.",
				}),
			}.Cli,
			{
				name: "basic",
				version: "v0.0.1",
				authors: ["Some One <some.one@mail.com>"],
				description: "This is a basic example of what you can build with Weaver. You get safe parsing, useful error messages, and help pages all for free!",
				text_style: Color,
			},
		),
	)
