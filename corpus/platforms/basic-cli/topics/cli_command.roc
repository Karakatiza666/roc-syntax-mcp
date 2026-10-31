## Running other programs: four runners, one error. `call!` for the simple case,
## `capture!` for the text, `run!` for the status and bytes, `spawn!` for a child.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.Cmd
import pf.OsStr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# The simple case. Inherits your stdin, stdout and stderr, so the child's
	# output goes straight to the terminal and Roc never sees it. Anything but
	# exit code 0 is an error.
	Cmd.call!("echo", ["hello"])?

	# To see the output as text, `capture!`. It fails when the exit code is not
	# 0, and when the output is not UTF-8.
	head = Cmd.new("git").args(["rev-parse", "--short", "HEAD"]).capture!()?
	Stdout.line!("HEAD is ${head.trim()}")?

	# To see everything as data, `run!`. A non-zero exit code is the `status`, not
	# an error. The bytes are never decoded, and `require_success()` turns a bad
	# status back into an error that carries the output.
	out = Cmd.new("cat").args(["/dev/null"]).run!()?
	Stdout.line!("${out.stdout_bytes.len().to_str()} bytes")?
	Stdout.line!("stderr was ${out.stderr_utf8_lossy()}")?

	# A controlled environment. `clear_envs` drops the inherited one, then `env`
	# adds back exactly what the child should see. Inspecting the command shows
	# the names of the variables and never their values.
	Cmd.new("/usr/bin/env")
		.clear_envs()
		.env("LANG", "C")
		.env("PATH", "/usr/bin")
		.call!()?

	# Only the exit status. Here a non-zero code is the result, not an error.
	status = Cmd.new("test").args(["-f", "/etc/hosts"]).inherit_stdio().run!()?.status
	Stdout.line!("test exited ${Str.inspect(status)}")?

	# Check before you run. This checks PATH without executing anything.
	if Cmd.check_available!("rg") {
		Cmd.call!("rg", ["--version"])?
	} else {
		Stdout.line!("ripgrep is not installed")?
	}

	Ok({})
}

## A `Cmd.Command` is a plain value until a runner takes it, so building one is
## pure and you can pass it around, log it, or test it. `Cmd` is the namespace;
## the type of a builder is `Cmd.Command`.
git : List(Str) -> Cmd.Command
git = |args| Cmd.new("git").args(args.map(OsStr.from_str))

expect git(["status"]).to_str() == "git status"

## Every runner reports the command in its error, so a failure is readable and
## you do not have to pass the arguments along yourself.
try_git! : List(Str) => Try(Str, _)
try_git! = |args| {
	text = git(args).capture!() ? |err| GitFailed(err)
	Ok(text)
}

## `args` and `arg` take `OsStr` values, and a string literal is one. A list of
## `Str` that you computed becomes a list of `OsStr` with `OsStr.from_str`.
exact : Cmd.Command
exact = Cmd.new("ls").arg("-la")

computed : List(Str) -> Cmd.Command
computed = |names| Cmd.new("ls").args(names.map(OsStr.from_str))
