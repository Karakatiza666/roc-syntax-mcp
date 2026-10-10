## A deployment CLI whose field record is bound once and finished separately.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.OsStr
import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param

# capture:start
DeployConfig : {
	dry_run : Bool,
	environment : Str,
	labels : List(Str),
	region : Str,
	replicas : U64,
	target_image : Str,
}

deploy_fields = {
	dry_run: Opt.flag(dry_run_option),
	environment: Opt.str(environment_option),
	labels: Opt.str_list(label_option),
	region: Opt.str(region_option),
	replicas: Opt.u64(replicas_option),
	target_image: Param.str(image_parameter),
}.Cli

# capture:end

main! : List(OsStr) => Try({}, _)
main! = |args|
	match Cli.parse_or_display_message(cli_parser, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => Stdout.line!(message)
		Err(InvalidUsage(message)) => {
			Stdout.line!(message)?
			Err(Exit(1))
		}
		Ok(config) => {
			Stdout.line!("Deployment plan:")?
			Stdout.line!(Str.inspect(config))
		}
	}

cli_parser : Cli.CliParser(DeployConfig)
cli_parser =
	Cli.assert_valid(
		Cli.finish(
			deploy_fields,
			{
				name: "deploy",
				version: "v0.1.0",
				authors: ["Acme Platform Team <platform@example.com>"],
				description: "Roll out a container image to one deployment environment.",
				text_style: Color,
			},
		),
	)

dry_run_option = {
	short: "n",
	long: "dry-run",
	help: "Print the deployment plan without applying it.",
}

environment_option = {
	short: "e",
	long: "environment",
	help: "Target environment, such as staging or production.",
	default: NoDefault,
}

image_parameter = {
	name: "image",
	help: "Container image and tag to deploy.",
	default: NoDefault,
}

label_option = {
	short: "l",
	long: "label",
	help: "Attach a repeatable KEY=VALUE label.",
}

region_option = {
	short: "",
	long: "region",
	help: "Cloud region. [default: us-east-1]",
	default: Value("us-east-1"),
}

replicas_option = {
	short: "r",
	long: "replicas",
	help: "Number of service replicas. [default: 3]",
	default: Value(3),
}
