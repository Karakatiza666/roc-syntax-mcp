## Where the arguments come from: the converter, the raw tag union, and the
## `path.Path` values three constructors hand back.
##
## Weaver reads arguments as `path.Path`, never as `Str`, because an argument on
## disk is bytes on Unix and UTF-16 code units on Windows, and decoding it early
## loses a filename that is neither. `Cli.parse_or_display_message` takes the
## converter as its third argument so the platform decides how its own argument
## type becomes those raw bytes.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
	# Naming a `Path` in an annotation means pinning the package it comes from,
	# at the release weaver itself pins: `roc-lang/path` 4.0.0. Package identity
	# here is content, not a version string, so a different release produces a
	# mismatch that reports `Path` where `Path` was wanted, and names neither
	# release.
	path: "https://github.com/roc-lang/path/releases/download/4.0.0/7YfABZPwJAXtLBY2vm8FqMyGAtNxncCJ65HdNKHFGNnE.tar.zst",
}

import pf.OsStr
import pf.Stdout
import path.Path
import weaver.Cli
import weaver.Opt
import weaver.Param

Config : {
	# `Opt.str` and `Param.str` decode at the parser boundary and hand back
	# `Str`. `Opt.arg`, `Opt.maybe_arg`, `Opt.arg_list`, `Param.arg`,
	# `Param.maybe_arg` and `Param.arg_list` keep the raw value instead.
	label : Str,
	# `Param.maybe_arg` is the one `maybe_*` that does not return
	# `Try(a, [NoValue])` under its own name. Upstream types it as
	# `Parser.ArgValue`, and `weaver.Parser` is not a public module of the
	# package, so `import weaver.Parser` is refused. `ArgValue` is an alias for
	# `Try(Path.Path, [NoValue])`, which is what an app writes instead.
	target : Try(Path.Path, [NoValue]),
	rest : List(Path.Path),
}

## basic-cli hands `main!` a `List(OsStr)` and `OsStr.to_raw` is the converter,
## so nothing in the app decodes anything. A platform whose `main!` takes
## `List(Str)` needs an adapter of its own, which is the shape upstream's
## examples use on the Zig platform template:
##
##     str_to_raw_arg : Str -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]
##     str_to_raw_arg = |arg| UnixBytes(Str.to_utf8(arg))
##
## Weaver never drops an argument. basic-cli 0.25.0 does not put the program
## name in `args`, so pass them whole. A platform that puts the executable path in
## `args[0]`, as that template does, needs `args.drop_first(1)`. Without it, the
## app compiles and then consumes the executable path as the first parameter.
## At runtime, the parser then reports the first real argument as unexpected.
main! : List(OsStr) => Try({}, _)
main! = |args|
	match Cli.parse_or_display_message(parser, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => Stdout.line!(message)
		Err(InvalidUsage(message)) => {
			Stdout.line!(message)?
			Err(Exit(1))
		}
		Ok(config) => {
			Stdout.line!("label ${config.label}")?
			# A `Path` is decoded when the app decides to, and the decode can
			# fail: a filename that is not valid UTF-8 is a real argument.
			match config.target {
				Err(NoValue) => Stdout.line!("no target")
				Ok(target) =>
					match Path.to_str(target) {
						Ok(text) => Stdout.line!("target ${text}")
						Err(_) => Stdout.line!("target is not valid UTF-8")
					}
				}?
			Stdout.line!("${Str.inspect(List.len(config.rest))} more")
		}
	}

parser : Cli.CliParser(Config)
parser =
	Cli.assert_valid(
		Cli.finish(
			{
				label: Opt.str({ short: "l", long: "label", help: "A decoded string.", default: Value("") }),
				target: Param.maybe_arg({ name: "target", help: "Kept as raw bytes." }),
				rest: Param.arg_list({ name: "rest", help: "Also raw." }),
			}.Cli,
			{
				name: "rawargs",
				version: "1.0.0",
				authors: [],
				description: "Decoded and raw arguments side by side.",
				text_style: Plain,
			},
		),
	)
