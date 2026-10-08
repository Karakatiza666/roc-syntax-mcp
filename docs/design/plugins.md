# Platform and package plugins

This page describes how the server works when a user installs corpora that the
server does not ship. It covers what a plugin is, what the server does with it,
and what a caller sees when two plugins disagree.
`docs/plans/platform-plugins.md` has the build order and the file-level work.

## What a plugin is

A plugin is a directory of Roc source, prose and a JSON manifest. No JavaScript
from a plugin ever runs. The manifest lists corpora, and each corpus documents
one release:

| Corpus | Ships | Example |
|---|---|---|
| A platform | Its modules, topics, an overview page, a scaffold | `@roc-syntax/roc-ray` |
| A package | Its modules and prose | `@roc-syntax/weaver` |

One plugin holds all the corpora that one install needs. If the API of a
platform uses the types of a package, the plugin ships both. For example,
joy's `render` returns joy-html's `Html`, and the documentation of one without
the other leaves half of the API unexplained.

Both kinds take the same fields. The header of the release tells which kind a
corpus is. The release URL gives the name, the version, and the repository
that detection matches. Thus no manifest field can contradict the release
content. The server refuses the fields that only a platform uses, `scaffold`,
`sample` and `docs`, on a package.

A user installs a plugin package and then names it. The server does not scan
for plugins, and it does not load a plugin only because the plugin is in a
nearby directory. `plugin add` does both steps in one command:

```
roc-syntax-mcp plugin add @roc-syntax/roc-ray
```

`plugin add` installs into a folder that the server owns. It uses npm, or Bun
when the server runs under Bun, so the registry and login settings of the user
apply. `ROC_MCP_HOME` changes the folder. The default folder is:

| OS | Folder |
|---|---|
| Linux | `$XDG_DATA_HOME/roc-syntax-mcp/plugins` |
| macOS | `~/Library/Application Support/roc-syntax-mcp/plugins` |
| Windows | `%LOCALAPPDATA%\roc-syntax-mcp\plugins` |

The dependencies in the `package.json` of that folder are the installed set.
`add` checks each package in the same way as the server at startup, together
with the plugins that are already installed. If the server would refuse the
package, `add` undoes the install. The server loads the installed set in name
order, so a new plugin can take a name from a plugin that the server serves at
present. `add` refuses that case too, because at the next start the server
would drop the older plugin with no message. A package that is installed but
has no `plugin.json` is reported as not a plugin, not as missing. If an
installed plugin does not resolve, for example a path plugin whose folder was
deleted, the server skips it in every workspace. The message names
`plugin remove` as the fix. `add` works for every type of server install, so
it also works under `npx`, `bunx`, `yarn dlx` and pnpm 11.

A plugin can be declared in three places. The server combines all three,
because each one has a different purpose:

| Source | For |
|---|---|
| `plugin add` | Per user: served in every workspace. The command itself names the plugin. The main path |
| `--plugin=<pkg-or-path>`, repeatable | One client entry. A project's committed client config, such as `.mcp.json`, carries it for that project only |
| `ROC_MCP_PLUGINS` | The same, for clients that pass environment variables more easily than arguments |

The server looks for a package name in the `plugin add` folder, then beside
its own install. The second location is for global installs: `npm i -g`,
`yarn global add`, `bun add -g` and pnpm up to 10 put a plugin beside the
server. pnpm 11 isolates every global package, so with pnpm 11, `plugin add` is
the only global path. The server resolves a relative path against the
workspace.

The server has no config file of its own in the workspace. Every client has a
project config that teams commit, and that config can carry `--plugin=` and
`--platform=`. Also, a server that a client starts for every project would not
find a file that it reads one time at startup from the working directory. If
such a file named a plugin that a teammate did not install, the server would
fail to start for that teammate.

## One server, one tool list

The alternative design is one MCP server per platform. Each server costs about
2700 tokens, and the model must select between the servers on every call. With
one server, a platform adds about 21 tokens, the size of its scope name in five
tool schemas. Nothing else changes.

