# Compares the upstream langref at the pinned commit with a newer commit, one
# section at a time, and names the topics that carry each changed section.
#
# Usage, from the repo root:
#   roc scripts/langref-diff.roc -- <roc checkout> [commit]
#   roc scripts/langref-diff.roc -- --check-map
#
# The first form reads the pinned commit from corpus/language/UPSTREAM, and
# compares it with the given commit, or with HEAD of the checkout. The script
# fetches a commit that the checkout lacks, so a `git clone --depth 1` is
# enough. The report goes to stdout as markdown: every changed, added, removed
# and renamed section, its prose diff, and the topics that
# corpus/language/langref-map.txt names for the section.
#
# The second form checks that the map has exactly one line for each section of
# corpus/language/langref/. It exits 1 if not. src/langref.test.ts checks the
# same map against the parser in src/langref.ts, so this check also proves that
# the two parsers split the pages into the same sections.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout

## One unit of the langref. The key is `<page>` for the text between the `#`
## heading and the first `##`, and `<page>#<slug>` for a section.
Section : { key : Str, body : Str }

Change : [Changed(Str), Added(Str), Removed(Str), Renamed(Str, Str)]

langref_dir = "corpus/language/langref"
map_file = "corpus/language/langref-map.txt"
upstream_file = "corpus/language/UPSTREAM"

main! : List(OsStr) => Try({}, _)
main! = |args| {
	match args.map(OsStr.display) {
		["--check-map"] => check_map!()
		[repo] => diff!(repo, Err(Head))
		[repo, commit] => diff!(repo, Ok(commit))
		_ => {
			Stderr.line!("usage: roc scripts/langref-diff.roc -- (<roc checkout> [commit] | --check-map)")?
			Err(Exit(2))
		}
	}
}

# --- --check-map -------------------------------------------------------------

check_map! : () => Try({}, _)
check_map! = || {
	pages = Path.utf8(langref_dir).list!()?.keep_if(|p| p.display().ends_with(".md"))
	var $keys = []
	for page in pages {
		name = page.filename()?.display().drop_suffix(".md")
		$keys = $keys.concat(sections(name, page.read_utf8!()?).map(|s| s.key))
	}
	keys = $keys
	mapped = parse_map(Path.utf8(map_file).read_utf8!()?).map(|row| row.key)
	missing = keys.keep_if(|k| !mapped.contains(k))
	unknown = mapped.keep_if(|k| !keys.contains(k))
	for key in missing {
		Stdout.line!("missing from the map: ${key}")?
	}
	for key in unknown {
		Stdout.line!("in the map but not in the langref: ${key}")?
	}
	if missing.is_empty() and unknown.is_empty() {
		Stdout.line!("ok    ${map_file}: ${keys.len().to_str()} sections")
	} else {
		Err(Exit(1))
	}
}

# --- the diff ----------------------------------------------------------------

diff! : Str, Try(Str, [Head]) => Try({}, _)
diff! = |repo, wanted| {
	old = pinned_commit(Path.utf8(upstream_file).read_utf8!()?)?
	new = match wanted {
		Ok(commit) => commit
		Err(Head) => git_ok!(repo, ["rev-parse", "HEAD"])?.trim()
	}
	have!(repo, old)?
	have!(repo, new)?
	before = langref_at!(repo, old)?
	after = langref_at!(repo, new)?
	map = parse_map(Path.utf8(map_file).read_utf8!()?)
	found = changes(before, after)

	Stdout.line!("# Langref diff ${short(old)}..${short(new)}\n")?
	Stdout.line!(summary(found, review(found, map)))?
	stale = map.map(|row| row.key).keep_if(|k| !before.any(|s| s.key == k))
	if !stale.is_empty() {
		Stdout.line!("\nThe map names keys that the pinned commit does not have: ${Str.join_with(stale, ", ")}.")?
	}

	dir = Env.temp_dir!()
	for change in found {
		Stdout.line!("\n${headline(change, map)}")?
		match change {
			Changed(key) => Stdout.line!(prose_diff!(dir, body_of(before, key), body_of(after, key))?)?
			Renamed(_, _) => {}
			Added(key) => Stdout.line!(fenced(body_of(after, key)))?
			Removed(key) => Stdout.line!(fenced(body_of(before, key)))?
		}
	}
	Ok({})
}

