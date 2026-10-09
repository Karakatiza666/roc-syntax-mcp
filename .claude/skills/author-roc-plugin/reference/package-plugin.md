# Package plugins

A package plugin does a different job from a platform plugin, and it has its own
rule about when it can win. A package corpus serves one namespace: the modules
and prose of one Roc package. It takes the same fields as a platform corpus, and
the release's own `package` header makes it a package. `reference/manifest.md`
has the full table.

`roc-syntax-mcp plugin init <dir> --kind=package` writes a plugin with one
package corpus. A plugin can also hold a package beside the platform whose API
uses it. It can also hold several packages, each in its own corpus.

## The two shapes

```json
{
  "schema": 1,
  "maintainer": "you",
  "corpora": [
    {
      "release": "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
      "description": "An argument parser built as a record of Opt and Param fields.",
      "purpose": "parsing command-line arguments, on any platform",
      "overview": "overview.md",
      "examples": "examples",
      "checks": ["topics", "verify"],
      "topics": [{ "name": "weaver_cli", "file": "topics/weaver_cli.roc", "description": "...", "keywords": ["..."] }]
    }
  ]
}
```

Write this shape, a documented package. The release makes the corpus the
provider for each app whose header pins that release. `description` makes it a
page, named `weaver` after the repo. `plugin index` writes the `index.json` that
the host reads the release from. `plugins/weaver/` is the worked example.

A package is not a scope. A `scope` value limits a search to the language, the
builtins or one platform, and a package is none of those. After an app pins a
package, the server reads the package with the builtins. A separate scope would
filter nothing that a caller needs, and it would add `tools/list` tokens to
every request.

The loader refuses, by name, the fields that only a platform uses: `scaffold`,
`sample` and `docs`. `roc_check` wraps bare source in a platform's app, so the
server would never select a package's scaffold. A package's programs are
complete apps that pin their own platform, and `roc_check(path:)` checks them.

The other shape omits `description` and every field that depends on it:

```json
{
  "schema": 1,
  "maintainer": "you",
  "corpora": [{ "release": "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst" }]
}
```

That shape gives signatures only, with no page and no topics. A caller reaches
the items only by address. When an app pins the package, `search_symbols` and
`get_builtin_module` find its names, each with its origin. The loader refuses
`overview`, `topics`, `examples` and `checks` without a `description`, because
nothing could read them.

## Where a documented package sits

| What | Where a caller finds it |
|---|---|
| Its items, after the app header pins it | With the builtins: every unscoped search, `scope: "builtin"`, and `search_symbols` |
| Its items, before an app pins it | Only on a miss. The answer names the package, shows up to three matching signatures, and gives the header line that pins it |
| Its page | `get_roc_syntax(topic: "<name>")`, or the repo path. The page lists the topics and examples, and says whether this app pins the package |
| Its topics | Filed under `language`, so they answer an unscoped question before an app pins the package. An answer from a package that is not pinned ends with the header line |
| Its examples | Read by the package name and the file name, as in `get_roc_syntax(topic: "weaver/basic")`. Listed by `list_roc_index(kind: "examples")` |
| Its name and maintainer | `list_roc_index(kind: "scopes")`, under "Documented packages", and the catalogue line of `get_roc_syntax()` |

The install adds no item to any address space. The app header states what the
app uses, and that is the same evidence rule that a platform gets. The host
indexes a module that the package's header does not expose at host tier, which
is addressable and excluded from search.

Package names and scope names are in one shared set. If a plugin claims a
scope's name or a documented package's name, the loader refuses the full
plugin, and the first plugin to load keeps the name.

## Which provider answers

The host selects one provider per namespace, once at load. It never selects
again for each call.

| Tier | Provider | Wins because |
|---|---|---|
| 0 | The exact release that the header pins, from the compiler's cache | The app compiles against those bytes. The host uses this tier only when no corpus has that release |
| 1 | A package corpus in a declared plugin | Somebody installed it for this namespace |
| 3 | This server's vendored copy | The shipped server then works with no plugins installed |

Tier 1 wins over tier 3 only under a condition, and that condition is the core
of the design. "When your override is refused" below gives the condition. The
loader holds a plugin that ships a platform and its pinned package to the pinned
release, so the plugin's own package always meets the condition.

## Why a version difference can be fatal

These results were measured against the bundled nightly, because upstream's
`corpus/language/langref/packages.md` is a stub:

| Experiment | Result |
|---|---|
| App pins a byte-identical copy of http at a fresh local path, and the platform pins the 1.0.0 tarball | Compiles |
| Same, with one comment line appended to `Response.roc` | `type mismatch` at the platform boundary |
| App pins both copies at once and keeps the second one off the boundary | Compiles |

The compiler identifies a package by its content, and the URL that it came from
does not matter. The second experiment changed a comment, and `Server.respond`
then refused the app's `Response`. The compiler's own diagnostic names both
types `Response`, and does not say where either one comes from:

