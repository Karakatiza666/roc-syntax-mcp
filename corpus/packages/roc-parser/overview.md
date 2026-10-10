# roc-parser

`lukewilliamboswell/roc-parser`: parser combinators, and parsers for CSV, YAML,
XML, Markdown and HTTP/1.1 messages. It works on any platform. For JSON, use
`Json.parse` from the standard library.

```roc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/2.0.0/7CLzCK6qUz7zmj6nvBxMEFu11HPwQTnCovKiyWzDSLTW.tar.zst",
}

import parser.Parser
import parser.Utf8
```

| Module | Gives | Start with | Topic |
|---|---|---|---|
| `Parser`, `Utf8` | Combinators over bytes | `Utf8.parse_str(parser, text)` | `parser_combinators` |
| `CSV` | Rows into your records | `CSV.parse(text)` | `parser_csv` |
| `Yaml` | Config into a record, or a tree | `Yaml.decode(text)`, `Yaml.parse_str` | `parser_yaml` |
| `Xml` | A document tree | `Xml.parse_str(text)` | `parser_xml` |
| `Markdown` | Blocks and inlines to render | `Markdown.parse_str(text)` | `parser_markdown` |
| `HTTP` | Requests and responses from bytes | `HTTP.parse_request(bytes)` | `parser_http` |

## The 2.0 style

- Each error is one open tag named after its format: `ParseError`,
  `InvalidCsv`, `InvalidYaml`, `InvalidXml`, `InvalidHttp`. So `?` joins them.
- A value that can be absent is `Try(_, [Missing])`.
- `CSV.parse` and `Yaml.decode` take the shape from the annotation:

```roc
setting : Parser(Utf8.Bytes, { key : Str, port : U64 })
setting = Parser.const(|key| |port| { key, port }).keep(Utf8.string("port")).skip(Utf8.codeunit('=')).keep(Utf8.digits)

Row : { name : Str, qty : U64 }

rows : Try(List(Row), [InvalidCsv(CSV.Error), MissingRequiredField(Str)])
rows = CSV.parse("name,qty\nbolt,4\n")
```

## Traps

- `import parser.Parser exposing [Parser]` is an error: a type module exposes
  its type by itself.
- `Parser.const` takes a curried function, one argument per `.keep`.
- `Utf8.parse_str` must consume all the input. Use `Utf8.parse_str_partial` for
  a prefix, which gives `{ value, rest }`.
- A decoded record needs `MissingRequiredField(Str)` in its error annotation.
- `Markdown.parse_str` returns a `List`, not a `Try`, so `?` on it is an error.
- `HTTP.parse_request` takes `List(U8)`: call `.to_utf8()` on a `Str`.

`CSV.Format`, `CSV.State`, `Yaml.Format` and `Yaml.Cursor` are the decoding
protocol. Static dispatch uses them. Never call them.

Full manual: https://github.com/lukewilliamboswell/roc-parser/tree/2.0.0/docs

- Add the package, and read CSV into records in a first program:
  https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/getting-started.adoc
- Which way to read your input: decode into your own type, read a document
  tree, build a parser with combinators, or use no parser at all:
  https://github.com/lukewilliamboswell/roc-parser/blob/2.0.0/docs/choosing-an-approach.adoc
