## Files and directories: `Path` is the whole API, and every failure returns
## the failing path with the error.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.Env
import pf.File
import pf.IOErr
import pf.OsStr
import pf.Path
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# A string literal becomes a Path where an annotation says so. In an
	# expression position, where nothing says so, write Path.utf8.
	config : Path
	config = "demo/config.toml"

	Path.utf8("demo").create_all!()?

	# Whole-file reads and writes.
	config.write_utf8!("name = \"demo\"\n")?
	text = config.read_utf8!()?
	Stdout.line!(text)?

	bytes = config.read_bytes!()?
	config.write_bytes!(bytes)?

	# In-place substitution, without reading the file into Roc.
	config.replace_utf8!("demo", "example")?

	# Metadata. Times are U128 nanoseconds since the epoch, the same unit Utc uses.
	size = config.size_in_bytes!()?
	modified = config.time_modified!()?
	Stdout.line!("${size.to_str()} bytes, modified ${modified.to_str()}")?

	# Existence and kind. `type!` gives all four cases in one call. Three
	# separate calls can disagree with each other.
	match config.type!()? {
		IsFile => Stdout.line!("regular file")?
		IsDir => Stdout.line!("directory")?
		IsSymLink => Stdout.line!("symlink")?
		IsOther => Stdout.line!("something else")?
	}

	# Directories.
	entries = Path.utf8("demo").list!()?
	for entry in entries {
		Stdout.line!("  ${entry.display()}")?
	}

	# Path arithmetic is pure: no filesystem call, no failure.
	nested = Path.utf8("demo").join("logs").join("today.txt")
	Stdout.line!(nested.display())?

	Stdout.line!(file_label(nested))?

	# Cleanup. `delete_empty!` refuses a non-empty directory. `delete_all!` does
	# not, so use it only when you intend to delete everything.
	config.delete!()?
	Path.utf8("demo").delete_all!()?

	temp = Env.temp_dir!()
	Stdout.line!("temp dir: ${temp.display()}")?
	Ok({})
}

## `filename` and `ext` can fail, because a directory path has neither. The
## match takes a parameter: on the constant `nested` above, the compiler
## evaluates it at compile time and warns that the condition is unconditional.
file_label : Path -> Str
file_label = |path|
	match path.filename() {
		Ok(name) => name.display()
		Err(IsDirPath) => "no filename"
		Err(EndsInDots) => "no filename"
	}

## Errors carry the path. Match on the pair. Do not build the path again from a
## variable that is in scope.
read_or_default! : Path, Str => Try(Str, [PathErr(IOErr, Path)])
read_or_default! = |path, fallback|
	match path.read_utf8!() {
		Ok(text) => Ok(text)
		Err(PathErr(NotFound, _)) => Ok(fallback)
		Err(err) => Err(err)
	}

## `File` has one use: to read a large file one line at a time, without loading
## all of it into memory. `read_line!` returns an empty list at the end.
count_lines! : Path => Try(U64, _)
count_lines! = |path| {
	# `open_reader!` carries no annotation upstream, so its result needs one here
	# before `read_line!` can dispatch on it.
	reader : File.Reader
	reader = File.open_reader!(path)?
	helper! = |n| {
		line = reader.read_line!()?
		if line.len() == 0 Ok(n) else helper!(n + 1)
	}
	helper!(0)
}
