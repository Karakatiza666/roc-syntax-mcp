# Finding the traps

A trap is a place where the obvious reading of a platform's API is false. No
script finds traps, and they are the reason that a plugin is worth installing.

A model that writes Roc for a platform that it has not seen produces plausible
code. Most of that code compiles. The model recalls the syntax well. Its errors
are in the few places where the obvious reading of an API is false. Each error
costs at least one compile cycle. At worst, it gives a program that is wrong and
shows no error. You can document each trap in one sentence on an overview page.

## The method

Write a program that you expect to work. Compile it. Keep each error that the
compiler reports.

```bash
"$ROC" check topics/ray_draw.roc
```

That is the full method. It works because the compiler gives a fixed answer.
Recalled Roc and a plausible reading of a signature can agree with each other
and both be wrong. A compiler rejection is a fact.

Two consequences:

- If the compiler rejected nothing that you wrote, you documented only what a
  model already knew. Write more difficult programs, not more of the same
  programs.
- Write each finding down at the moment that you find it. Notes reconstructed
  from memory a week later are recall again, and this method exists to replace
  recall.

`roc check` type-checks but does not run `expect`. Use `roc test` on each file
whose `expect` states a claim about values, not only about types:

```bash
"$ROC" test --no-color topics/ray_draw.roc
```

## What counts as a finding

A finding has three properties. If one property is missing, the fact does not
belong on the page:

| Property | A fact fails it when |
|---|---|
| True | You inferred it from a name and did not compile it |
| Surprising | The compiler, or the module's own shape, already makes it obvious |
| Consequential | A model that gets it wrong writes a program that compiles and misbehaves, or a program that does not compile |

"`Stdout.line!` writes a line" fails the second property. "The API is
effectful" fails the third. "`Utc.now!` returns nanoseconds" has all three. It
is true, the name says nothing about the unit, and the wrong unit gives a
program that compiles and reports the wrong time.

## The probes

A probe is a test program that you write to find one kind of trap. Run each
probe against the platform that you document. These probes found the findings
that this server already ships. They apply to other platforms, because they test
how Roc's type system meets a platform's API, not a detail of one platform.

| Probe | Write | Look for |
|---|---|---|
| Module naming | An app that looks for the API under the module whose name suggests it | A misleading module name. basic-cli's `File` holds only the buffered reader, and the filesystem API is on `Path` |
| Literal coercion | A bare string or number where the API wants a wrapper type | Whether an annotation makes the literal that type, and whether inference carries through a call |
| Error unions | An effect's error matched exhaustively, then combined with the error of another effect | A closed union that does not merge with the open `[..]` that each effect returns. `Url.ParseErr` is one |
| Unannotated upstream | A binding whose type comes from an upstream function declared as a bare `name = |args|` | The type does not flow. Annotate the binding, and check whether an app can name the type of the inner stage at all |
| Return shape | The call whose name suggests that it returns the useful value | A wrapper that you must unpack. `Http.send_json!` returns a `Response`, not the decoded reply |
| Units | Each function that returns a time, a size or a duration | Nanoseconds or seconds, bytes or entries. The name almost never states the unit |
| Entry-point contract | The app header with the wrong arity or the wrong name for its entry point | What the platform fixes, and what it leaves to you |
| Argument conventions | The entry point's arguments, printed | Off-by-one conventions. basic-cli's `args` includes the executable path |
| Effect ordering | Two effects where the result of one is the input of the other | Whether the platform gives a sequencing operator or expects a block |
| Host handles | A type that appears in a signature but not in the exposes list | A type that an app cannot name, so the binding must stay unannotated |
| Construction order | The API's builder or config record, with its parts in the order that a reader would write them | A phantom type parameter that enforces an order which the names do not show |
| Neighbouring pins | An annotation that names a type from one of the corpus's own dependencies | Whether the app must also pin that package, and at which exact release |

The host-handle probe is the easiest to miss and the most costly. A signature
can name a type that the platform never exposes. Then the only correct app code
says nothing about that type. The only way to find this is to write the
annotation and see it fail.

The last two probes are specific to packages. A package has no entry point and
no callbacks, so its traps are in the types. One trap is an order that the type
system enforces without saying so. The other is a dependency that the app
inherits when it writes an annotation.

## Worked examples

This table shows the seven basic-cli findings, how each one was found, and where
each one was documented. Use them to calibrate what a complete set looks like.

| Finding | Found by | Documented in |
|---|---|---|
| `File` holds only the buffered reader, and the filesystem API is on `Path` | Looking for `read_utf8!` under `File` | The overview lead, and `cli_files` |
| A string literal is a `Path` only where an annotation makes it one | Passing a literal and reading the mismatch | The overview, and `cli_files` |
| `Url.ParseErr` is closed and does not merge with the open `[..]` that an effect returns | The compiler rejected the first draft of a program that parsed a URL and did IO | `cli_net` |
| `Sqlite.query!` and `query_many!` are unannotated upstream, so the result type does not flow out of the decoder | A later call did not dispatch on a value that looked typed | `cli_sqlite`, which annotates every binding and says why |
| A row decoder's inner stage is typed over a host handle that an app cannot name, so it must stay unannotated | Trying to write that annotation | `cli_sqlite` |
| `Http.send_json!` returns a `Response`, not the decoded reply | Using the return value as the reply | `cli_http` |
| `Utc.now!` is nanoseconds, not seconds or millis | Printing it | The overview trap list, and `cli_terminal` |

