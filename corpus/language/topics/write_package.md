Set up a Roc package repo, or bring an existing one to the community
conventions. The conventions come from ageron/roc-package-template and the
new-compiler packages on roc-awesome. One change: Roc sources go in `src/`,
not `package/`. The directory name is not in the bundle, so both layouts give
the same bundle hash. Tested with nightly-2026-10-09-258ab27.
`release_package` covers the pin, the bundle, releases, docs and CI.

### Checklist

For a new repo, do each step. For an existing repo, compare each file with its
section and fix the differences.

| # | Step | Section |
|---|---|---|
| 1 | Create the files of the layout. In an old repo, `git mv package src`, then change the path in scripts, workflows (`bump_entrypoint`, `paths` filters) and example headers | Layout |
| 2 | Port old-compiler code: `module [..]` headers, `\x ->`, `Result` | topics `modules`, `functions`, `try_operator` |
| 3 | List the public modules. Release URL dependencies only. No `roc:` pin | `src/main.roc` |
| 4 | One type per file, `##` docs, `expect`s next to the code | `src/Greet.roc` |
| 5 | Put helpers in hidden modules | `src/Internal/Text.roc` |
| 6 | Runnable, noninteractive examples | `examples/hello.roc` |
| 7 | One script for the local and CI checks | `scripts/all_tests.sh` |
| 8 | `.roc-version`, bundle, bundle test, release, docs, compiler updates, README | `release_package` |

### Layout

```text
src/main.roc             root module: the public modules and the dependencies
src/Greet.roc            one public type module per file
src/Internal/Text.roc    hidden module: not in the header
examples/hello.roc       runnable apps that use the package
scripts/all_tests.sh     local and CI checks
.roc-version             the compiler pin (release_package)
.github/                 setup-roc action and workflows (release_package)
README.md                overview, import line with the release URL, docs link
LICENSE                  UPL-1.0 is the most common in Roc repos
```

Keep only the package in `src/`. The bundle takes its files from there.
Examples, scripts and tests that need a platform go outside it. One repo holds
one package.

The files below are a whole package. Each one is ready to copy.

### src/main.roc

`src/main.roc`
```roc
package
	[
		Greet,
	]
	{}
```

- The list names the public type modules. Every other module is hidden.
  `import pkg.Text` in an app gives "package module is private".
- To make a module in a subdirectory public, import it in main.roc with an
  alias and list the alias: `import Internal/Wrapper as Wrap`, then `Wrap`.
- A dependency goes in the record, as a release URL:
  `unicode: "https://github.com/roc-lang/unicode/releases/download/<version>/<hash>.tar.zst"`.
  A path dependency (`"../other/main.roc"`) works in a checkout, but
  `roc bundle` refuses it: "outside the entry point directory".
- `roc docs` does not show a `##` above the `package` header. Put the
  overview in README.md.
- No `roc:` pin here. A published pin gives "roc version mismatch" to every
  user on another nightly. Use `.roc-version`.

### src/Greet.roc

`src/Greet.roc`
```roc
import Internal/Text as Text

## A greeting for one person.
Greet :: { name : Str }.{

	## Makes a [Greet] for `name`. Spaces at each end are removed.
	new : Str -> Greet
	new = |name| { name: name.trim() }

	## The greeting as text.
	##
	## ```roc
	## expect Greet.new("Ana").to_str() == "Hello, Ana!"
	## ```
	to_str : Greet -> Str
	to_str = |greet| "Hello, ${Text.punctuate(greet.name)}"
}

expect Greet.new("  Ana ").to_str() == "Hello, Ana!"
expect Greet.new("").to_str() == "Hello, !"
```

- The file name, the type name and the header entry are the same.
- `##` above the type and above each `.{ }` item become the docs. A `##` block
  at the top of the file, followed by a blank line, is the module doc. It
  replaces the `##` of the type, so write one of the two.
- A top-level definition outside `.{ }` is private to the file.
- Tests are top-level `expect`s next to the code.

### src/Internal/Text.roc

`src/Internal/Text.roc`
```roc
# Helpers for the public modules. main.roc does not list Text, so Text is hidden.
Text :: [].{
	punctuate : Str -> Str
	punctuate = |s| "${s}!"
}

expect Text.punctuate("Ana") == "Ana!"
```

- An import path is relative to the importing file (`Internal/Text`), or to
  the package root with a leading `/` (`/Internal/Text`).
- `roc test src/main.roc` and `roc bundle` follow imports. A file that no
  module imports is not in the bundle, and its `expect`s do not run.

### examples/hello.roc

`examples/hello.roc`
```roc
app [] { pkg: "../src/main.roc" }

import pkg.Greet

main! = |_args| {
	echo!(Greet.new("World").to_str())
	Ok({})
}
```

- With no platform, `roc` uses its built-in echo host. CI needs no platform
  download and no Zig.
- Use the shorthand `pkg` in all examples. The release notes show `pkg` too.
- Keep examples noninteractive, so CI can run them.
- Examples always use the relative path. The bundle test swaps it for the
  bundle with `--replace-dep` (`release_package`). README.md holds the URL.

### scripts/all_tests.sh

`scripts/all_tests.sh`
```sh
#!/usr/bin/env bash
# The local and CI checks. Usage: ROC=/path/to/roc scripts/all_tests.sh
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."

"$ROC" version
"$ROC" fmt --check src examples
"$ROC" check src/main.roc
"$ROC" test src/main.roc
for f in examples/*.roc; do
	"$ROC" check "$f"
	"$ROC" "$f"
done
"$ROC" docs src/main.roc
```

Then test the bundle as a dependency (`release_package`).

### .gitignore and .gitattributes

`.gitignore`
```text
/dist/
/generated-docs/
/.release/
```

`.gitattributes`
```text
*.roc text eol=lf
```

Add the binaries that `roc build` writes for the examples to `.gitignore`.