Topic names are the part of the tool list that grows with each plugin.
`search_roc_syntax`'s description lists them, for the platforms that apply:

| Configuration | Listed |
|---|---|
| A platform set, by `--platform=` | The language topics, plus that platform's |
| No scope set, plugins installed | The language topics, plus every installed platform's |
| Neither | The language topics, and a pointer to `list_roc_index(kind: "topics")` |

The server answers `tools/list` before the first tool call, and detection does
not run until that call. Thus only the configuration is available to
`tools/list`. Without a configured platform, the installed plugins are the best
data available, and the description is the cheapest place to name their
topics. A model asks by name for a topic that the description lists. For a
topic that the description omits, a model guesses, misses, and tries again.

A platform plugin that a user did not install adds no topic names to the tool
list of that user. A user pays tokens only for the plugins that the user
installed.

The allowance applies per tool, not per plugin, because `plugin add` serves a
plugin in every workspace. With ten installed plugins, an allowance per plugin
does not limit the total. All loaded plugins together add at most
`PLUGIN_TOOL_GROWTH` (180) tokens to one tool. Each tool spends its own
allowance in declaration order. Topic names come first, in `search_roc_syntax`.
Scope names come next, in the `scope` enum and in the "Name a platform" hint.
A caller gets the remainder through the listing:

| Over the allowance | The tool says |
|---|---|
| Topic names | "N more topics: list_roc_index(kind='topics')" |
| Scope names | `scope` becomes a string, checked against the same values, and its description points at `list_roc_index(kind='scopes')` |

Measured on 2026-10-07 with ten synthetic platform plugins of three topics
each: without the allowance, `search_roc_syntax` grew by 229 tokens. With it,
no tool grows by more than the allowance plus its pointer.

The allowance is 180 tokens for these reasons. A platform plugin adds about 3
tokens to a tool with only a `scope` enum, and about 6 to a tool that also has
the hint. It adds 25 to 33 tokens to `search_roc_syntax`, which lists its topic
names. Thus in practice, the allowance limits only `search_roc_syntax`:

| Tool | Plugins that fit at 60 | At 180 |
|---|---|---|
| `scope` enum only | ~20 | ~60 |
| Enum and hint | ~10 | ~30 |
| `search_roc_syntax` | ~2 | ~6 |

With an allowance of 60, roc-ray, weaver and joy together (about 82 tokens in
`search_roc_syntax`) cut some of joy's topics. With 180, six typical plugins
cost about 340 tokens more than the 2770 of the shipped tool list. In the
theoretical worst case, every tool is at its allowance. That case costs 1440
tokens and needs about 60 platform plugins.

## The address space

An address space is the set of namespaces that a lookup searches. It holds the
language, the builtins, and at most one platform. This rule makes plugins
practical. Two platforms never need to agree about `Path.read_utf8!`, so two
plugins never need to negotiate.

Every indexed item has a namespace. The namespace identifies the body of Roc
source that the item comes from:

| Namespace | Is |
|---|---|
| `builtin` | `corpus/language/Builtin.roc` |
| `platform:basic-cli` | A platform's own modules |
| `pkg:roc-lang/http` | A package's modules |

The repository path is the identity. The version is an attribute of the
provider and is not part of the key. Thus `roc-lang/http` at 1.0.0 and at 1.2.0
are one namespace with two candidate providers, not two separate namespaces.

| Namespace | In the space when |
|---|---|
| `builtin`, language | Always |
| `platform:<name>` | It is the active platform. At most one |
| `pkg:<id>` | The active platform declares it, or the detected app header pins it |

A package is a namespace, not a scope. A `scope` value selects the language,
the builtins or one platform. A package, like the builtins, is a library that
an app uses.

