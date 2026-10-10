## Nested subcommands: two levels, each a tag union lifted by its own mapper.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.OsStr
import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param
import weaver.SubCmd

SubSubcommandConfig : [
	SS1({ a : U64, b : U64 }),
	SS2({ a : U64, c : U64, data : Str }),
]

FirstSubcommandConfig : {
	d : Try(U64, [NoValue]),
	volume : Try(U64, [NoValue]),
	sc : Try(SubSubcommandConfig, [NoSubcommand]),
}

SubcommandConfig : [
	S1(FirstSubcommandConfig),
	S2([DFlag(Try(U64, [NoValue]))]),
]

RootConfig : {
	force : Bool,
	sc : Try(SubcommandConfig, [NoSubcommand]),
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

cli_parser : Cli.CliParser(RootConfig)
cli_parser =
	Cli.assert_valid(
		Cli.finish(
			{
				force: Opt.flag({
					short: "f",
					long: "",
					help: "Force the task to complete.",
				}),
				sc: SubCmd.optional([subcommand_parser1, subcommand_parser2]),
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
				name: "subcommands",
				version: "v0.0.1",
				authors: ["Some One <some.one@mail.com>"],
				description: "This is a basic example of what you can build with Weaver. You get safe parsing, useful error messages, and help pages all for free!",
				text_style: Color,
			},
		),
	)

subcommand_parser1 : SubCmd.SubcommandParserConfig(SubcommandConfig)
subcommand_parser1 =
	SubCmd.finish(
		{
			d: Opt.maybe_u64({
				short: "d",
				long: "",
				help: "A non-overlapping subcommand flag with s2.",
			}),
			volume: Opt.maybe_u64({
				short: "v",
				long: "volume",
				help: "How loud to grind the gears.",
			}),
			sc: SubCmd.optional([sub_subcommand_parser1, sub_subcommand_parser2]),
		}.Cli,
		{
			name: "s1",
			description: "A first subcommand.",
			mapper: |data| S1(data),
		},
	)

subcommand_parser2 : SubCmd.SubcommandParserConfig(SubcommandConfig)
subcommand_parser2 =
	SubCmd.finish(
		Cli.map(
			Opt.maybe_u64({
				short: "d",
				long: "",
				help: "This doesn't overlap with s1's -d flag.",
			}),
			|d_flag| DFlag(d_flag),
		),
		{
			name: "s2",
			description: "Another subcommand.",
			mapper: |data| S2(data),
		},
	)

sub_subcommand_parser1 : SubCmd.SubcommandParserConfig(SubSubcommandConfig)
sub_subcommand_parser1 =
	SubCmd.finish(
		{
			a: Opt.u64({
				short: "a",
				long: "",
				help: "An example short flag for a sub-subcommand.",
				default: NoDefault,
			}),
			b: Opt.u64({
				short: "b",
				long: "",
				help: "Another example short flag for a sub-subcommand.",
				default: NoDefault,
			}),
		}.Cli,
		{
			name: "ss1",
			description: "A sub-subcommand.",
			mapper: |data| SS1(data),
		},
	)

sub_subcommand_parser2 : SubCmd.SubcommandParserConfig(SubSubcommandConfig)
sub_subcommand_parser2 =
	SubCmd.finish(
		{
			a: Opt.u64({
				short: "a",
				long: "",
				help: "Set the alpha level.",
				default: NoDefault,
			}),
			c: Opt.u64({
				short: "c",
				long: "create",
				help: "Create a doohickey.",
				default: NoDefault,
			}),
			data: Param.str({
				name: "data",
				help: "Data to manipulate.",
				default: NoDefault,
			}),
		}.Cli,
		{
			name: "ss2",
			description: "Another sub-subcommand.",
			mapper: |data| SS2(data),
		},
	)