Six of the seven are type errors. The compiler found them, and it would find
them for anybody who wrote the program. The seventh, nanoseconds, is a fact that
a type checker cannot find, so it is the most important one to write down.

`plugins/roc-ray/` is the second worked set. Read it beside the first, because
the platform has a different shape: a frame loop with three callbacks, not one
entry point.

| Finding | Found by |
|---|---|
| An app must declare a type named `Msg` even with no tasks, and the header never lists it | Writing the smallest app that could work |
| `render!` returns `Try({}, ...)`, so it cannot change the model | Returning the model from it |
| Every effect that waits type-checks in `update!` and stops the app at runtime | Reading a file there, and seeing it compile |
| Preparing text is refused in `render!`, which is where it is natural to write | The same, with the most tempting instance of it |
| A scoped drawing call forces `ScopeLimit` into the error set of `render!`, and the `..` tail does not absorb it | Drawing inside a camera scope |
| `Http.get_utf8!` takes a `Url`. A literal coerces to it, and a runtime `Str` does not | Passing a URL out of the model |
| `Audio.load_sound!` ignores the `Assets.Store` root and resolves against the working directory | Passing it the store |
| `Sprite` carries receivers and `Sprite.Animation` does not | Writing `animation.step(dt)` |

Two of these findings are the same fact about annotations, and that fact
applies beyond this platform. A `..` tail in an annotation is a fixed open tail.
It does not mean "and whatever else the body raises", so do not write `..` and
expect that result. Write `_`, which infers the set and still states what the
callback is. Upstream's own examples write `App.Init(Model, _)`. This was found
by reading those examples after the fact, not by compiling. It is the one part
of this method where reading worked better than writing.

The same work found six host defects. Each defect was fixed in the host, so all
platforms get the fix, and none was worked around in the plugin:

| Defect | Found by |
|---|---|
| Detection matched only `x.y.z`, so it ignored every app that pinned a prerelease | Pinning `0.10.0-rc3` |
| The parser read an annotated binding inside an `expect` block as a module member | `plugin validate` reporting it as a duplicate |
| A plugin could ship topics that no caller could reach, because `checks` compiles them and serves nothing | Asking what `search_roc_syntax` answered for this platform, and finding nothing |
| `_` is a keyword of the `derived_methods` topic, and every snake_case query contains one, so `key_pressed` and `with_camera` both matched that topic | Searching for a topic by its own name |
| Keywords matched by raw substring, so `str` matched the start of "structure" in "how do I structure a game", and the architecture topic lost to string literals | Asking a topic the question that its own description states |
| With no app header, detection had no input, and no tool listed the platforms of this server. A model could not choose a platform, so the server chose for it, and that had to stop | Watching an agent use the plugin from a workspace with no app header yet |

The last four defects apply generally. A corpus that is compiled but that no
caller can reach looks the same as a working corpus in every check. Thus check
what a caller gets, not what the checks report. A retrieval bug cannot be seen
from inside the corpus. To find one, ask a query whose correct answer you know,
in the words that the topic itself uses. Check detection in the same way.
Detection is written for a workspace that already has an app, but a plugin's
first hour of use is in a workspace that has none. The fix is never to guess
for the caller, because an installed corpus shows what is available, not what
somebody writes. The fix is to list what exists, in a few words for each, and
let the caller select.

`plugins/weaver/` is the third worked set, and the first for a package. A
package has no callbacks and no entry point to get wrong, so every finding is
about the types that the API uses:

| Finding | Found by |
|---|---|
| Field order in `{ ... }.Cli` is source order, and the compiler checks it. The order is options, then subcommands, then parameters, with the list parameter last | Writing the record in the order that the config type reads |
| A record builder needs two fields. With one field, the result is "not yet implemented", and the compiler gives no useful diagnostic | Writing a CLI with a single option |
| The parse result's error union is closed, so `?` fixes the error type of `main!`, and the platform's open `[..]` does not merge with it | Propagating the error instead of matching it |
| `Err(Help(_))` and `Err(Version(_))` are successes that weaver has already rendered | Matching only the `Ok` and the failure |
| The compiler evaluates `Cli.assert_valid` at compile time, so an invalid configuration fails `roc check`. A type error inside it is reported a second time, as a crash | Giving two options the same short flag |
| Upstream documents how to handle `Cli.finish` by hand, but that code gives a warning, because a literal configuration is known at compile time | Writing the documented alternative |
| Weaver drops no argument, and basic-cli 0.22.0 does include the executable path, so `args.drop_first(1)` is required | Running it, not checking it |
| `Param.maybe_arg` is typed over a module that the package does not expose. Thus the annotation is `Try(Path.Path, [NoValue])`, and the app must pin `roc-lang/path` 4.0.0 itself | Trying to write that annotation |

