## Files and directories: `Path` is the whole API, and every failure returns
## the failing path with the error.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.Env
import pf.File
import pf.IOErr
import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Utc

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

	# Metadata. File times are `Utc` values, and `since` gives a `Duration`.
	size = config.size_in_bytes!()?
	modified = config.time_modified!()?
	age = Utc.now!().since(modified)
	Stdout.line!("${size.to_str()} bytes, modified ${age.to_str()} ago")?

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

## `File` is for incremental work. To read a large file one line at a time,
## without loading all of it into memory, loop over `lines()`. A line that is not
## valid UTF-8 is one `Err(BadUtf8(_))` item, and the loop carries on. A failure
## of the file itself is the last item.
count_lines! : Path => Try(U64, _)
count_lines! = |path| {
	# `open_reader!` carries no annotation upstream, so its result needs one here
	# before `lines` can dispatch on it.
	reader : File.Reader
	reader = File.open_reader!(path)?
	var $count = 0.U64
	for! item in reader.lines() {
		match item {
			Ok(_) => { $count = $count + 1 }
			Err(BadUtf8(_)) => { $count = $count + 1 }
			Err(FileErr(err)) => { return Err(FileErr(err)) }
		}
	}
	Ok($count)
}

## To write a file piece by piece, open a writer. `with_writer!` flushes when
## the callback returns, and reports a failed flush. The mode is `Truncate`,
## `Append` or `RequireNew`, and the third argument holds the options: `{}`
## keeps the operating system's default permissions.
write_report! : Path, List({ name : Str, total : U64 }) => Try({}, [PathErr(IOErr, Path), FileErr(IOErr)])
write_report! = |path, rows|
	File.with_writer!(
		path,
		Truncate,
		{},
		|writer| {
			writer.write_utf8!("name,total\n")?
			for row in rows {
				writer.write_utf8!("${row.name},${row.total.to_str()}\n")?
			}
			Ok({})
		},
	)