| What | Where |
|---|---|
| A package the app pins beyond the platform | Searched with the builtins: every unscoped search, `scope: "builtin"`, `search_symbols` and `get_builtin_module`. Each item names its origin |
| A documented package nobody pins | In no space. A lookup that misses names the package, shows up to three matching signatures, and gives the header line that pins it |
| Its page | `search_roc_syntax("<name>")`, which also takes the repository path, and the resource `roc-syntax://package/<name>` |
| Its topics and examples | Filed under `language`, so a question finds the package before any app pins it. Each example is read by the package name and the file name, as `search_roc_syntax("roc-parser/csv-movies")`, or as the resource `roc-syntax://package/roc-parser/example/csv-movies` |
| Its name and maintainer | `list_roc_index(kind: "scopes")`, under "Documented packages", and one clause each on the default `roc_overview` |

None of these add a value to a `scope` enum. But package names and scope names
are one set of names, so no plugin can replace a page that this server ships.

## What the Roc compiler permits

The precedence rule below follows from the behavior of the compiler.
Upstream's `corpus/language/langref/packages.md` is a `TODO` stub, so this
behavior was measured against the bundled nightly.

| Experiment | Result |
|---|---|
| App pins a byte-identical copy of http at a fresh local path, and the platform pins the 1.0.0 tarball | Compiles |
| Same, with one comment line appended to `Response.roc` | `type mismatch` at the platform boundary |
| App pins both copies at once and keeps the second one off the boundary | Compiles |

The compiler identifies a package by its content, not by the URL that it was
fetched from. The second experiment changed only a comment, and
`Server.respond` stopped accepting the app's `Response`. The compiler names
both types `Response`:

```
This argument has the type:
    Response
But the function needs the first argument to be:
    Response
```

This behavior has three consequences:

1. Semver carries no compatibility information. For a type that crosses a
   platform boundary, a patch bump breaks the app as much as a major bump.
2. Two versions can coexist in one app, so a mismatch is not always a mistake.
   A mismatch breaks the app only where the types of the package cross the
   exposed API of the platform.
3. The corpus shows if the types cross: an exposed module has
   `import http.X`.

| Platform | Exposed modules importing the package |
|---|---|
| basic-webserver | `Http`, `MultipartFormData`, `Server` |
| basic-cli | `Http` |

Both platforms cross. For both, a package plugin that serves a version other
than the pinned version describes an app that cannot be written.

This test over-approximates. A module can import a package type and never
expose it in a public signature. Thus the server refuses some overrides that
would work. A refusal is the safe error.

## Which provider answers

The server chooses one provider per namespace, one time:

| Tier | Provider | Why it wins |
|---|---|---|
| 0 | The exact release the header pins, read from the compiler's package cache | Those are the bytes the app compiles against. Used only when no other provider has that release |
| 1 | A package corpus in a declared plugin | Somebody installed it for this namespace |
| 3 | The host's vendored copy | So that the server works with no plugins installed |

Tier 2 is not used. It was the tier for a platform's vendored copy of a
package. Each package is a corpus of its own, in the plugin that ships it, so
no provider has tier 2. The number is not reassigned.

Tier 1 wins over tier 3 only under the conditions below, which follow from the
compiler result above:

| Package crosses the active platform's exposed API | Versions agree | Outcome |
|---|---|---|
| Yes | Yes | The package plugin wins with no message. Same package, better documentation |
| Yes | No | Refused. The server serves the platform's copy and reports the reason |
| No | Either | The package plugin wins. The app pins that package itself, and the platform's pin has no effect on the app |

The server reads the required version from the platform's own header, the
`packages { ... }` block that the platform was compiled against. It does not
read the version from a manifest field, because a manifest field can become
out of date. The app header that the platform's scaffold generates must agree
with this block. `check:platforms` compiles that scaffold on every run, so a
compiler verifies the pin.

Here the server gives information that the compiler does not give. The
compiler's diagnostic shows `Response` on both sides and does not name the
package. The server can tell which two pins disagree and which one the
platform requires.

## Where a release's source comes from

