## Read YAML configuration with lukewilliamboswell/roc-parser 2.0: decode a
## document into your own record with `Yaml.decode`, set other key spellings
## with `Yaml.decoder`, or explore a `Yaml` tree with `Yaml.parse_str`,
## `get_path` and `as_str`.
##
## The parser reads the YAML 1.2 core schema subset that configuration files
## and Markdown frontmatter use. It rejects the rest with `InvalidYaml`. It
## does not guess.
##
## Full manual: decoding into a record, key spellings, the tree, frontmatter,
## how plain values are typed, multi-line text, lists, quoting, what is
## rejected, and error locations: https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/yaml.adoc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst",
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
# `Yaml.decode` takes no type argument. The annotation gives the type. A
# required field that is absent fails with `MissingRequiredField(name)`. The
# compiler adds that tag, and you must write it in the annotation, or the
# check fails with "parser error row missing tag".

Owner : { name : Str, email : Try(Str, [Missing]) }

Config : { name : Str, version : Str, replicas : U8, ports : List(U16), owners : List(Owner) }

load_config : Str -> Try(Config, [InvalidYaml(Yaml.Error), MissingRequiredField(Str)])
load_config = |text| Yaml.decode(text)

expect {
	config = load_config(config_text)?
	# A `Str` field takes the plain scalar as written: "1.10", not 1.1.
	config.version == "1.10" and config.replicas == 3
}

# `Try(_, [Missing])` is an absent key.
expect load_config(config_text).map_ok(|c| c.owners.map(|o| o.email)) == Ok([Ok("ada@example.com"), Err(Missing)])

expect load_config("name: web\nreplicas: 3\nports: []\nowners: []") == Err(MissingRequiredField("version"))

# A value that does not fit its type is `InvalidYaml`, at that value.
expect load_config("name: web\nversion: 1\nreplicas: 300\nports: []\nowners: []").is_err()

# `Try(_, [Null])` is a key with a null value: `~`, `null` or nothing.
expect {
	got : Try({ email : Try(Str, [Null]) }, [InvalidYaml(Yaml.Error), MissingRequiredField(Str)])
	got = Yaml.decode("email: ~")
	got == Ok({ email: Err(Null) })
}

# A tag union without payloads takes the tag name, as written.
expect {
	got : Try({ level : [Debug, Info] }, [InvalidYaml(Yaml.Error), MissingRequiredField(Str)])
	got = Yaml.decode("level: Info")
	got == Ok({ level: Info })
}

# --- Other key spellings, and unknown keys ----------------------------------
#
# `Yaml.decode` uses keys as written, and skips keys the record does not have.
# Build a stricter decoder once, as a top-level constant.

decode_strict = Yaml.decoder({ keys: KebabCase, unknown_keys: Reject })

Server : { user_id : U64, max_connections : U32 }

load_server : Str -> Try(Server, [InvalidYaml(Yaml.Error), MissingRequiredField(Str)])
load_server = |text| decode_strict(text)

expect load_server("user-id: 7\nmax-connections: 10") == Ok({ user_id: 7, max_connections: 10 })

# With this decoder, a typo in a key is an error, not a skipped key and a missing field.
expect load_server("user-id: 7\nmax-conections: 10").is_err()

# --- Explore a tree ----------------------------------------------------------
#
# The tree tags are `Null`, `Bool`, `Int` (an `I64`), `Float`, `Text`,
# `Sequence` and `Mapping`. The 1.x releases named the text tag `String` and
# the error tag `YamlError`. In 2.0, a match on `String(s)` fails to compile,
# and the error tag is `InvalidYaml`.

## `get_path` reads a sequence index as a decimal string. Each `?` adds its own
## tag, so the annotation lists `Missing` and `WrongType` too.
first_owner : Str -> Try(Str, [InvalidYaml(Yaml.Error), Missing, WrongType])
first_owner = |text| {
	doc = Yaml.parse_str(text)?
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

expect Yaml.parse_str("port: 8080").map_ok(port) == Ok(8080)

# YAML 1.2, not 1.1: `yes`, `no`, `on` and `off` are text, not booleans.
expect Yaml.parse_str("debug: yes").map_ok(|doc| doc.get("debug")) == Ok(Ok(Text("yes")))
expect {
	got : Try({ debug : Bool }, [InvalidYaml(Yaml.Error), MissingRequiredField(Str)])
	got = Yaml.decode("debug: no")
	got.is_err()
}

# A tree `Int` is an `I64`, so a larger integer is an error in the tree.
# Decode it into a `U64` (or `Str`) field instead.
expect Yaml.parse_str("id: 18446744073709551615").is_err()
expect {
	got : Try({ id : U64 }, [InvalidYaml(Yaml.Error), MissingRequiredField(Str)])
	got = Yaml.decode("id: 18446744073709551615")
	got == Ok({ id: 18446744073709551615 })
}

# Keys are their source text and are not typed. `1` and `01` are two keys.
expect Yaml.parse_str("1: a\n01: b").map_ok(|doc| doc.get("01")) == Ok(Ok(Text("b")))

# --- What is rejected --------------------------------------------------------
#
# Each is `InvalidYaml`, never a different value: anchors and aliases, tags,
# directives, `? ` complex keys, several documents, a flow collection or a
# quoted or plain string over more lines, tab indentation, and duplicate keys.
# Use a block scalar (`|` or `>`) for text over more lines.

expect Yaml.parse_str("base: &defaults\n  port: 80").is_err()
expect Yaml.parse_str("one: 1\n---\ntwo: 2").is_err()
expect Yaml.parse_str("server:\n\tport: 80").is_err()
expect Yaml.parse_str("name: a\nname: b").is_err()
expect Yaml.parse_str("list: [1,\n  2]").is_err()

# `Yaml.Format` and `Yaml.Cursor` are the decode protocol. Only `Yaml.decode`
# calls them. Never call them.

report : Str -> Str
report = |text| {
	match Yaml.parse_str(text) {
		Ok(doc) => Yaml.to_inspect(doc)
		Err(InvalidYaml({ line, column, message })) => "${line.to_str()}:${column.to_str()}: ${message}"
	}
}

main! = |_args| {
	summary = load_config(config_text).map_ok(|c| "${c.name} ${c.version}, ${c.replicas.to_str()} replicas") ?? "invalid configuration"
	Stdout.line!(summary)?
	Stdout.line!(report("name: a\nname: b"))?
	Ok({})
}
