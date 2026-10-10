## The record builder: what `{ ... }.Cli` is, why the field order is checked,
## and the one shape it refuses.
##
## Every field is a `Builder.CliBuilder`, and `.Cli` folds them left to right
## with `Cli.map2`. The two type parameters after the data are phantom: each
## constructor declares the stage it may follow and the stage it leaves behind,
## so a wrong order of options -> subcommands -> parameters is a type error,
## not a runtime surprise.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.OsStr
import pf.Stdout
# `CliBuilder` and the three stage types are here, not in `Cli`. No example
# upstream imports this module, and the compiler names `Builder.CliBuilder` in
# every ordering error, so you need this import to write that type.
import weaver.Builder
import weaver.Cli
import weaver.Opt
import weaver.Param

Config : {
	force : Bool,
	level : U64,
	target : Str,
	rest : List(Str),
}

## The stages, and what each constructor does to them:
##
##     Opt.*          GetOptionsAction     -> GetOptionsAction
##     SubCmd.*       GetOptionsAction     -> GetParamsAction
##     Param.*        any                  -> GetParamsAction
##     Param.*_list   any                  -> StopCollectingAction
##
## `Cli.map2` requires the left field's outgoing stage to equal the right
## field's incoming stage, so an `Opt` after a `Param` reports
## `GetParamsAction` where `GetOptionsAction` was wanted, and anything after a
## list parameter reports `StopCollectingAction`, which is an empty tag union
## and accepts nothing.
fields : Builder.CliBuilder(Config, Builder.GetOptionsAction, Builder.StopCollectingAction)
fields = {
	force: Opt.flag({ short: "f", long: "force", help: "Do it anyway." }),
	level: Opt.u64({ short: "l", long: "level", help: "How hard.", default: Value(1) }),
	target: Param.str({ name: "target", help: "What to act on.", default: NoDefault }),
	rest: Param.str_list({ name: "rest", help: "Everything else." }),
}.Cli

## Two fields is the minimum. `{ only: Opt.flag(...) }.Cli` is rejected with
## "single-field record builder (minimum 2 fields required)", an unimplemented
## feature carrying no proper diagnostic, so a one-option CLI reads as a
## compiler bug rather than as a shape to avoid. `Cli.map` is the shape:
## one builder, one function, no record.
solo : Builder.CliBuilder([Level(U64)], Builder.GetOptionsAction, Builder.GetOptionsAction)
solo =
	Cli.map(
		Opt.u64({ short: "l", long: "level", help: "How hard.", default: NoDefault }),
		|level| Level(level),
	)

main! : List(OsStr) => Try({}, _)
main! = |args|
	match Cli.parse_or_display_message(parser, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => Stdout.line!(message)
		Err(InvalidUsage(message)) => {
			Stdout.line!(message)?
			Err(Exit(1))
		}
		Ok(config) => {
			Stdout.line!(Str.inspect(config))?
			Stdout.line!("the one-option CLI beside it is ${solo_parser.config.name}")
		}
	}

parser : Cli.CliParser(Config)
parser =
	Cli.assert_valid(
		Cli.finish(
			fields,
			{
				name: "builder",
				version: "1.0.0",
				authors: [],
				description: "Show what the record builder checks.",
				text_style: Plain,
			},
		),
	)

## The one-field CLI, finished, so the shape is compiled rather than described.
solo_parser : Cli.CliParser([Level(U64)])
solo_parser =
	Cli.assert_valid(
		Cli.finish(
			solo,
			{
				name: "solo",
				version: "1.0.0",
				authors: [],
				description: "One option, and so no record builder.",
				text_style: Plain,
			},
		),
	)