A manifest names each corpus by `release`, a tarball URL. The plugin ships the
`index.json` that `roc-syntax-mcp plugin index` writes from that release. No
plugin and no corpus in this repository vendors release source. The server
refuses a plugin that names a `dir`, with a message that names `plugin index`.
Only the language scope of the host reads a directory, because `Builtin.roc`
is not a release.

| Source | Read from | Written by |
|---|---|---|
| `release`, documented by a manifest | `index.json` beside the manifest: each module's parsed signatures and imports, and the header's `exposes` and pins | `plugin index`, or `npm run build:index` for this repository's own corpora. Both read the compiler's package cache. `check:index` and the `index current` check of `validate` make sure that it matches the release |
| `release`, any other | The compiler's package cache, `<cache>/roc/packages/<hash>/` | `roc deps`, run by the server |

One table holds the snapshots, keyed by hash. The first file that holds a hash
wins. The server reads its own files first, so a plugin cannot replace the
snapshot of a release that this server documents.

The hash in the URL identifies the release in all three places. Thus a
pre-built snapshot and a cached tree for one hash come from the same bytes. The
server uses the pre-built snapshot first, because the gates (the named check
scripts, such as `check:platforms` and `plugin validate`) measured it.

### A release the app pins and no corpus documents

Detection reads the URLs in the app header. Before the first answer, the
server lists the releases that it needs and cannot read:

- a platform pinned at a release other than the bundled one,
- a package pinned at a release that no provider has.

For each one, the server runs `roc deps` on a stub app that pins it. `roc deps`
downloads the release, checks the hash, and unpacks it with no compile. Then
the server answers. The wait occurs one time per release, in the call that
found the release. An answer of "not fetched yet" would cost the model one turn
to fill the cache and another turn to ask again.

| What the header pins | What is served |
|---|---|
| A platform at the bundled release | The pre-built index, the overview, the topics |
| A platform at another release | That release's signatures and its header's pins. The overview, topics and examples stay the bundled release's, and a note says so |
| A package at a release some provider has | That provider, by the tiers above |
| A package at a release none has | Tier 0, from the cache |
| A release `roc deps` could not fetch | What the tiers give without it, with the pin conflict note |

The server never limits prose to a matching version. This applies to a
platform, a package and a plugin, and also across a major version. A page
written for another release is mostly still correct. An agent with no page
writes worse code than an agent with a page that is slightly out of date. Only
signatures follow the pin.

The server opens no network connection itself. `roc` opens one, but only for a
release that an app header names. `roc check` makes the same download on its
first run.

## When nothing serves a namespace

After a refusal, the server tries the next tier: tier 1 refused, then tier 3.
The host vendors only `roc-lang/http`, roc-parser and roc-random. For any other
package, the namespace can end with no compatible provider, and then it adds
nothing to the space.

This state can occur, and the server always reports it. The report uses the
out-of-scope note:

```
No provider serves lukewilliamboswell/weaver.
Your app header pins 0.8.0; @roc-syntax/weaver serves 0.9.0.
Install a package plugin at 0.8.0, or run this server with
--force=lukewilliamboswell/weaver to read 0.9.0 anyway.
```

The obvious alternative is to serve the incompatible copy with a warning. Two
problems prevent this:

1. `roc_check` would contradict `search_symbols`. `roc_check` compiles the app
   against the 0.8.0 that its header pins, but the lookup prints 0.9.0
   signatures. A server whose own tools disagree about one name is worse than a
   server that declines to answer.
2. Documentation labeled 0.9.0 can cause a model to write that pin into the app
   header, next to a dependency that pins 0.8.0. Only this case causes a
   `CliParser` against `CliParser` error that the compiler cannot explain.

This choice has a cost. With no provider, a model falls back on the Roc that it
recalls, and this server exists to prevent that failure. Thus the note names
both solutions, and the end user makes the choice.

## `force`

The server reads the boundary test from the corpus, and a plugin author may
know more. The end user can override the test, for one namespace at a time.
The override comes only from the configuration, never from a manifest, so a
plugin can never vouch for itself:

