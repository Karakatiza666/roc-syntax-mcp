## Running other programs: `Cmd.exec!` for the simple case, a chained `Cmd` when
## you need the output, the environment, or the exit code.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.Cmd
import pf.OsStr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# The simple case. Inherits your stdin, stdout and stderr, so the child's
	# output goes straight to the terminal and Roc never sees it.
	Cmd.exec!("echo", ["hello"])?

	# To see the output, build a Cmd and capture it. `exec_output!` decodes
	# stdout as UTF-8 and fails if it is not UTF-8. `exec_output_bytes!` never
	# fails that way.
	out = Cmd.new("git").args(["rev-parse", "--short", "HEAD"]).exec_output!()?
	Stdout.line!("HEAD is ${out.stdout_utf8.trim()}")?
	Stdout.line!("stderr was ${out.stderr_utf8_lossy}")?

	raw = Cmd.new("cat").args(["/dev/null"]).exec_output_bytes!()?
	Stdout.line!("${raw.stdout_bytes.len().to_str()} bytes")?

	# A controlled environment. `clear_envs` drops the inherited one, then `env`
	# adds back exactly what the child should see.
	Cmd.new("/usr/bin/env")
		.clear_envs()
		.env_str("LANG", "C")
		.env_str("PATH", "/usr/bin")
		.exec_cmd!()?

	# Only the exit code. Here a non-zero code is the result, not an error.
	# `exec!` and `exec_cmd!` fail on a non-zero code, which is usually what you want.
	code = Cmd.new("test").args(["-f", "/etc/hosts"]).exec_exit_code!()?
	Stdout.line!("test exited ${code.to_str()}")?

	# Check before you run. This checks PATH without executing anything.
	if Cmd.check_available!("rg") {
		Cmd.exec!("rg", ["--version"])?
	} else {
		Stdout.line!("ripgrep is not installed")?
	}

	Ok({})
}

## A `Cmd` is a plain value until a runner takes it, so building one is pure and
## you can pass it around, log it, or test it.
git : List(Str) -> Cmd
git = |args| Cmd.new_str("git").args_str(args)

expect Cmd.to_str(git(["status"])).contains("git")

## Every runner reports the command in its error, so a failure is readable and
## you do not have to pass the arguments along yourself.
try_git! : List(Str) => Try(Str, _)
try_git! = |args| {
	out = git(args).exec_output!() ? |err| GitFailed(err)
	Ok(out.stdout_utf8)
}

## The builders that take arguments come in pairs. The `OsStr` form is exact.
## The `_str` form is for arguments that are text.
exact : Cmd
exact = Cmd.new(OsStr.utf8("ls")).arg(OsStr.utf8("-la"))

convenient : Cmd
convenient = Cmd.new_str("ls").arg_str("-la")