## The first line of the report: how many sections changed in each way, and
## the topics to review.
summary : List(Change), List(Str) -> Str
summary = |found, topics| {
	count = |wanted| found.count_if(|c| kind(c) == wanted).to_str()
	listed = if topics.is_empty() "none" else Str.join_with(topics, ", ")
	"${count("changed")} changed, ${count("added")} added, ${count("removed")} removed, ${count("renamed")} renamed. Topics to review: ${listed}."
}

expect summary([Changed("a#x"), Added("a#y"), Added("a#z")], []) == "1 changed, 2 added, 0 removed, 0 renamed. Topics to review: none."

kind : Change -> Str
kind = |change|
	match change {
		Changed(_) => "changed"
		Added(_) => "added"
		Removed(_) => "removed"
		Renamed(_, _) => "renamed"
	}

## The heading of one change in the report, with the topics to review.
headline : Change, List({ key : Str, value : Str }) -> Str
headline = |change, map|
	match change {
		Changed(key) => "## Changed: ${key}\n\nTopics: ${mapped(map, key)}"
		Added(key) => "## Added: ${key}\n\nNot in the map yet. Add a line for it to ${map_file}."
		Removed(key) => "## Removed: ${key}\n\nTopics: ${mapped(map, key)}. Remove its line from the map."
		Renamed(from, to) => "## Renamed: ${from} to ${to}\n\nThe text is the same. Topics: ${mapped(map, from)}. Rename its key in the map."
	}

mapped : List({ key : Str, value : Str }), Str -> Str
mapped = |map, key|
	match map.find_first(|row| row.key == key) {
		Ok(row) => row.value
		Err(NotFound) => "none, because the map has no line for this key"
	}

## The topics that the changed, removed and renamed sections map to.
review : List(Change), List({ key : Str, value : Str }) -> List(Str)
review = |found, map| {
	var $topics = []
	for change in found {
		key = match change {
			Changed(k) => k
			Removed(k) => k
			Renamed(k, _) => k
			Added(k) => k
		}
		row = map.find_first(|r| r.key == key) ?? { key, value: "" }
		if !row.value.starts_with("skip:") {
			for topic in row.value.split_on(",").map(Str.trim) {
				if !topic.is_empty() and !$topics.contains(topic) {
					$topics = $topics.append(topic)
				}
			}
		}
	}
	$topics
}

expect review([Changed("a#x"), Added("a#new")], [{ key: "a#x", value: "loops, numbers" }, { key: "a#y", value: "skip: none" }]) == ["loops", "numbers"]
expect review([Removed("a#y")], [{ key: "a#y", value: "skip: none" }]) == []

## Sections whose text differs between two versions. A section that keeps its
## text but changes its key counts as renamed.
changes : List(Section), List(Section) -> List(Change)
changes = |before, after| {
	removed = before.keep_if(|old| !after.any(|new| new.key == old.key))
	var $out = []
	var $renamed = []
	for new in after {
		match before.find_first(|old| old.key == new.key) {
			Ok(old) =>
				if old.body != new.body {
					$out = $out.append(Changed(new.key))
				}
			Err(NotFound) =>
				match removed.find_first(|old| old.body == new.body) {
					Ok(old) => {
						$out = $out.append(Renamed(old.key, new.key))
						$renamed = $renamed.append(old.key)
					}
					Err(NotFound) => {
						$out = $out.append(Added(new.key))
					}
				}
		}
	}
	renamed = $renamed
	$out.concat(removed.keep_if(|old| !renamed.contains(old.key)).map(|old| Removed(old.key)))
}

expect {
	before = [{ key: "a", body: "intro" }, { key: "a#x", body: "x" }, { key: "a#y", body: "y" }, { key: "a#z", body: "z" }]
	after = [{ key: "a", body: "intro" }, { key: "a#x", body: "x2" }, { key: "a#why", body: "y" }, { key: "a#new", body: "n" }]
	changes(before, after) == [Changed("a#x"), Renamed("a#y", "a#why"), Added("a#new"), Removed("a#z")]
}