| Source | Written |
|---|---|
| `--force=<id>`, repeatable | `--force=lukewilliamboswell/weaver` |
| `ROC_MCP_FORCE` | Same separators as `ROC_MCP_PLUGINS` |

Both sources name a namespace directly. An id that is not a repository path
names no namespace. The server reports a diagnostic for such an id and does not
ignore it, because the operator wrote the id to change a resolution.

Every item from a forced namespace names the version that it was forced over,
as `(weaver 0.9.0, forced over 0.8.0)`. The note is on each item, not in a
footer. The override changes every signature in that namespace, and a caller
who reads only one item must still see the note.

`force` is never the default for a version difference, minor or major. The
compiler identifies a package by a hash of its content, so it does not rank
differences as semver does.

## Two namespaces claiming one name

A namespace prevents collisions inside it. Across namespaces, a collision is
valid. The http package's `Request` and a platform's own `Request` are both
correct, and the app gets them as `http.Request` and `pf.Request`. The alias
in the app header selects between them, and the namespace is that alias.

Thus a lookup for a name that more than one namespace in a space claims returns
all of them, each with its origin. The rule for two platforms is the opposite.
Two answers to `Cmd.exec!` from two platforms compete, and only one can
compile.

## Stale plugins

A host update never invalidates an installed plugin. The end user decides if a
plugin is stale, so the server only reports the signals below and continues.
All three signals appear in `list_roc_index(kind: "scopes")` and nowhere else,
because provenance on every response costs tokens on calls that do not need
it.

| Signal | Reported as |
|---|---|
| Manifest `compiler` differs from the host's `corpus/language/UPSTREAM` | Built against a nightly this server does not bundle |
| Workspace pins a version the plugin does not serve | The existing version-mismatch note |
| Manifest `schema` older than the host's current | Named, with no other effect |

These schema rules keep that guarantee:

- The server ignores unknown manifest fields.
- Every field added after v1 is optional and has a default.
- The meaning of a field never changes under an existing name.
- The server reports the `schema` version and does not refuse a load because
  of it.

## When a plugin set is misconfigured

The server resolves conflicts one time, at load. The result is a fixed table of
one provider per namespace, and a list of diagnostics. No tool call computes a
resolution again.

The server does not exit on a misconfigured plugin set, for three reasons:

- An MCP server that stops at startup is almost impossible to diagnose over
  stdio.
- The language reference, the builtins and the bundled platforms do not depend
  on any plugin.
- The installed set is global, so one stale entry would stop the server in
  every workspace.

| Failure | Behavior |
|---|---|
| A plugin named in `--plugin=`, `ROC_MCP_PLUGINS` or `plugin add` cannot be resolved at all | Skip it, load the rest, diagnose on stderr and in the first `roc_overview` answer |
| A manifest is unreadable or malformed | Skip that plugin, load the rest, diagnose |
| A manifest carries fields this host does not know | Load it |
| A corpus file fails to parse | Skip the file, keep the plugin, diagnose |
| Two plugins claim one scope name | First wins, second skipped, diagnose |
| A package override is refused, leaving the namespace empty | Resolve as above, diagnose, answer lookups with the note |

The server writes diagnostics to stderr at startup, for an operator, and to
`list_roc_index(kind: "scopes")`, for a model. It is best to find a bad plugin
set before the server runs, and `plugin doctor` does that check.

## Authoring a plugin

A manifest lists corpora, each naming its release:

```json
{
  "schema": 1,
  "maintainer": "niclas-ahden",
  "corpora": [
    { "release": "https://github.com/niclas-ahden/joy/releases/download/<tag>/<hash>.tar.zst", "description": "...", "scaffold": "joy/scaffold.roc" },
    { "release": "https://github.com/niclas-ahden/joy-html/releases/download/<tag>/<hash>.tar.zst", "description": "..." }
  ]
}
```

