## Standard streams, raw mode, and the small effects around them: environment,
## clock, sleep, random seeds, locale.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.Duration
import pf.Env
import pf.IOErr
import pf.Locale
import pf.OsStr
import pf.Monotonic
import pf.Random
import pf.Signal
import pf.Sleep
import pf.Stderr
import pf.Stdin
import pf.Stdout
import pf.System
import pf.Tty
import pf.Utc

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# `line!` appends a newline. `write!` does not. `write_bytes!` takes bytes,
	# not UTF-8 text. Stderr has the same three.
	Stdout.write!("name: ")?
	Stderr.line!("(prompting)")?

	# `Stdin.line!` strips the trailing newline and returns Err(EndOfInput) when
	# there is no more input. That is an ordinary end, not a failure, so match
	# it. An empty line is a real answer, `Ok("")`. A line that is not valid
	# UTF-8 is `Err(BadUtf8(_))`. Caught signals add a bare `Interrupted`.
	name = match Stdin.line!() {
		Ok(line) => line
		Err(EndOfInput) => "world"
		Err(BadUtf8(_)) => "world"
		Err(Interrupted) => return Err(Interrupted)
		Err(StdinErr(err)) => return Err(ReadFailed(err))
	}
	Stdout.line!("hello, ${name}")?

	timing!()?
	environment!()?
	Ok({})
}

## Time has types. `Utc` is a signed instant, for showing to people. `Monotonic`
## is an opaque clock reading, for measuring: `elapsed!` and `since` return a
## `Duration`, a non-negative length of time with nanosecond resolution. It adds,
## subtracts and compares, and clamps instead of going negative. Sleeping can
## fail, because a caught stop request returns `Err(Interrupted)`.
timing! : () => Try({}, _)
timing! = || {
	started = Utc.now!()
	start = Monotonic.now!()
	Sleep.millis!(50)?
	Duration.millis(50).sleep!()?

	Stdout.line!("started ${Utc.to_iso_8601(started)}")?
	Stdout.line!("took ${start.elapsed!().to_str()}")?
	Stdout.line!("since the start: ${Utc.now!().since(started).to_str()}")?
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

	# Build target, at run time. `.arch()` is `X64` or `Arm64`. `.os()` is
	# `Linux(os)`, `MacOS(os)` or `Windows(_)`, and the witness that a Unix match
	# yields enables Unix-only operations such as `Signal.catch!`.
	target = System.target!()
	Stdout.line!(Str.inspect(target.arch()))?
	match target.os() {
		Linux(os) => Signal.catch!([Interrupt, Terminate(os.unix())])?
		MacOS(os) => Signal.catch!([Interrupt, Terminate(os.unix())])?
		Windows(_) => Signal.catch!([Interrupt])?
	}
	Ok({})
}

## Catching a stop request lets cleanup run. Registered requests stay pending
## until `Signal.poll!()` acknowledges them. If `Interrupted` reaches `main!`, the
## platform restores the terminal and exits 130 for Interrupt or 143 for
## Terminate, without running your cleanup.
finish! : Try({}, [Interrupted, StdoutErr(IOErr)]) => Try({}, [Interrupted, StdoutErr(IOErr)])
finish! = |result|
	match result {
		Err(Interrupted) => {
			_pending = Signal.poll!()
			Stdout.line!("cleaning up")?
			Ok({})
		}
		other => other
	}

## Raw mode turns off line buffering and echo, so `Stdin.bytes!` returns the
## keystroke rather than waiting for Enter. Turn it back off before you exit, or
## you leave the user's terminal in that state.
read_one_key! : () => Try(List(U8), _)
read_one_key! = || {
	Tty.enable_raw_mode!()?
	key = Stdin.bytes!()?
	Tty.disable_raw_mode!()?
	Ok(key)
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
