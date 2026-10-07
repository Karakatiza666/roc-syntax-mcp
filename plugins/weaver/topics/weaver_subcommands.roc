## Subcommands: one tag union per level, `SubCmd.finish` per command, and where
## they sit in the parent's field order.
##
## A subcommand is an ordinary builder plus a name, a description and a mapper
## that lifts its own data into the parent's union. It nests: a subcommand's
## builder may itself carry `SubCmd.optional`.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.OsStr
import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param
import weaver.SubCmd

## One variant per command, each carrying that command's own config record.
Command : [
	Build({ release : Bool, target : Str }),
	Clean({ deep : Bool }),
]

Config : {
	quiet : Bool,
	# `SubCmd.optional` gives `Try(_, [NoSubcommand])`. `SubCmd.required` gives
	# the union bare and reports `NoSubcommandCalled` when none was named.
	command : Try(Command, [NoSubcommand]),
	root : Str,
}

main! : List(OsStr) => Try({}, _)
main! = |args|
	match Cli.parse_or_display_message(parser, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => Stdout.line!(message)
		Err(InvalidUsage(message)) => {
			Stdout.line!(message)?
			Err(Exit(1))
		}
		Ok(config) =>
			match config.command {
				Err(NoSubcommand) => Stdout.line!("no command under ${config.root}")
				Ok(Build({ release, target })) =>
					Stdout.line!("build ${target}, release ${Str.inspect(release)}")

				Ok(Clean({ deep })) => Stdout.line!("clean, deep ${Str.inspect(deep)}")
			}
		}

parser : Cli.CliParser(Config)
parser =
	Cli.assert_valid(
		Cli.finish(
			{
				# Subcommands sit between the options and the parameters, and
				# the stage types enforce it: `SubCmd.optional` goes from
				# `GetOptionsAction` to `GetParamsAction`, so an `Opt` after it
				# and a `Param` before it are both type errors.
				quiet: Opt.flag({ short: "q", long: "quiet", help: "Say less." }),
				command: SubCmd.optional([build, clean]),
				root: Param.str({ name: "root", help: "Project root.", default: Value(".") }),
			}.Cli,
			{
				name: "work",
				version: "1.0.0",
				authors: [],
				description: "Two commands and a positional root.",
				text_style: Plain,
			},
		),
	)

## Annotate each subcommand. Without the annotation, the compiler infers the
## union from what the mappers build, and a typo in one variant shows up as a
## mismatch at `SubCmd.optional`, not here.
build : SubCmd.SubcommandParserConfig(Command)
build =
	SubCmd.finish(
		{
			release: Opt.flag({ short: "r", long: "release", help: "Optimise." }),
			target: Param.str({ name: "target", help: "What to build.", default: NoDefault }),
		}.Cli,
		# `mapper` is what lifts this command's record into the parent's union.
		{ name: "build", description: "Build the project.", mapper: |data| Build(data) },
	)

## A subcommand whose builder would have one field runs into the record
## builder's two-field minimum, so this one uses `Cli.map` for the same reason
## `topics/weaver_builder.roc` does.
clean : SubCmd.SubcommandParserConfig(Command)
clean =
	SubCmd.finish(
		Cli.map(
			Opt.flag({ short: "d", long: "deep", help: "Remove caches too." }),
			# `{ deep }` here reads as a block returning `deep`, not as a record,
			# so the mapper has to name the field: the union variant would
			# otherwise come out as `Clean(Bool)`.
			|deep| { deep: deep },
		),
		{ name: "clean", description: "Remove build output.", mapper: |data| Clean(data) },
	)

# `SubCmd.empty` is the third constructor: a command that takes nothing and
# yields a fixed value, for a bare verb like `version` or `doctor`.