Detection is declarative, with no regex. Every Roc platform is pinned by a
release URL, and a regex from an untrusted manifest adds only the risk of ReDoS
(regular expression denial of service). The host builds
`<repo>/releases/download/(version)/` from the repository in the release URL of
a platform. The captured version is the whole tag, including a prerelease
suffix. An app that pins `0.10.0-rc3` pins exactly that tag. A prerelease sorts
below the release that it precedes, so the server reports a pin as older or
newer by the semver rules.

A `release` is any URL that an app header can pin: an https URL whose file
name is the content hash of the tarball. `roc deps` fetches only this form of
URL.

| URL | Namespace | Version |
|---|---|---|
| A GitHub release URL | The repository, which is also the name | The tag. Versions are ordered |
| Any other URL | The host and directory | The first 12 characters of the hash. Versions can only be compared for equality, so a different bundle is reported as different, not older or newer |

A commit is not a release, because no header can pin a commit. `roc deps`
refuses a GitHub archive URL, because the file name of that URL is a commit
SHA, not a content hash.

The header of a release tells if it is a platform or a package, and
`plugin index` records the kind in `index.json`. A fetch does not need the
kind. `roc deps` on a stub that pins any release as a platform unpacks the
release into the cache, and only then reports "invalid platform" for a
package.

A platform corpus declares no dependencies. The platform was compiled against
the `packages { ... }` block in its header, so the server reads the pins of the
platform from that block. A plugin whose platform re-exports http ships no
http files. The server still reports an error when the provider for the http
namespace has a different release.

If a plugin ships a platform and a package that the platform pins, the plugin
must ship the pinned release of the package. For the compiler, two releases
with different content give two different nominal types. Thus the loader
refuses any other release, and its message names both versions.

`purpose` is a few words that tell what programs the platform is for, for
example "games, graphics and sound". Before there is code to detect,
`roc_overview` lists every platform by name and purpose and asks the caller to
select one. Without this list, a model can only guess. Each platform gets one
line in the list, so the field has a limit of 60 characters. If a manifest has
no `purpose`, the server uses `description`.

`maintainer` names the person responsible for the corpus. The scope listing
prints it exactly as written, and nothing checks its content.

Two more fields describe what a gate compiles, not what a caller reads. With
these fields, a plugin is checked in the same way as the platforms of this
repository:

| Field | Is |
|---|---|
| `sample` | Bare source with no header, in the same form that `roc_check` submits. The gate wraps it in `scaffold` and compiles it, so the prelude is verified together with a sample and not alone |
| `checks` | Directories of complete programs beyond `examples`: topic files, and the app holding every snippet the overview page shows |

`topics` is the complement of `checks`. A `checks` entry makes the gate compile
a program. A `topics` entry makes a program readable. Each `topics` entry names
a program in the plugin and the words that a question about it would use.

```json
"topics": [{
  "name": "ray_game",
  "file": "topics/ray_game.roc",
  "description": "One line, in the shape a reader would ask the question.",
  "keywords": ["game", "architecture", "delta time", "state machine"]
}]
```

Declared topics join the registry that `search_roc_syntax` answers from and
that `list_roc_index(kind: "topics")` lists, under the plugin's own scope. Thus
a platform that this server does not know answers a question in the same way
as basic-cli. The name of a topic is its address, and it is unique across all
corpora. If names collide, the names of this server win, and the server
reports the other topic and does not serve it. Without a `topics` declaration,
the gate compiles a `checks` directory on every run, but no caller can read it.
For this reason, this repository's own roc-ray plugin shipped six programs that
no caller could read.

A lookup by the exact name of a declared topic finds the topic, whether or not
the caller selected that platform. The description of `search_roc_syntax` names
the topics of each installed platform. If the server refused a name that the
caller read there, the description would advertise a call that then answers
"no topic matched". The reply names the corpus of the topic. A search by
keyword or by question stays inside the scopes that the caller selected.

The server binary also has the authoring tools, under a `plugin` argument. In
this mode, the binary does not speak JSON-RPC, so it does not import the
server:

