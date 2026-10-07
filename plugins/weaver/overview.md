# weaver

An argument parser you build as a record: one field per option or parameter,
each field a builder, the record folded into a typed config. Weaver is a
package, not a platform, so an app pins a platform for its I/O and pins weaver
beside it. It depends on `roc-lang/path` and `lukewilliamboswell/roc-ansi`,
neither of which an app needs to pin unless it names their types.

`get_builtin_module Opt` for every field constructor, `lookup_builtin
Cli.parse_or_display_message` for one signature, `search` when you do not
know the name, `search_roc_syntax weaver_cli` for a complete program,
`list_roc_index kind="examples"` for five more that all compile.

## The contract

```roc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}
```

Three calls, always in this order: build a record of fields, `Cli.finish` it
with the program's metadata, `Cli.assert_valid` the result, then
`Cli.parse_or_display_message` it against the arguments.

```roc
Config : { force : Bool, region : Str, image : Str, rest : List(Str) }

parser : Cli.CliParser(Config)
parser =
	Cli.assert_valid(
		Cli.finish(
			{
				force: Opt.flag({ short: "f", long: "force", help: "Do it anyway." }),
				region: Opt.str({ short: "", long: "region", help: "Where.", default: Value("us-east-1") }),
				image: Param.str({ name: "image", help: "What to deploy.", default: NoDefault }),
				rest: Param.str_list({ name: "rest", help: "Anything else." }),
			}.Cli,
			{ name: "deploy", version: "1.0.0", authors: [], description: "Ship it.", text_style: Plain },
		),
	)
```

All five metadata fields are required. `text_style` is `Color` for ANSI help and
diagnostics, `Plain` otherwise.

## The modules

`Opt` and `Param` are where the work is: every field of a config comes from one
of them, in three shapes each. One is a required value (`Opt.str`, `Param.u64`),
one optional (`Opt.maybe_str`), one repeatable (`Opt.str_list`). `Cli` holds only
four things an app calls: `finish`, `assert_valid`, `parse_or_display_message`
and `map`. `SubCmd` holds subcommands. `Base` holds the config types the
compiler names in its errors.

Nothing suggests that you need `Builder`, but it holds `CliBuilder` and the
three stage types, so it is the import that makes a field record annotatable.
`Parser`, `Extract`, `Terminal`, `Utils` and `CliTest` are private modules of
the package. `import weaver.Parser` is refused.

## The field record

Source order is parse order, and it is type-checked. Options first, then
subcommands, then parameters, with a list parameter last. Each constructor
declares the stage it may follow and the stage it leaves behind, so an `Opt`
after a `Param` reports `Builder.GetParamsAction` where `GetOptionsAction` was
wanted, and anything after a `Param.*_list` reports `Builder.StopCollectingAction`,
which is an empty tag union and accepts nothing.

Two fields is the minimum: `{ only: ... }.Cli` is rejected as "single-field record
builder (minimum 2 fields required)", an unimplemented feature carrying no
proper diagnostic. For one field, use `Cli.map`.

```roc
solo = Cli.map(
	Opt.u64({ short: "l", long: "level", help: "How hard.", default: NoDefault }),
	|level| Level(level),
)
```

Every option record carries both `short` and `long`. Use `""` to leave one
out. `default` belongs to exactly the required-value constructors: `NoDefault`
makes one required, `Value(x)` and `Generate(fn)` make it optional, and passing
`default` to a `flag`, a `count`, a `maybe_*` or a `*_list` is a type error
because those take a record without it.

## Arguments in, config out

```roc
main! : List(OsStr) => Try({}, _)
main! = |args|
	match Cli.parse_or_display_message(parser, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => Stdout.line!(message)
		Err(InvalidUsage(message)) => {
			Stdout.line!(message)?
			Err(Exit(1))
		}
		Ok(config) => Stdout.line!(Str.inspect(config))
	}
```

Weaver reads arguments as `path.Path`, so the third argument is the converter
from the platform's own argument type: `OsStr.to_raw` on basic-cli, and on a
platform whose `main!` takes `List(Str)` a hand-written
`Str -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]`. Weaver never
drops an argument of its own. basic-cli 0.24.0 leaves the program name out of
`args` (it is `Env.program_name!`), so pass them whole. On a platform that puts
the executable path in `args[0]`, `args.drop_first(1)` is the app's job. Without
it, the app compiles, then consumes the executable path as the first parameter.

`Opt.arg`, `Param.arg`, `Param.maybe_arg` and the `*_arg_list` pair keep the raw
value as a `path.Path` instead of decoding it. Naming one in an annotation means
pinning `roc-lang/path` at 4.0.0, the release weaver pins. Identity here is the
content, so any other release reports `Path` where `Path` was wanted, and names
neither release.

## Errors

There are three, and two of them are successes. `Err(Help(message))` and
`Err(Version(message))` mean weaver has already rendered the page. Print it and
exit zero. `Err(InvalidUsage(message))` carries the rendered diagnostic and the
usage line.

Match this rather than `?` it. Under nightly 2026-10-04 `?` type-checks, but it
sends `--help` and `--version` out of `main!` as errors, so the page is never
printed and the process exits non-zero.

Configuration errors are separate and earlier. `Cli.assert_valid` is evaluated
at compile time, so two options sharing a short flag fails `roc check` with
weaver's own crash message rather than surviving to a run. Handling the `Try`
from `Cli.finish` yourself is the documented alternative and warns instead: a
configuration built from literals is compile-time known, so the compiler reports
an unconditional condition on the match.

## Testing

A parser is testable with no platform, no binary and no shell. `roc test` runs
these. `roc check` does not.

```roc
expect
	Cli.parse_or_display_message(parser, ["-f", "img", "x"], |arg| Utf8(arg))
	== Ok({ force: True, region: "us-east-1", image: "img", rest: ["x"] })
```

## Traps

- A type error inside `Cli.finish(...)` always reports twice: the mismatch, then
  a "compile time crash ... runtime error" on the same definition, because
  `assert_valid` was being evaluated. Fix the first, and the second disappears.
- A value beginning with `-` reads as another option. Write `--region=-1` or put
  `--` in front of it. `--region -1` is a missing option value.
- Short flags group and count: `-vvv` is three of `Opt.count`.
- `Param.maybe_arg` is typed upstream as `Parser.ArgValue`, in a private module.
  Write `Try(Path.Path, [NoValue])`, which is what the alias means.
- Help prose wraps at 80 UTF-8 bytes, never mid-token, so one long Unicode token
  can run past it.