```
This argument has the type:
    Response
But the function needs the first argument to be:
    Response
```

Design for three consequences:

- Semver gives no compatibility information here. For anything that crosses a
  platform boundary, a patch bump is as fatal as a major bump.
- Two versions can exist together in one app, so a mismatch is not always a
  mistake. It is fatal only where the package's types cross the platform's
  exposed API.
- You can compute whether they cross. They cross when an exposed platform module
  contains `import <pkg>.X`.

Both platforms that this server ships cross on `roc-lang/http`. For either
platform, a package plugin that serves any version other than the pinned one
describes an app that nobody can write.

## When your override is refused

| Crosses the active platform's exposed API | Versions agree | Outcome |
|---|---|---|
| Yes | Yes | Your plugin wins with no message. It is the same package, with better documentation |
| Yes | No | Refused. The host serves the platform's copy and reports the reason |
| No | Either | Your plugin wins. The app pins the package itself, and the platform's pin has no effect on the app |

The crossing test over-approximates. A module can import a package type and
never use it in a public signature, so the host refuses a few overrides that
would work. The test errs toward refusal, which is the safe direction.

`plugin validate` reports which bundled platform's API each declared package
crosses, and which release that platform requires. That check never fails, by
design. A crossing is a property of the platform and does not show a defect in
your plugin. A count that you can read is more useful than a rule that guesses.

Run `plugin inspect` for the other half of the answer: which of your overrides
this host would refuse.

## When nothing serves a namespace

When the host refuses a provider, it tries the next tier. If it refuses tier 1,
it tries tier 3, and it can refuse that tier too. This server indexes only
`roc-lang/http`, roc-parser and roc-random, so a namespace can end with no
compatible provider.

This state can occur, and the server always reports it:

```
No provider serves lukewilliamboswell/weaver.
Your app header pins 0.8.0; @roc-syntax/weaver serves 0.9.0.
Install a package plugin at 0.8.0, or run this server with
--force=lukewilliamboswell/weaver to read 0.9.0 anyway.
```

The note names the flag, so nobody has to search for it: `run this server with
--force=lukewilliamboswell/weaver to read 0.9.0 anyway`.

The obvious alternative is to serve the incompatible copy with a warning, with
no request from the user. Two reasons rule it out:

1. `roc_check` would contradict `search_symbols`. `roc_check` compiles the app
   against the 0.8.0 that its header pins, while the lookup prints 0.9.0
   signatures. A server whose tools disagree about one name is worse than a
   server that declines.
2. Documentation labelled 0.9.0 also encourages a model to write that pin into
   an app header, next to a dependency that still pins 0.8.0. That is the one
   case that produces a `CliParser` against `CliParser` error that the compiler
   cannot explain.

Declining has a real cost, so the note names both ways out and does not only
decline.

## `force`

The crossing test reads the corpus and over-approximates, and a package's
maintainer can know better. Thus the end-user can override the test for each
namespace. There are two sources, and neither is a manifest, so a plugin cannot
force itself.

| Source | Written |
|---|---|
| Flag, repeatable | `--force=lukewilliamboswell/weaver` |
| Environment | `ROC_MCP_FORCE=lukewilliamboswell/weaver`, comma, colon or semicolon separated |

Both sources name a namespace directly, and say that someone vouches for it. An
id that is not a repo path names no namespace. The host reports such an id in
the scope listing and on stderr, and does not ignore it. The operator wrote the
id to change a resolution, and a typo would otherwise change nothing, with no
message.

A forced namespace states, on each item that it answers, what it was forced
over:

```
## Cli.finish (weaver 0.9.0, forced over 0.8.0)
```

The note is on each item and not in a footer, because an override changes what
every signature in that namespace says. A caller who reads one item and stops
must still see the note. For the same reason, `plugin doctor` marks the row
`FORCED` in its resolution table. Without the mark, the table would show the
resolution as if the host had selected it by itself.

`force` is the end-user's switch, not yours. Do not document it as the way to
install your plugin. Do not use it to resolve a version difference. Because of
content hashing, the compiler does not grade differences as semver does. Thus
`force` states that somebody checked, and it must not be a default.

## Two namespaces claiming one name

A name is unique in its namespace. `validate` fails a duplicate, because a
duplicate means that the parser read one declaration twice.

A collision across namespaces is legitimate and expected. The http package's
`Request` and a platform's own `Request` are both correct, and an app reaches
them as `http.Request` and `pf.Request`. The header's alias tells them apart,
and the namespace is that alias. Thus a lookup returns both, each with its
origin.

This rule is the opposite of the rule between two platforms. Two platform
answers to `Cmd.exec!` compete, and only one can compile. Across namespaces,
nothing has to be resolved, so `validate` counts collisions and does not fail
them.