| Command | Does |
|---|---|
| `plugin init <dir>` | Manifest, layout, a scaffold stub with its markers, a sample for it, and the verify app that compiles the overview's snippets |
| `plugin index <dir>` | Writes `index.json` from the releases the manifest names, fetching each with `roc deps` when the cache lacks it. `--check` compares |
| `plugin validate <dir>` | Runs the gates of this repository on another directory |
| `plugin inspect <dir>` | What the host would index: counts by tier, namespaces, which overrides would be refused |
| `plugin doctor` | Reads the config the server would read and prints the resolution table plus every diagnostic |

`validate` checks the mechanical properties:

- the manifest schema and the corpus parse,
- `roc check` on every `.roc` file, and the scaffold round trip,
- the token ceiling of the overview, and that the verify app has every
  overview snippet,
- the token growth of each tool,
- collisions across namespaces,
- which declared packages cross the exposed API of the platform.

`validate` is part of the published package. Thus a user does not need to
trust the author alone, because the author can run the same gate in their CI.

No script can check the other properties. The value of this server is in
findings like the seven in `docs/plans/basic-cli-scope.md:155`. Each one was
found by writing a program and observing that the compiler rejects it. No
script can make sure that someone noticed that `Utc.now!` returns nanoseconds.
`.claude/skills/author-roc-plugin/` gives the model of an author the method,
the probes that produced those findings, and the shape of an overview page.

The listing names the maintainer of each scope, from the `maintainer` field,
and tells when no maintainer is named. This design lets anyone publish a
plugin. The worst that a corpus can do is give wrong information about Roc,
which is the same harm as a wrong overview page in this server. Thus the
server tells whose page it is and does not refuse pages that nobody vouched
for. `validate` fails a plugin with no maintainer, but the loader serves it,
because publication is the right time to ask for a name.

Because a plugin is only data, an author cannot use a hook to work around a
limitation of the host parser. The author reports a bug, and the fix applies to
every platform. The two limitations that basic-cli found, unannotated members
and space indentation, are examples.

## A release the nightly cannot build

Sometimes a release fails on the pinned nightly, and upstream has a fix that it
has not released. roc-parser 2.0.0 was the first case. On nightlies from
2026-10-04, its `Yaml.roc` gives a redundant-expose error, so only an app that
imports `Yaml` fails. The corpus pinned 2.0.0 nonetheless, because users get
that release, until a fixed release replaces it.

With `scripts/gate-overrides.json`, the gate can check those apps:

| Step | `check:platforms` |
|---|---|
| 1 | Compiles each file as written |
| 2 | Only if that fails, and the file pins a release the list names: copies the cached release, applies the listed `gate-` patch, and compiles a copy of the file pinned to the patched `main.roc` |
| 3 | Reports `ok (override: <patch>)` under the original path, and counts the file in the summary |

A file that compiles against the real release never gets to step 2, so the
override cannot hide a problem that it does not fix. The server serves no
patched file. The list is not in `files`, so `plugin validate` in an install
measures every plugin against the published release. A test fails while an
entry names a release that no corpus file pins, so the entry is removed
together with the repin.

## Out of scope

| Not doing | Why |
|---|---|
| Plugins that ship JS | Plugin code would run with access to the compiler and the workspace |
| A downloaded plugin registry | Needs the network at stdio startup, and fails offline |
| Auto-scanning sibling `node_modules` | Works for flat installs, but fails with pnpm's isolated store. ESLint and Prettier chose explicit declaration for the same reason |
| Refusing to load a stale plugin | The end user decides. The refusal of a package override that crosses a platform boundary is a different case, based on a compiler result, not a guess |
| Packages as scopes | Costs tokens for a distinction that no caller needs |
| Two platforms in one space | Decided in `docs/plans/basic-cli-scope.md:51`. Plugins do not change this decision |
| Exiting on a plugin conflict | A conflict does not affect the language, the builtins or the platform, and a stdio server that stopped is the hardest failure to diagnose |