body_of : List(Section), Str -> Str
body_of = |all, key| (all.find_first(|s| s.key == key) ?? { key, body: "" }).body

fenced : Str -> Str
fenced = |text| "\n````markdown\n${text}\n````"

short : Str -> Str
short = |commit| Str.from_utf8_lossy(commit.to_utf8().take_first(7))

## The commit on the `commit` line of corpus/language/UPSTREAM.
pinned_commit : Str -> Try(Str, [NoCommitLine])
pinned_commit = |text| {
	words = text
		.split_on("\n")
		.find_first(|line| line.starts_with("commit "))
		.map_ok(|line| line.split_on(" ").keep_if(|w| !w.is_empty()))
	match words {
		Ok([_, commit, ..]) => Ok(commit)
		_ => Err(NoCommitLine)
	}
}

expect pinned_commit("repo     x\ncommit   c34079d4\ndate 1") == Ok("c34079d4")
expect pinned_commit("compiler nightly") == Err(NoCommitLine)

# --- the map -----------------------------------------------------------------

## The lines of corpus/language/langref-map.txt: a key, spaces, then either the
## topics that carry the section, comma-separated, or `skip: <reason>`. A line
## that starts with `#` is a comment.
parse_map : Str -> List({ key : Str, value : Str })
parse_map = |text|
	text
		.split_on("\n")
		.map(Str.trim)
		.keep_if(|line| !line.is_empty() and !line.starts_with("#"))
		.map(
			|line| {
				parts = line.split_on(" ")
				key = parts.first() ?? ""
				{ key, value: line.drop_prefix(key).trim() }
			},
		)

expect parse_map("# comment\nfunctions#tail-calls   functions, effects\n\nnaming   skip: no rule\n") == [{ key: "functions#tail-calls", value: "functions, effects" }, { key: "naming", value: "skip: no rule" }]

# --- git ---------------------------------------------------------------------

## Runs git in the checkout. A non-zero exit is a result, not an error.
git! : Str, List(Str) => Try({ code : I32, out : Str, err : Str }, _)
git! = |repo, args| {
	run = Cmd.new_str("git").args_str(["-C", repo].concat(args)).run!()?
	code = match run.status {
		Exited(c) => c
		Signaled(s) => 128 + s
	}
	Ok({ code, out: Str.from_utf8_lossy(run.stdout_bytes), err: Str.from_utf8_lossy(run.stderr_bytes) })
}

git_ok! : Str, List(Str) => Try(Str, _)
git_ok! = |repo, args| {
	run = git!(repo, args)?
	if run.code == 0 Ok(run.out) else Err(GitFailed({ args, err: run.err }))
}

## Fetches the commit when the checkout lacks it.
have! : Str, Str => Try({}, _)
have! = |repo, commit| {
	present = git!(repo, ["cat-file", "-e", "${commit}^{commit}"])?
	if present.code != 0 {
		_ = git_ok!(repo, ["fetch", "--depth", "1", "origin", commit])?
	}
	Ok({})
}

## Every section of docs/langref/*.md at one commit.
langref_at! : Str, Str => Try(List(Section), _)
langref_at! = |repo, commit| {
	listing = git_ok!(repo, ["ls-tree", "--name-only", commit, "docs/langref/"])?
	var $all = []
	for file in listing.split_on("\n").keep_if(|f| f.ends_with(".md")) {
		name = file.drop_prefix("docs/langref/").drop_suffix(".md")
		$all = $all.concat(sections(name, git_ok!(repo, ["show", "${commit}:${file}"])?))
	}
	Ok($all)
}

## A unified diff of two texts, from `git diff --no-index`, which exits 1 when
## the files differ.
prose_diff! : Path, Str, Str => Try(Str, _)
prose_diff! = |dir, before, after| {
	old = dir.join("langref-diff-old.md")
	new = dir.join("langref-diff-new.md")
	old.write_utf8!("${before}\n")?
	new.write_utf8!("${after}\n")?
	run = git!(".", ["diff", "--no-index", "--no-color", "-U2", old.display(), new.display()])?
	hunks = run.out.split_on("\n").drop_first(4)
	Ok("\n```diff\n${Str.join_with(hunks, "\n").trim_end()}\n```")
}

