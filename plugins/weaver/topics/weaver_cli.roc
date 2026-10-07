## The whole contract, end to end: build a parser, run it, and answer the three
## things it can hand back.
##
## Weaver is a package, not a platform. An app pins a platform for its I/O and
## pins weaver beside it, and every program in this corpus has that two-line
## header. Nothing here is specific to basic-cli except `OsStr` and the
## converter. `topics/weaver_raw_args.roc` covers what changes on a platform
## that gives `main!` a `List(Str)`.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.OsStr
import pf.Stdout
import pf.Stderr
import weaver.Cli
import weaver.Opt
import weaver.Param

## The record the parser produces. One field per builder field, same names,
## same order. Writing it out is optional but useful. Without it, the compiler
## infers the config type from the builder and reports every mistake at the
## call site, not here.
Config : {
	verbose : Bool,
	out : Str,
	inputs : List(Str),
}

main! : List(OsStr) => Try({}, _)
main! = |args|
# Weaver never drops an argument of its own. basic-cli 0.24.0 already leaves
# the program name out of `args` (it is `Env.program_name!`), so pass `args`
# whole. A leftover `args.drop_first(1)` from an older basic-cli compiles and
# then silently loses the first real argument.
#
# `match`, not `?`. `?` type-checks, but it would send Help and Version out
# of `main!` as errors. Then the page is never printed and the exit code is not 0.
	match Cli.parse_or_display_message(parser, args, OsStr.to_raw) {
		# Help and Version are successes inside an `Err`. Weaver has already
		# rendered the page. The app prints it and exits zero.
		Err(Help(message)) | Err(Version(message)) => Stdout.line!(message)

		Err(InvalidUsage(message)) => {
			Stderr.line!(message)?
			Err(Exit(1))
		}

		Ok(config) => {
			Stdout.line!("out: ${config.out}")?
			Stdout.line!("verbose: ${Str.inspect(config.verbose)}")?
			Stdout.line!("inputs: ${Str.join_with(config.inputs, ", ")}")
		}
	}

## `Cli.assert_valid` is evaluated at compile time. So a configuration that
## weaver rejects (two options sharing a short flag, an ill-formed name,
## overlapping parameters) fails `roc check` with weaver's own crash message,
## and does not reach a run. Handling the `Try` from `Cli.finish` by hand is the
## documented alternative and warns here instead: the configuration is built
## from literals, so the compiler already knows which branch the match takes and
## reports an unconditional condition.
parser : Cli.CliParser(Config)
parser =
	Cli.assert_valid(
		Cli.finish(
			# Source order is parse order, and it is type-checked: options, then
			# subcommands, then parameters, with a list parameter last. See
			# `topics/weaver_builder.roc` for what the compiler says otherwise.
			{
				verbose: Opt.flag({ short: "v", long: "verbose", help: "Say more." }),
				out: Opt.str({ short: "o", long: "out", help: "Where to write.", default: Value("-") }),
				inputs: Param.str_list({ name: "inputs", help: "Files to read." }),
			}.Cli,
			# All five fields are required. `text_style` is `Color` for ANSI help
			# and diagnostics, `Plain` for output that is redirected or for an
			# application honouring NO_COLOR.
			{
				name: "weave",
				version: "1.0.0",
				authors: ["Example <nobody@example.com>"],
				description: "Read some files and write them somewhere.",
				text_style: Plain,
			},
		),
	)

## A parser is testable without a platform, a binary or a shell. Feed it a
## `List(Str)` and the identity converter, and compare against the record you
## expect. `roc test` runs it. `roc check` does not.
expect
	Cli.parse_or_display_message(parser, ["-v", "-o", "log", "a.txt"], |arg| Utf8(arg))
		== Ok({ verbose: True, out: "log", inputs: ["a.txt"] })

## The same shape checks the failures, which is where a CLI actually goes wrong.
## A missing required parameter is an `InvalidUsage`, and an unknown flag is one
## too. Both carry weaver's rendered message, not a tag to match on.
expect
	match Cli.parse_or_display_message(parser, ["--nope"], |arg| Utf8(arg)) {
		Err(InvalidUsage(_)) => True
		_other => False
	}
