# Type-checks and tests every language topic, and checks the claims that the
# topics make in comments.
#
# Usage: roc scripts/check-topics.roc -- <roc> <topics dir> <work dir> [topic...]
#
# With topic names, the script checks only those topics.
#
# A topic is a fragment, so this script appends a `main!` to it. The topic must
# pass `roc check` and `roc test`. A topic states that some code fails with a
# comment block:
#
#   # @rejects effectful top level value
#   # message = greet!("Sam")
#
# The block is the comment lines after the marker, up to a bare `#` or a line
# that is not a comment. The script removes `# ` and the common indent, then
# compiles the block after the whole topic, so the block can use the names that
# the topic defines. `@rejects` needs an error with that title. `@warns` needs a
# warning with that title and no error.
#
# The script writes its files to <work dir>, and exits 1 if any check fails.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout

Kind : [Rejects, Warns]

Claim : { kind : Kind, title : Str, block : Str }

main! : List(OsStr) => Try({}, _)
main! = |args| {
	match args.map(OsStr.display) {
		[roc, topics, work, .. as only] => {
			failed = check_all!(roc, Path.utf8(topics), Path.utf8(work), only)?
			if failed > 0 Err(Exit(1)) else Ok({})
		}
		_ => {
			Stderr.line!("usage: roc scripts/check-topics.roc -- <roc> <topics dir> <work dir> [topic...]")?
			Err(Exit(2))
		}
	}
}

## Checks the topics named in `only`, or every topic when `only` is empty.
## Prints one line per check, and returns how many checks failed.
check_all! : Str, Path, Path, List(Str) => Try(U64, _)
check_all! = |roc, topics, work, only| {
	files = topics.list!()?.keep_if(|p| p.display().ends_with(".roc")).sort_with(|a, b| order(a.display(), b.display()))
	var $failed = 0
	for file in files {
		name = file.filename()?.display().drop_suffix(".roc")
		if only.is_empty() or only.contains(name) {
			text = file.read_utf8!()?
			$failed = $failed + check_topic!(roc, work, name, text)?
		}
	}
	Ok($failed)
}

## Checks one topic and its claims. Returns how many checks failed.
check_topic! : Str, Path, Str, Str => Try(U64, _)
check_topic! = |roc, work, name, text| {
	wrapped = work.join("${name}.roc")
	wrapped.write_utf8!(with_main(text))?
	checked = compile!(roc, ["check", "--no-color", wrapped.display()])?
	if !checked.contains("No errors found") {
		report!("FAIL  ${name}", checked)?
		return Ok(1)
	}
	tested = compile!(roc, ["test", "--no-color", wrapped.display()])?
	if !tests_passed(tested) {
		report!("FAIL  ${name} (roc test)", tested)?
		return Ok(1)
	}
	Stdout.line!("ok    ${name}")?

	var $failed = 0
	var $n = 0.U64
	for claim in claims(text) {
		$n = $n + 1
		file = work.join("claim_${name}_${$n.to_str()}.roc")
		file.write_utf8!(with_main("${text}\n${claim.block}"))?
		output = compile!(roc, ["check", "--no-color", file.display()])?
		label = "${name} ${marker_text(claim.kind)} ${claim.title}"
		if holds(claim, output) {
			Stdout.line!("ok    ${label}")?
		} else {
			report!("FAIL  ${label}", "${claim.block}\n---\n${output}")?
			$failed = $failed + 1
		}
	}
	Ok($failed)
}

## Runs the compiler and returns stdout and stderr together. A non-zero exit is
## a result here, because a rejected block exits non-zero.
compile! : Str, List(Str) => Try(Str, _)
compile! = |roc, args| {
	out = Cmd.new_str(roc).args_str(args).merge_stderr(True).timeout_ms(300_000).run!()?
	Ok(Str.from_utf8_lossy(out.stdout_bytes))
}

report! : Str, Str => Try({}, _)
report! = |headline, detail| {
	Stdout.line!(headline)?
	Stdout.line!(Str.join_with(detail.split_on("\n").map(|line| "      ${line}"), "\n"))
}

with_main : Str -> Str
with_main = |text| "${text}\nmain! = |_args| Ok({})\n"

tests_passed : Str -> Bool
tests_passed = |output| output.split_on("\n").any(|line| line.starts_with("All (") and line.contains(" tests passed"))

expect tests_passed("All (3) tests passed in 11.8 ms.")
expect !tests_passed("Ran 2 tests in 8.0 ms.:\n    1 passed\n    1 failed\n    0 compiler errors")
expect !tests_passed("    1 passed tests passed")