# --- splitting a page into sections ------------------------------------------
#
# These functions follow parseLangrefPage in src/langref.ts, and must produce
# the same keys. `--check-map` and src/langref.test.ts check both against the map.

## The sections of one page, the intro first.
sections : Str, Str -> List(Section)
sections = |page, content| {
	var $parts = []
	var $intro = []
	var $seen_h1 = False
	var $in_fence = False
	var $current = Err(NoSection)
	var $parent = Err(NoParent)
	for line in content.split_on("\n") {
		# A heading inside a fenced code block is content, not structure.
		if line.trim_start().starts_with("```") {
			$in_fence = !$in_fence
		}
		heading = if $in_fence Err(NotHeading) else heading_line(line)
		match heading {
			Ok(found) => {
				$parts = flush($parts, $current)
				$current = Err(NoSection)
				if found.level == 1 {
					$seen_h1 = True
				} else {
					parsed = heading_text(found.text)
					slug = parsed.anchor ?? slugify(parsed.title)
					if found.level == 2 {
						$parent = Ok(slug)
					}
					$current = Ok({ slug, parent: if found.level == 3 $parent else Err(NoParent), lines: [] })
				}
			}
			Err(NotHeading) =>
				match $current {
					Ok(open) => {
						$current = Ok({ ..open, lines: open.lines.append(line) })
					}
					Err(NoSection) =>
						if $seen_h1 {
							$intro = $intro.append(line)
						}
				}
		}
	}
	parts = dedupe(flush($parts, $current))
	[{ key: page, body: Str.join_with($intro, "\n").trim() }].concat(parts.map(|p| { key: "${page}#${p.slug}", body: p.body }))
}

flush : List({ slug : Str, parent : Try(Str, [NoParent]), body : Str }), Try({ slug : Str, parent : Try(Str, [NoParent]), lines : List(Str) }, [NoSection]) -> List({ slug : Str, parent : Try(Str, [NoParent]), body : Str })
flush = |parts, current|
	match current {
		Ok(open) => parts.append({ slug: open.slug, parent: open.parent, body: Str.join_with(open.lines, "\n").trim() })
		Err(NoSection) => parts
	}

## A duplicate slug gets its parent's slug as a prefix, then a number if it is
## still taken. tag-unions.md has two `### Limitations`.
dedupe : List({ slug : Str, parent : Try(Str, [NoParent]), body : Str }) -> List({ slug : Str, parent : Try(Str, [NoParent]), body : Str })
dedupe = |parts| {
	var $taken = []
	var $out = []
	for part in parts {
		slug =
			if parts.count_if(|other| other.slug == part.slug) > 1 {
				qualified = match part.parent {
					Ok(parent) => "${parent}-${part.slug}"
					Err(NoParent) => part.slug
				}
				unique($taken, qualified)
			} else {
				part.slug
			}
		$taken = $taken.append(slug)
		$out = $out.append({ ..part, slug })
	}
	$out
}

unique : List(Str), Str -> Str
unique = |taken, base| {
	var $candidate = base
	var $n = 2.U64
	while taken.contains($candidate) {
		$candidate = "${base}-${$n.to_str()}"
		$n = $n + 1
	}
	$candidate
}

## `#`, `##` or `###`, then whitespace, then the heading text. `####` is body text.
heading_line : Str -> Try({ level : U64, text : Str }, [NotHeading])
heading_line = |line| {
	bytes = line.to_utf8()
	level = bytes.find_first_index(|b| b != '#') ?? bytes.len()
	match bytes.get(level) {
		Ok(b) if level >= 1 and level <= 3 and is_space(b) => Ok({ level, text: Str.from_utf8_lossy(bytes.drop_first(level)).trim() })
		_ => Err(NotHeading)
	}
}

expect heading_line("## [`continue`](#continue) {#continue}") == Ok({ level: 2, text: "[`continue`](#continue) {#continue}" })
expect heading_line("#### Modulo Cons") == Err(NotHeading)
expect heading_line("#comment") == Err(NotHeading)

