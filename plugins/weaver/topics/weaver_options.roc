# Fields: what `Opt` and `Param` take, and the three record rules that decide
# whether a constructor accepts yours.
#
# An `Opt` is named on the command line (`-v`, `--verbose`). A `Param` is
# positional. Both come in the same three shapes (one required value, one
# optional value, a repeatable list), and the shape decides the record.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.OsStr
import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param

Config : {
	# Opt.flag is Bool, Opt.count is U64. Neither takes a value.
	force : Bool,
	verbosity : U64,
	# A required-value option: `default` decides whether it is really required.
	region : Str,
	replicas : U64,
	# maybe_* is `Try(a, [NoValue])`: absent and empty are different answers.
	note : Try(Str, [NoValue]),
	# *_list collects every occurrence, and is empty rather than absent.
	labels : List(Str),
	# Parameters, in the order they are declared.
	image : Str,
	extra : List(Str),
}

main! : List(OsStr) => Try({}, _)
main! = |args|
	match Cli.parse_or_display_message(parser, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => Stdout.line!(message)
		Err(InvalidUsage(message)) => {
			Stdout.line!(message)?
			Err(Exit(1))
		}
		Ok(config) => Stdout.line!(Str.inspect(config))
	}

parser : Cli.CliParser(Config)
parser =
	Cli.assert_valid(
		Cli.finish(
			{
				# Rule one: every option record carries both `short` and `long`.
				# Leaving one out is a missing-field error. Use `""` to say that
				# an option has no short form or no long form.
				force: Opt.flag({ short: "f", long: "", help: "Do it anyway." }),

				# A short flag repeats, and `-vvv` counts three.
				verbosity: Opt.count({ short: "v", long: "verbose", help: "Say more, repeatably." }),

				# Rule two: `default` belongs to exactly the required-value
				# constructors. `Value(x)` supplies one, `Generate(fn)` computes
				# one per run, and `NoDefault` is what makes the option required.
				region: Opt.str({ short: "", long: "region", help: "Where.", default: Value("us-east-1") }),
				replicas: Opt.u64({ short: "r", long: "replicas", help: "How many.", default: NoDefault }),

				# The same record without `default`: passing one to a `maybe_*`,
				# a `flag`, a `count` or a `*_list` is a type error, because
				# those constructors take the base record and Roc records are
				# exact.
				note: Opt.maybe_str({ short: "n", long: "note", help: "Anything to add." }),
				labels: Opt.str_list({ short: "l", long: "label", help: "Repeatable KEY=VALUE." }),

				# Rule three: parameters take `name` where options take `short`
				# and `long`. `name` is what the help page and the usage line
				# print, and it is not matched on the command line.
				image: Param.str({ name: "image", help: "What to deploy.", default: NoDefault }),

				# A list parameter takes everything left, so nothing may follow.
				extra: Param.str_list({ name: "extra", help: "Anything else." }),
			}.Cli,
			{
				name: "fields",
				version: "1.0.0",
				authors: [],
				description: "Every field shape weaver offers, once each.",
				text_style: Plain,
			},
		),
	)

# Every numeric width has the same three shapes, named for the type:
# `Opt.u8`/`maybe_u8`/`u8_list` through `u128`, the signed widths, `Opt.dec`,
# `Opt.f32`, `Opt.f64`. `Opt.single`, `Opt.maybe` and `Opt.list` take a
# `parser` and a `type` name and cover anything else. `type` is the word that
# the usage line prints for the value, so use a word from the app's own domain.
#
# A value that begins with `-` reads as another option. Pass it as
# `--replicas=-1` or put `--` in front of it. `--replicas -1` is a missing
# option value.
