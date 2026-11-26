## Read YAML configuration with lukewilliamboswell/roc-parser 6.0: decode a
## document into your own record with `Yaml.decode_str(text, props)`, set other
## key spellings and reject unknown keys in its props, or explore a `Yaml` tree
## with `Yaml.parse_str`, `get_path` and `as_str`. `Yaml.tokenize_str` colors
## source for a highlighter, and a literal can be checked at build time (the
## parser_compile_time topic).
##
## The parser reads the YAML 1.2 core schema subset that configuration files
## and Markdown frontmatter use. It rejects the rest with `InvalidYaml`. It
## does not guess. Every failure, a missing key included, is
## `InvalidYaml(Parser.Diagnostic(Yaml.Problem))`: match its `problem` tag.
##
## Full manual: decoding into a record, key spellings, the tree, frontmatter,
## how plain values are typed, multi-line text, lists, quoting, what is
## rejected, and error locations: https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/yaml.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import pf.Stdout
import parser.Yaml

config_text =
	\\name: web
	\\version: 1.10
	\\replicas: 3
	\\ports: [80, 443]
	\\owners:
	\\  - name: Ada
	\\    email: ada@example.com
	\\  - name: Grace

# --- Decode into a record ----------------------------------------------------
#
# `Yaml.decode_str` takes no type argument. The annotation gives the type, and
# `{}` gives the default props. The error row is `[InvalidYaml(Yaml.Error)]`:
# an absent required key is the problem `MissingRequiredField(name)` inside it.

Owner : { name : Str, email : Try(Str, [Missing]) }

Config : { name : Str, version : Str, replicas : U8, ports : List(U16), owners : List(Owner) }

load_config : Str -> Try(Config, [InvalidYaml(Yaml.Error)])
load_config = |text| Yaml.decode_str(text, {})

expect {
	config = load_config(config_text)?
	# A `Str` field takes the plain scalar as written: "1.10", not 1.1.
	config.version == "1.10" and config.replicas == 3
}

# `Try(_, [Missing])` is an absent key.
expect load_config(config_text).map_ok(|c| c.owners.map(|o| o.email)) == Ok([Ok("ada@example.com"), Err(Missing)])

problem : Try(_, [InvalidYaml(Yaml.Error)]) -> Str
problem = |result|
	match result {
		Ok(_) => "ok"
		Err(InvalidYaml(error)) => Str.inspect(error.problem)
	}

expect problem(load_config("name: web\nreplicas: 3\nports: []\nowners: []")) == "MissingRequiredField(\"version\")"

# A value that does not fit its type is a problem at that value.
expect problem(load_config("name: web\nversion: 1\nreplicas: 300\nports: []\nowners: []")) == "IntegerOutOfRange({ target: U8, value: \"300\" })"

# `Try(_, [Null])` is a key with a null value: `~`, `null` or nothing.
expect {
	got : Try({ email : Try(Str, [Null]) }, [InvalidYaml(Yaml.Error)])
	got = Yaml.decode_str("email: ~", {})
	got == Ok({ email: Err(Null) })
}

# A tag union without payloads takes the tag name, as written.
expect {
	got : Try({ level : [Debug, Info] }, [InvalidYaml(Yaml.Error)])
	got = Yaml.decode_str("level: Info", {})
	got == Ok({ level: Info })
}

# --- Other key spellings, and unknown keys ----------------------------------
#
# By default keys match the field names as written, and keys the record does
# not have are skipped. Both are props of the same call. There is no
# `Yaml.decoder`.

Server : { user_id : U64, max_connections : U32 }

load_server : Str -> Try(Server, [InvalidYaml(Yaml.Error)])
load_server = |text| Yaml.decode_str(text, { keys: KebabCase, unknown_keys: Reject })

expect load_server("user-id: 7\nmax-connections: 10") == Ok({ user_id: 7, max_connections: 10 })

# With `Reject`, a typo in a key is an error, not a skipped key.
expect problem(load_server("user-id: 7\nmax-connections: 10\nmax-conections: 10")) == "UnknownKey(\"max-conections\")"

# --- Explore a tree ----------------------------------------------------------
#
# The tree tags are `Null`, `Bool`, `Int` (an `I64`), `Float`, `Text`,
# `Sequence` and `Mapping`. There is no `String` tag.

## `get_path` reads a sequence index as a decimal string. Each `?` adds its own
## tag, so the annotation lists `Missing` and `WrongType` too.
first_owner : Str -> Try(Str, [InvalidYaml(Yaml.Error), Missing, WrongType])
first_owner = |text| {
	doc = Yaml.parse_str(text, {})?
	doc.get_path(["owners", "0", "name"])?.as_str()
}

expect first_owner(config_text) == Ok("Ada")
expect first_owner("owners: []") == Err(Missing)

# In the tree, a plain scalar is typed by the core schema. `1.10` is a
# `Float`, so `as_str` gives `WrongType`. Quote a value that must stay text.
expect first_owner("owners:\n  - name: 1.10") == Err(WrongType)
expect first_owner("owners:\n  - name: '1.10'") == Ok("1.10")

port : Yaml -> I64
port = |doc| {
	match doc.get("port") {
		Ok(Int(n)) => n
		_ => 0
	}
}

expect Yaml.parse_str("port: 8080", {}).map_ok(port) == Ok(8080)