is_space : U8 -> Bool
is_space = |b| b == ' ' or b == '\t' or b == '\r'

## The title and the explicit anchor of a heading. Upstream writes a self-link
## (`[text](#slug)`) and an anchor (`{#slug}`), so both are removed from the title.
heading_text : Str -> { title : Str, anchor : Try(Str, [NoAnchor]) }
heading_text = |text| {
	trimmed = text.trim()
	parts = trimmed.split_on("{#")
	anchor =
		match parts.last() {
			Ok(last) if parts.len() > 1 and last.ends_with("}") => {
				name = last.drop_suffix("}").trim_end()
				if name.is_empty() or name.contains("}") Err(NoAnchor) else Ok(name)
			}
			_ => Err(NoAnchor)
		}
	rest = match anchor {
		Ok(_) => Str.join_with(parts.drop_last(1), "{#")
		Err(NoAnchor) => trimmed
	}
	{ title: strip_links(rest).trim(), anchor }
}

expect heading_text("[`continue`](#continue) {#continue}") == { title: "`continue`", anchor: Ok("continue") }
expect heading_text("Pure Functions") == { title: "Pure Functions", anchor: Err(NoAnchor) }

## Replaces each `[text](target)` with `text`.
strip_links : Str -> Str
strip_links = |text| {
	bytes = text.to_utf8()
	var $out = []
	var $i = 0
	while $i < bytes.len() {
		match link_at(bytes, $i) {
			Ok(link) => {
				$out = $out.concat(link.text)
				$i = link.next
			}
			Err(NoLink) => {
				$out = $out.append(bytes.get($i) ?? 0)
				$i = $i + 1
			}
		}
	}
	Str.from_utf8_lossy($out)
}

expect strip_links("see [the docs](a.md) and [b](c)") == "see the docs and b"
expect strip_links("a [b] c") == "a [b] c"

link_at : List(U8), U64 -> Try({ text : List(U8), next : U64 }, [NoLink])
link_at = |bytes, start| {
	if bytes.get(start) != Ok('[') {
		return Err(NoLink)
	}
	close = index_from(bytes, ']', start + 1)?
	if bytes.get(close + 1) != Ok('(') {
		return Err(NoLink)
	}
	paren = index_from(bytes, ')', close + 2)?
	Ok({ text: bytes.sublist({ start: start + 1, len: close - start - 1 }), next: paren + 1 })
}

index_from : List(U8), U8, U64 -> Try(U64, [NoLink])
index_from = |bytes, byte, start|
	match bytes.drop_first(start).find_first_index(|b| b == byte) {
		Ok(i) => Ok(start + i)
		Err(NotFound) => Err(NoLink)
	}

## Lowercase, without backticks, with each run of other characters as one `-`,
## and no `-` at either end.
slugify : Str -> Str
slugify = |title| {
	var $out = []
	var $gap = False
	for b in title.with_ascii_lowercased().to_utf8() {
		if b == '`' {
			{}
		} else if (b >= 'a' and b <= 'z') or (b >= '0' and b <= '9') {
			if $gap and !$out.is_empty() {
				$out = $out.append('-')
			}
			$out = $out.append(b)
			$gap = False
		} else {
			$gap = True
		}
	}
	Str.from_utf8_lossy($out)
}

expect slugify("`->` and `=>` in function type annotations") == "and-in-function-type-annotations"
expect slugify("`[…]` (subscript operator)") == "subscript-operator"
expect slugify("Self-Tail Calls") == "self-tail-calls"
expect slugify("`for`s and `while`s") == "fors-and-whiles"

expect {
	page =
		\\# Tag Unions
		\\
		\\Intro text.
		\\
		\\## Structural {#structural}
		\\
		\\Body one.
		\\
		\\```roc
		\\## not a heading
		\\```
		\\
		\\### Limitations
		\\
		\\First.
		\\
		\\## [Nominal](#nominal)
		\\
		\\### Limitations
		\\
		\\Second.
	sections("tag-unions", page).map(|s| s.key)
		== ["tag-unions", "tag-unions#structural", "tag-unions#structural-limitations", "tag-unions#nominal", "tag-unions#nominal-limitations"]
}
