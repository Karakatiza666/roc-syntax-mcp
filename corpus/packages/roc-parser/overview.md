# roc-parser

`lukewilliamboswell/roc-parser`: parser combinators, and parsers for CSV, YAML,
JSON, XML, HTML, SVG, MathML, Markdown, AsciiDoc, Roc source, HTTP/1.1, QIF and
OFX. It works on any platform, on a Roc nightly from 2026-11-13 or later. The
standard library's `Json` decodes JSON into records.

```roc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst",
}

import parser.Parser
import parser.CSV
```

| Module | Gives | Topic |
|---|---|---|
| `Parser` | Combinators over bytes | `parser_combinators` |
| `CSV` | Rows into your records | `parser_csv` |
| `Yaml` | Config into a record or tree | `parser_yaml` |
| `JsonValue` | Any JSON, and a writer | `parser_json` |
| `Xml` | A document tree | `parser_xml` |
| `Html`, `Svg`, `MathML` | Checked markup trees | `parser_markup` |
| `Markdown` | Blocks to render | `parser_markdown` |
| `AsciiDoc` | Blocks, HTML, includes | `parser_asciidoc` |
| `RocSyntax` | Roc tokens and tree | `parser_roc_syntax` |
| `HTTP` | Messages from bytes | `parser_http` |
| `QIF`, `OFX`, decoders | Input in chunks | `parser_streaming` |
| `Parser.Quotation` | Checked literals and files | `parser_compile_time` |

## The style

- Every entry point takes a props record: `CSV.decode_str(text, {})`. There
  are no `_with` variants.
- Each error is one open tag named after its format: `ParseError`,
  `InvalidCsv`, `InvalidYaml`, `InvalidJsonValue`, `InvalidXml`,
  `InvalidMarkup`, `InvalidHttp`. So `?` joins them. Each holds
  `{ problem, location, path }`. Match the `problem` tag; there is no message.
- A value that can be absent is `Try(_, [Missing])`.
- `CSV.decode_str` and `Yaml.decode_str` take the shape from the annotation.

```roc
setting : Parser(Parser.Utf8.Bytes, { key : Str, port : U64 }, _)
setting = Parser.const(|key| |port| { key, port }).keep(Parser.Utf8.string("port")).skip(Parser.Utf8.codeunit('=')).keep(Parser.Utf8.digits({}))

Row : { name : Str, qty : U64 }

rows : Try(List(Row), [InvalidCsv(CSV.Error)])
rows = CSV.decode_str("name,qty\nbolt,4\n", {})
```

## Traps

- `import parser.Utf8` is an error: the byte primitives are `Parser.Utf8`.
- `Parser` takes three arguments; the third, the problem union, is `_`.
- `digits({})`, `rest({})` and `CSV.string({})` are factories: call them.
- `Parser.const` takes a curried function, one argument per `.keep`.
- A recursive parser is a function `|{}|`, not a value.
- `parser.parse_str(text)` must consume all the input. `run_str` parses a
  prefix and gives `{ value, rest }`.
- A missing column or key is `MissingRequiredField` inside `InvalidCsv` or
  `InvalidYaml`, not a tag of its own.
- `Markdown.parse_str` returns a `List`, not a `Try`, so `?` on it is an error.
- HTTP takes `List(U8)`: call `.to_utf8()` on a `Str`.
- `Html` checks and builds a tree. It does not render HTML text.
- A literal annotated `CSV.Decoded(Row)`, `JsonValue`, `Html.Fragment` and so
  on is checked during compilation.

Full manual: https://github.com/lukewilliamboswell/roc-parser/tree/6.0.0/docs

- Choose an approach: decode into your type, read a tree, combinators, or no
  parser: https://github.com/lukewilliamboswell/roc-parser/blob/6.0.0/docs/choosing-an-approach.adoc