No type checker can find the seventh finding. It took `roc run` against a real
basic-cli binary to settle it. Upstream's own README says that a modern platform
needs no drop. This server's basic-cli page says that the executable path is
`args[0]`. Printing the list settled the question. When two documents disagree
about runtime behaviour, run the program.

The eighth finding is the platform-boundary rule from
`reference/package-plugin.md`, seen from the package side. If the app pins
`roc-lang/path` 2.0.0 instead of 4.0.0, the compiler reports a mismatch between
`Path` and `Path`, and does not say where either type comes from.

That work found seven more host defects. Again, each defect was fixed in the
host, so all plugins get the fix:

| Defect | Found by |
|---|---|
| `parseExposes` read only a platform's `exposes [...]`, so a package header exposed nothing and the full corpus was indexed at host tier | `plugin inspect` reporting 243 items and not one at public tier |
| `parsePackageDeps` read only a platform's `packages { ... }`, so a package's own pins were not visible | The same run, reporting no dependencies for a package that has two |
| `check-platform-examples.sh` skipped each plugin with no `version`, so nothing compiled the examples, topics and verify app of a package plugin | Reading the script after `validate` reported a pass count that was too small |
| A corpus declared as both `modules` and `packages` was indexed twice, and every lookup answered twice | Asking a live server for one name from a workspace that pinned the package |
| The `scope` enum of `search_roc_syntax` was built from the platforms, so the registry served a package plugin's topics, but no caller could address them | Passing `scope: "weaver"` and getting an error that the enum expects a platform |
| The default working set ignored a package that the workspace's app header pins. The topics stayed out of the set, while the server's own startup line named the pin | Asking a question with no `scope` from a workspace that pins the package |
| `matchTopic` returned the first declared topic that matched any keyword, so "how do I parse command line arguments" answered with JSON encoding | Asking a topic the question that its own description states |

Rows four to six cannot occur in the current design, because a package is not a
scope. A package plugin declares no `modules`, its topics are filed under
`language`, and the server reads a pinned package with the builtins. The rows
stay here, because their cause is general: a host written only for platforms.

The last two rows are the general ones. Detection and the working set were
written for platforms. A header pins a package in the same way, and with the
same certainty, as a platform. Thus check all code that answers "what is this
workspace" for both platforms and packages. Also, retrieval gets worse as
topics are added. Each new corpus makes it more likely that the first match is
wrong. The only way to see this is to ask questions whose answers you already
know.

A fourth method found three more defects, and it is the cheapest method. An
agent used `plugins/roc-ray/` for real work and reported the cost of its calls.
None of these defects gave a wrong answer, so no check and no probe had found
them.

| Defect | Found by |
|---|---|
| `get_roc_syntax` declared no arguments, and an argument that a tool does not declare is dropped before the handler sees it. Thus a caller that asked for `ray_project` got the full syntax file, twice, with no error | Reading what an agent called, not whether the call succeeded |
| A type query of `search_symbols` matched a query variable only against another variable. Thus `F32 -> Try(U64, err)` found none of the four `F32 -> Try(U64, [OutOfRange, ..])` conversions, and the caller had to read a module of 111 methods | A query whose answer was known to exist |
| `roc_fmt` took a `code` string, where the related tool `roc_check` took `code` or `path` | One failed call in the same transcript |

All three apply generally:

- A tool must declare each argument that a caller can plausibly pass, so that
  the tool can answer or refuse it. If the tool drops the argument without a
  message, the caller pays for an answer to a question that they did not ask.
- Related tools take the same input in the same shape. If they do not, the
  caller spends a call to learn the difference.
- An empty search result is a claim about the corpus. Test it with one query
  whose answer you already know. A false negative looks the same as a corpus
  that does not have the item.

## Where a finding goes

Put each finding in both places. The two places do different jobs.

| Place | Form | Why both |
|---|---|---|
| The overview page | One clause, in the paragraph that the reader is already reading | The overview is the only text that a model reads before it writes Roc |
| The topic file | A comment at the line where the mistake happens, beside code that shows the correct use | A model reads the topic after it has selected the API, when it is about to use the API wrong |

A finding that is only in the overview is lost when the reader moves on to the
index. A reader who does not open a topic never sees a finding that is only in
that topic.

## When the bug is in the host

A plugin ships no code, so an author cannot work around a gap in this server's
parser. This is intentional. If the index is missing members, a module is
empty, or a signature is damaged, the cause is in `src/builtin_parser.ts`. Fix
it there, so that every platform gets the fix.

There are two precedents. basic-cli found both, and both were fixed in the host:

- Upstream declared members as bare `name = |args|`, with no annotation.
- One file used spaces for indentation, while every other file used tabs.

Neither problem could be fixed from inside a plugin, and each was worth a bug
report.

Use `plugin inspect` to tell the two cases apart. If it reports the counts that
you expect by tier and namespace, the corpus is correct, and the problem is in
what you wrote about it. If the counts are wrong, stop curating and file a bug.
