## Standard streams, raw mode, and the small effects around them: environment,
## clock, sleep, random seeds, locale.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst" }

import pf.Env
import pf.Locale
import pf.OsStr
import pf.Random
import pf.Sleep
import pf.Stderr
import pf.Stdin
import pf.Stdout
import pf.Tty
import pf.Utc

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# `line!` appends a newline. `write!` does not. `write_bytes!` takes bytes,
	# not UTF-8 text. Stderr has the same three.
	Stdout.write!("name: ")?
	Stderr.line!("(prompting)")?

	# `Stdin.line!` strips the trailing newline and returns Err(EndOfFile) when
	# there is no more input. That is an ordinary end, not a failure, so match it.
	name = match Stdin.line!() {
		Ok(line) => line
		Err(EndOfFile) => "world"
		Err(StdinErr(err)) => return Err(ReadFailed(err))
	}
	Stdout.line!("hello, ${name}")?

	timing!()?
	environment!()?
	Ok({})
}

## `Utc.now!` is U128 nanoseconds since the epoch. The deltas take the later
## instant first, and they never go negative because the result is unsigned.
timing! : () => Try({}, _)
timing! = || {
	start = Utc.now!()
	Sleep.millis!(50)
	finish = Utc.now!()

	Stdout.line!("started ${Utc.to_iso_8601(start)}")?
	Stdout.line!("took ${Utc.delta_as_millis(finish, start).to_str()} ms")?
	Stdout.line!("     ${Utc.delta_as_nanos(finish, start).to_str()} ns")?
	Ok({})
}

## Environment variables are `OsStr` in and `OsStr` out, because they are not
## guaranteed to be text. `var_str!` requires the value to be text.
environment! : () => Try({}, _)
environment! = || {
	editor = match Env.var!("EDITOR") {
		Ok(value) => value.display()
		Err(VarNotFound(_)) => "vi"
		Err(err) => return Err(EnvLookupFailed(err))
	}
	Stdout.line!("editor: ${editor}")?

	home = Env.var_str!("HOME") ?? "/"
	Stdout.line!("home: ${home}")?

	cwd = Env.cwd!()?
	Stdout.line!("cwd: ${cwd.display()}")?
	Stdout.line!("exe: ${Env.exe_path!()?.display()}")?
	Stdout.line!("tmp: ${Env.temp_dir!().display()}")?

	# The full environment, as pairs.
	Stdout.line!("${Env.dict!().len().to_str()} variables set")?

	# Build target, at run time.
	host = Env.platform!()
	Stdout.line!(Str.inspect(host.os))?
	Ok({})
}

## Raw mode turns off line buffering and echo, so `Stdin.bytes!` returns the
## keystroke rather than waiting for Enter. Turn it back off before you exit, or
## you leave the user's terminal in that state.
read_one_key! : () => Try(List(U8), _)
read_one_key! = || {
	Tty.enable_raw_mode!()
	key = Stdin.bytes!()
	Tty.disable_raw_mode!()
	key
}

## `Random` gives seeds, not numbers. Give a seed to a generator. The platform
## has no generator.
seed! : () => Try(U64, _)
seed! = || Random.seed_u64!()

## Locale is a parsed BCP 47 tag. `get!` is the user's, `all!` is their ordered
## preference list.
locales! : () => Try(List(Str), _)
locales! = || {
	preferred = Locale.all!()
	Ok(preferred.map(|l| l.to_str()))
}

expect Locale.parse("en-GB").map_ok(|l| l.to_str()) == Ok("en-GB")
