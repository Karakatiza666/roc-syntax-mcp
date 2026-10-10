## The basic-cli application contract: `main!`, arguments, exit codes, and where
## to turn error tags into messages.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.OsStr
import pf.IOErr
import pf.Path
import pf.Stdout
import pf.Stderr

# An app provides exactly one function. The header names it, and the platform's
# `requires` clause fixes its type. It takes a list of native arguments and
# returns `Try({}, ...)`. Annotate the error as `_` so that the union stays
# open, because every effect you call adds its own tag to it.
main! : List(OsStr) => Try({}, _)
main! = |args| {
	# From 0.24.0, `args` holds only the real arguments, and `Env.program_name!`
	# gives the program name. Older code that calls `args.drop_first(1)` loses a
	# real argument.
	match args {
		[] => usage!()
		[path_arg, ..] => run!(Path.from_os_str(path_arg))
	}
}

usage! : () => Try({}, _)
usage! = || {
	Stderr.line!("usage: wc <file>")?
	# The platform reads `Exit(code)` and does not print it. It prints every
	# other Err with `Str.inspect` and exits 1.
	Err(Exit(2))
}

# Inside the program, fail with tags. A tag carries the values that a message
# needs, costs nothing, and the compiler can check it.
run! : Path => Try({}, _)
run! = |path| {
	text = path.read_utf8!() ? |err| CouldNotRead(err)
	lines = text.split_on("\n").len()
	Stdout.line!("${lines.to_str()} lines")?
	Ok({})
}

# Turn tags into text in exactly one place, at the edge of the program. If you
# do it earlier, you lose the structure. If you never do it, the user reads
# `Str.inspect` output.
explain : [CouldNotRead([PathErr(IOErr, Path), ..])] -> Str
explain = |err|
	match err {
		CouldNotRead(PathErr(NotFound, path)) => "no such file: ${path.display()}"
		CouldNotRead(PathErr(PermissionDenied, path)) => "cannot read ${path.display()}"
		CouldNotRead(PathErr(other, path)) => "${path.display()}: ${other.to_str()}"
		CouldNotRead(other) => Str.inspect(other)
	}

expect explain(CouldNotRead(PathErr(NotFound, Path.utf8("a.txt")))) == "no such file: a.txt"

# Arguments are not always text. `OsStr` has the three forms that an operating
# system gives, and `to_raw` lets you branch on them.
describe_arg : OsStr -> Str
describe_arg = |arg|
	match OsStr.to_raw(arg) {
		Utf8(str) => "utf-8: ${str}"
		UnixBytes(bytes) => "${bytes.len().to_str()} raw bytes"
		WindowsU16s(units) => "${units.len().to_str()} utf-16 code units"
	}

expect describe_arg(OsStr.utf8("hi")) == "utf-8: hi"

# `OsStr.display` gives a lossy string for a message. `OsStr.to_str_try`
# returns an error and not a damaged string.
show : OsStr -> Str
show = |arg| arg.display()

strict : OsStr -> Try(Str, [InvalidStr(U64)])
strict = |arg| OsStr.to_str_try(arg)
