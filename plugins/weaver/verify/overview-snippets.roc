## Every fenced snippet on overview.md, in one app, so that the page always
## matches code that compiles. `plugin validate` fails the page when a block on it is
## in no app under `checks`.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.OsStr
import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param

Config : { force : Bool, region : Str, image : Str, rest : List(Str) }

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
				force: Opt.flag({ short: "f", long: "force", help: "Do it anyway." }),
				region: Opt.str({ short: "", long: "region", help: "Where.", default: Value("us-east-1") }),
				image: Param.str({ name: "image", help: "What to deploy.", default: NoDefault }),
				rest: Param.str_list({ name: "rest", help: "Anything else." }),
			}.Cli,
			{ name: "deploy", version: "1.0.0", authors: [], description: "Ship it.", text_style: Plain },
		),
	)

solo = Cli.map(
	Opt.u64({ short: "l", long: "level", help: "How hard.", default: NoDefault }),
	|level| Level(level),
)

expect
	Cli.parse_or_display_message(parser, ["-f", "img", "x"], |arg| Utf8(arg))
		== Ok({ force: True, region: "us-east-1", image: "img", rest: ["x"] })

## Kept live so the one-field shape above is compiled rather than described.
solo_parser : Cli.CliParser([Level(U64)])
solo_parser =
	Cli.assert_valid(
		Cli.finish(solo, { name: "solo", version: "1.0.0", authors: [], description: "", text_style: Plain }),
	)

expect solo_parser.config.name == "solo"