## Whether the compiler output agrees with the claim. A diagnostic title line
## reads `── ✗ <title> ───` for an error and `── ● <title> ───` for a warning.
holds : Claim, Str -> Bool
holds = |claim, output|
	match claim.kind {
		Rejects => output.contains("── ✗ ${claim.title} ─")
		Warns => output.contains("── ● ${claim.title} ─") and !output.contains("── ✗ ")
	}

expect holds({ kind: Rejects, title: "type mismatch", block: "" }, "── ✗ type mismatch ──── a.roc:3:1")
expect !holds({ kind: Rejects, title: "type mismatch", block: "" }, "── ✗ effectful top level value ── a.roc:3:1")
expect holds({ kind: Warns, title: "duplicate definition", block: "" }, "── ● duplicate definition ── a.roc:3:2")
expect !holds({ kind: Warns, title: "duplicate definition", block: "" }, "── ● duplicate definition ──\n── ✗ type mismatch ──")
expect !holds({ kind: Warns, title: "duplicate definition", block: "" }, "── ● unused variable ──\nThe duplicate definition of x")

marker_text : Kind -> Str
marker_text = |kind|
	match kind {
		Rejects => "@rejects"
		Warns => "@warns"
	}

marker : Str -> Try({ kind : Kind, title : Str }, [NotMarker])
marker = |line|
	if line.starts_with("# @rejects ") {
		Ok({ kind: Rejects, title: line.drop_prefix("# @rejects ").trim() })
	} else if line.starts_with("# @warns ") {
		Ok({ kind: Warns, title: line.drop_prefix("# @warns ").trim() })
	} else {
		Err(NotMarker)
	}

## Every marked block of a topic, in file order.
claims : Str -> List(Claim)
claims = |text| {
	var $done = []
	var $open = Err(NoBlock)
	for line in text.split_on("\n") {
		match marker(line) {
			Ok(found) => {
				$done = close($done, $open)
				$open = Ok({ kind: found.kind, title: found.title, lines: [] })
			}
			Err(NotMarker) =>
				match $open {
					Ok(block) if line.starts_with("# ") or line.starts_with("#\t") => {
						$open = Ok({ ..block, lines: block.lines.append(line.drop_prefix("#").drop_prefix(" ")) })
					}
					_ => {
						$done = close($done, $open)
						$open = Err(NoBlock)
					}
				}
		}
	}
	close($done, $open)
}

close : List(Claim), Try({ kind : Kind, title : Str, lines : List(Str) }, [NoBlock]) -> List(Claim)
close = |done, open|
	match open {
		Ok(block) => done.append({ kind: block.kind, title: block.title, block: Str.join_with(dedent(block.lines), "\n") })
		Err(NoBlock) => done
	}

expect {
	text =
		\\greet! = |name| echo!(name)
		\\
		\\# @rejects effectful top level value
		\\# message = greet!("Sam")
		\\#
		\\# @warns duplicate definition
		\\#   f = |x| {
		\\#   	foo = 0
		\\#   }
		\\# @rejects type mismatch
		\\#   x : Str
		\\x = 1
	claims(text)
		== [
			{ kind: Rejects, title: "effectful top level value", block: "message = greet!(\"Sam\")" },
			{ kind: Warns, title: "duplicate definition", block: "f = |x| {\n\tfoo = 0\n}" },
			{ kind: Rejects, title: "type mismatch", block: "x : Str" },
		]
}

## Removes the indent that every non-blank line shares.
dedent : List(Str) -> List(Str)
dedent = |lines| {
	common = lines.keep_if(|line| !line.trim().is_empty()).map(indent).min() ?? 0
	lines.map(|line| Str.from_utf8_lossy(line.to_utf8().drop_first(common)))
}

expect dedent(["  a", "    b", "", "  c"]) == ["a", "  b", "", "c"]
expect dedent(["\ta", "\t\tb"]) == ["a", "\tb"]

## The count of leading spaces and tabs.
indent : Str -> U64
indent = |line| {
	var $n = 0
	for byte in line.to_utf8() {
		if byte == 32 or byte == 9 {
			$n = $n + 1
		} else {
			break
		}
	}
	$n
}

## Byte order of two strings, so that the output order does not depend on the
## order that the file system lists the topics in.
order : Str, Str -> [Before, Same, After]
order = |a, b| {
	x = a.to_utf8()
	y = b.to_utf8()
	var $i = 0
	var $result = if x.len() < y.len() Before else if x.len() > y.len() After else Same
	for byte in x {
		other = y.get($i) ?? 0
		if $i >= y.len() {
			break
		}
		if byte < other {
			$result = Before
			break
		}
		if byte > other {
			$result = After
			break
		}
		$i = $i + 1
	}
	$result
}

expect order("loops", "loops_x") == Before
expect order("numbers", "loops") == After
expect order("loops", "numbers") == Before
expect order("a", "a") == Same