# YAML 1.2, not 1.1: `yes`, `no`, `on` and `off` are text, not booleans.
expect Yaml.parse_str("debug: yes", {}).map_ok(|doc| doc.get("debug")) == Ok(Ok(Text("yes")))
expect {
	got : Try({ debug : Bool }, [InvalidYaml(Yaml.Error)])
	got = Yaml.decode_str("debug: no", {})
	problem(got) == "TypeMismatch({ actual: PlainScalar(\"no\"), expected: BooleanValue })"
}

# A tree `Int` is an `I64`, so a larger integer is an error in the tree.
# Decode it into a `U64` (or `Str`) field instead.
expect Yaml.parse_str("id: 18446744073709551615", {}).is_err()
expect {
	got : Try({ id : U64 }, [InvalidYaml(Yaml.Error)])
	got = Yaml.decode_str("id: 18446744073709551615", {})
	got == Ok({ id: 18446744073709551615 })
}

# Keys are their source text and are not typed. `1` and `01` are two keys.
expect Yaml.parse_str("1: a\n01: b", {}).map_ok(|doc| doc.get("01")) == Ok(Ok(Text("b")))

# --- What is rejected --------------------------------------------------------
#
# Each is `InvalidYaml`, never a different value: anchors and aliases, tags,
# directives, `? ` complex keys, several documents, a flow collection or a
# quoted or plain string over more lines, tab indentation, and duplicate keys.
# Use a block scalar (`|` or `>`) for text over more lines.

expect problem(Yaml.parse_str("base: &defaults\n  port: 80", {})) == "ReferencesUnsupported"
expect problem(Yaml.parse_str("one: 1\n---\ntwo: 2", {})) == "MultipleDocumentsUnsupported"
expect problem(Yaml.parse_str("server:\n\tport: 80", {})) == "TabIndentation"
expect problem(Yaml.parse_str("name: a\nname: b", {})) == "DuplicateKey(\"name\")"
expect problem(Yaml.parse_str("list: [1,\n  2]", {})) == "UnclosedFlowCollection"

# --- Highlight source, even broken source ----------------------------------
#
# `Yaml.tokenize_str` (and `tokenize_bytes` for any bytes) is a separate lexer
# for highlighters. It never fails: it returns `{ source, tokens, diagnostics,
# status }`, where the tokens cover every byte of the input in order, with
# comments, whitespace and CRLF kept. `status` is `Complete`, `Recovered` (a
# lexical problem, listed in `diagnostics`) or `Limited`. It does not depend
# on what `Yaml.parse_str` accepts, so an anchor or a tag is still colored.
#
# A token is `{ kind, start, end, role, scalar }` with byte offsets.
# `Yaml.highlight_category(token)` maps it to `PropertyName`, `StringText`,
# `NumericLiteral`, `BooleanLiteral`, `NullLiteral`, `CommentText`, `Symbol`,
# `Trivia`, `Name`, `TypeName` or `InvalidText`, with no theme colors.
workflow = "# CI\r\non: [push]\r\nname: 'Check'\r\ncontinue-on-error: false\r\nrun: |-\r\n  # shell, not a comment\r\n  echo ok\r\n"

piece : Yaml.Tokenized, Yaml.Token -> List(U8)
piece = |tokenized, token| tokenized.source.sublist({ start: token.start, len: token.end - token.start })

expect {
	tokenized = Yaml.tokenize_str(workflow)
	tokenized.tokens.fold([], |bytes, token| bytes.concat(piece(tokenized, token))) == workflow.to_utf8()
}

categories : Str -> List((Str, Yaml.HighlightCategory))
categories = |text| {
	tokenized = Yaml.tokenize_str(text)
	tokenized.tokens
		.map(|token| (Str.from_utf8(piece(tokenized, token)) ?? "?", Yaml.highlight_category(token)))
		.keep_if(|(_, category)| category != Trivia)
}

expect categories("on: false") == [("on", PropertyName), (":", Symbol), ("false", BooleanLiteral)]

# Text in a block scalar that starts with `#` is a script line, not a comment.
expect categories("run: |-\n  # not a comment").any(|(_, category)| category == CommentText) == False

# Broken input still tokenizes, and says so.
expect Yaml.tokenize_str("name: \"unfinished").status == Recovered
expect Yaml.tokenize_str("name: ok").status == Complete
expect !Yaml.tokenize_bytes([0xFF, 0x0A]).diagnostics.is_empty()

# `Yaml.Format` and `Yaml.Cursor` are the decode protocol. Only `decode_str`
# calls them. Never call them.

# The location is `Text` with a one-based `line` and `column` for a syntax
# error. A missing key has no position: `Unavailable(NotRetained)`, and its
# `path` names the key.
report : Str -> Str
report = |text| {
	match Yaml.parse_str(text, {}) {
		Ok(doc) => doc.to_inspect()
		Err(InvalidYaml({ location: Text({ line, column, .. }), problem: p, .. })) => "${line.to_str()}:${column.to_str()}: ${Str.inspect(p)}"
		Err(InvalidYaml({ problem: p, .. })) => Str.inspect(p)
	}
}

expect report("name: a\nname: b") == "2:1: DuplicateKey(\"name\")"

main! = |_args| {
	summary = load_config(config_text).map_ok(|c| "${c.name} ${c.version}, ${c.replicas.to_str()} replicas") ?? "invalid configuration"
	Stdout.line!(summary)?
	Stdout.line!(report("name: a\nname: b"))?
	Ok({})
}
