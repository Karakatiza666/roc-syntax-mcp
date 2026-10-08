---
name: author-roc-plugin
description: Author, curate and publish a roc-syntax-mcp plugin - a directory of Roc source, prose and a plugin.json that teaches this server a platform or a package it does not bundle. Covers the manifest, indexing a release with plugin index, how to find the findings worth shipping by running a compiler rather than recalling Roc, the shape of an overview page, the topic files, the scaffold and its sample, and the plugin validate command. Use when adding a corpus for a platform like roc-ray, when publishing a package plugin, when a plugin fails validate or doctor, or when an existing plugin has to be repinned to a newer release.
---

# Authoring a roc-syntax-mcp plugin

A plugin is a directory of Roc source, prose and a JSON manifest. It teaches
this server a corpus that the server does not ship: one platform or one
package. A plugin runs no JavaScript, and it declares nothing outside its own
directory. `docs/design/plugins.md` is the design contract that plugins follow.

The work has two halves, and each half fails in a different way:

| Half | Content | Failure mode |
|---|---|---|
| Mechanical | Manifest, layout, corpus, token ceilings, scaffold | `plugin validate` finds it, every time |
| Curatorial | The overview page, the topics, the facts you chose to state | The plugin compiles, loads and validates, but teaches the wrong thing |

`validate` is one command, and it checks all of the mechanical half. The
curatorial half is the reason to publish. A model already recalls Roc that is
approximately correct. It cannot recall that `Utc.now!` returns nanoseconds, or
that `File` holds only the buffered reader while the full filesystem API is on
`Path`. Both facts are among the seven findings in
`docs/plans/basic-cli-scope.md:155`. Each of the seven was found the same way.
Somebody wrote a program that they expected to work, and the compiler rejected
it.

Thus the standard of evidence is the compiler, not recall. Every claim on your
overview page must come from source that you compiled. If the compiler accepted
everything that you wrote on the first try, you documented only what a model
already knew. `reference/finding-traps.md` describes the method.

## Orientation

`plugin init` writes this layout. The manifest names every path in it. The
server does not discover files, so a file is not bundled only because it is in
the directory.

| Path | Role |
|---|---|
| `plugin.json` | The full declaration. It holds only data, with no regex, no code and no path outside the plugin. See `reference/manifest.md` |
| `package.json` | The npm metadata. This host does not read it, but `validate` checks it, because a path that it leaves out of the tarball is missing after install |
| `index.json` | The parsed modules of the release. `plugin index` writes it from the release that the manifest names. The plugin vendors no source |
| `overview.md` | The page that `roc_overview(scope: <name>)` returns for a platform, or that `search_roc_syntax("<name>")` returns for a package. Of all files here, it has the most effect on what a model writes. See `reference/overview-page.md` |
| `topics/` | Complete programs, one for each area that a model gets wrong. `init` does not write them. You add them |
| `examples/` | Worked programs from the release, listed by `list_roc_index(kind: "examples")`. A caller reads each one by the corpus name and the file name, as in `search_roc_syntax("roc-ray/camera")` |
| `verify/` | One app that holds every snippet that the overview shows, so the page cannot drift from code that compiles |
| `scaffold.roc` | The app that `roc_check` wraps a caller's bare source in. Its full contract is two markers |
| `sample.roc` | Bare source with no header, which is the input that `roc_check` receives. `validate` compiles it through the scaffold |
| `docs/` | Prose from the release, bundled unchanged. Omit the field when the release has no prose |

A directory has an effect only when a manifest field names it. `checks` names
`topics/` and `verify/`, and `validate` compiles each directory in `checks`.
`examples` names `examples/`, and a caller reads that directory.

## The command

The server binary is also the authoring tool, under a `plugin` argument. In
this mode it never speaks JSON-RPC, so these commands start no server that you
must stop.

```bash
roc-syntax-mcp plugin init ./roc-ray --repo=lukewilliamboswell/roc-ray \
  --package=@you/roc-ray --version=0.10.0-rc3 --url=<the release tarball>
roc-syntax-mcp plugin validate ./roc-ray
roc-syntax-mcp plugin inspect ./roc-ray
roc-syntax-mcp plugin doctor
```

`--repo` is the repository that an app header pins, and detection reads it.
`--package` is the npm package id. The two are different when you curate
another person's platform. Without `--package`, `init` scopes the package to
the repo owner, and you would publish under their npm name.

Add `--kind=package` for a package instead of a platform. This writes a
different skeleton, with no scaffold and no sample. The manifest has the same
shape for both kinds: one corpus that names one release. The release's own
header sets the kind. A plugin that documents a platform and the package that
its API uses holds two corpora. Add the second corpus by hand.

`--platform=<url>` sets the platform that the example apps pin for I/O. The
default is the basic-cli that this server bundles. All steps below apply to
both kinds, except Step 6, which is about the scaffold.
`reference/package-plugin.md` covers the rest of the package case.

From a checkout of this repo, `npm run plugin -- <command>` runs the same
command with no install.

| Command | Answers |
|---|---|
| `init` | Nothing. It writes a skeleton. Offline, the only failure in that skeleton is the missing index |
| `index` | Nothing. It writes `index.json` from the releases that `plugin.json` names. It fetches each release with `roc deps` if the Roc package cache does not have it. `--check` compares the file and does not write it |
| `validate` | Would this host serve the plugin, and does all of it compile? |
| `inspect` | What would this host index, by namespace and tier? |
| `doctor` | What would a server started here load, and what would it refuse? |

`validate` runs this repo's own gates (its check scripts) on your directory,
and does not reimplement them. It calls `check-platform-examples.sh` and
`check-roc-check.mjs`. Thus a plugin that passes was checked by the same code
that checks the platforms this server ships.

## Step 0: get the compiler and the release

You cannot finish without a `roc` binary. If none is available, `validate`
reports the two compiler-backed checks as `skip`, not `ok`. A `skip` means that
nobody ran the check.

```bash
ROC=$(echo "$PWD"/roc_nightly-*/roc)   # a glob does not expand in an assignment
export ROC
"$ROC" version
```

Use the nightly that the platform's own CI uses, not the newest one. A platform
release and a compiler nightly work as a pair. If a pair does not build, you
cannot fix it from inside a plugin. Write the nightly that you select on the
manifest's `compiler` line. This host reports the value when it differs from
the nightly that the host bundles. The host never refuses a plugin because of
it, because a host update must not invalidate a plugin that a user installed.

Then get the release that you document, at a tag, and record its tarball URL.
Every app that you write pins that URL, so the compiler fetches the real
platform and type-checks against it.

## Step 1: scaffold, then replace

`init` writes a working plugin for a platform that does not exist. Everything
in it is a placeholder, except the shape.

| Written | Replace with |
|---|---|
| `REPLACE_WITH_THE_TARBALL.tar.zst`, in `plugin.json` and every file with a header | The real release URL. The tarball name is a content hash, so no tool can derive it for you. Then run `plugin index`, which reads the release's modules from the tarball |
| `maintainer` | The person who answers for this corpus. `list_roc_index(kind: "scopes")` prints it unchanged |
| `description` | One line. A model reads it to decide whether to look in this corpus at all |
| `purpose` | A few words that say what a program on this platform is, for example "games, graphics and sound". It is the only line that a caller reads in the list of platforms, before any code exists to detect. The list shows it beside two other lines, so keep it shorter than a sentence |
| The `name` in `package.json` | The id that users declare. `--package=` sets it. Without `--package=`, `init` derives `@<owner>/<name>` from `--repo` |
| `"license": "MIT"` in `package.json` | The license of the corpus, because the corpus is upstream's source. `plugins/roc-ray/` declares `UPL-1.0` and ships upstream's `LICENSE`. A release with no license file grants no rights. In that case, say so in `UPSTREAM`, and in a `LICENSE` that identifies the upstream files. `plugins/weaver/` is the worked example. `UNLICENSED` stops the publish workflow |

Run `roc-syntax-mcp plugin validate <dir> --offline` immediately after `init`,
before you edit anything. Its only failure is `index`, and the message names
the command to run. Then each later failure comes from your edits, not from the
skeleton. When the URL is real, `roc-syntax-mcp plugin index <dir>` writes the
index, and the compiler-backed checks give meaningful results.

## Step 2: decide what to bundle

Bundle what an app author reads. Omit what only a contributor reads, and record
each omission, because an omitted directory and an empty one look the same in a
diff.

| Content | Bundle |
|---|---|
| The release's modules | Never as source. `plugin index` parses every module at the release root into `index.json`. Internal modules go in at host tier, which is addressable but excluded from app-facing search |
| The release's `examples/` | Yes, repinned to the tag that you document |
| The release's prose pages | Yes, as `docs`, if they are real pages. A redirect stub is not a real page |
| `README.md` | No. Curate it into the overview |
| `CONTRIBUTING.md`, `src/`, `ci/`, prebuilt host binaries | No |
| Binary fixtures that an example opens at runtime | No. `roc check` never opens them |

The examples at a tag pin the previous release, so a fresh checkout never
compiles against its own release. A package's examples often have a worse
problem. They pin the package by a relative path, `../package/main.roc`, which
resolves only inside a checkout. In both cases, repin the examples with a patch
that you regenerate for each new tag. Do not edit them in place, because then
you lose the record of what upstream wrote. Change only the pin, and record the
change in `UPSTREAM`. The platform that an upstream example selected is
upstream's choice, not yours.

Patch more than the pin only where a model would copy a pattern that fails
outside upstream's checkout. Put each such change in its own patch, and give
the reason in `UPSTREAM`. `plugins/roc-ray/patches/0001-*.patch` is the worked
example: it makes two examples read their assets beside the executable.

`validate` compiles `<examples>/*.roc`, one file per app, so `examples/` must
have that shape. If a release puts each example in `examples/<name>/main.roc`,
flatten it to `examples/<name>.roc`. An example that imports a sibling module,
or that statically imports an asset file, cannot be flattened. Leave it out.
Record each omission and its reason in the plugin's `UPSTREAM` file.
`plugins/roc-ray/UPSTREAM` is the worked example, with two omissions and a
reason for each.

The exposes list sets the tiers. The `exposes [...]` list in the release's own
`main.roc` sets which modules are app-facing. Each module that the list omits is
behind the host ABI boundary, and the host indexes it at host tier. No manifest
field can change this. The host reads the list from the header, so a plugin
cannot offer the host ABI to a model as app-facing API.

## Step 3: find the traps

A trap is a place where the obvious reading of an API is false. This step gives
the plugin its value, and no check script can do it for you. Work through
`reference/finding-traps.md` from start to end. In summary, write programs that
use the API as an app would, compile each one, and keep what the compiler
rejected. A finding is a fact that is true and surprising, and that a model
would otherwise spend a compile cycle to learn.

Record the findings while you work. The overview page and the topic files both
come from them. If you reconstruct them later from memory, you bring back the
recall that the plugin must replace.

## Step 4: write the overview page

`roc_overview` returns this page whole. Thus every call that reads the page pays
its full token cost, and the page is the first text that a model sees.
`reference/overview-page.md` describes its parts. `validate` enforces a ceiling
of 4000 tokens. A page near the ceiling should hold what a reader needs before
they write code, not reference material that belongs in the index.
`plugins/roc-ray/overview.md` is near the long end. Its page also says how to
build, run and lay out a project, because those differ from `roc main.roc` and a
reader cannot find them by looking up a name. Write that part only when your
platform also differs, as `reference/overview-page.md` describes.

Every fenced `roc` block on the page must also appear in an app under `checks`.
`verify/overview-snippets.roc` exists for this purpose. If a block is missing
from those apps, `validate` fails the page. This check keeps the page from
drifting into Roc that compiled only in the past.

## Step 5: write the topics

Write one complete program per area in `topics/`. Name the directory in
`checks`, so that `validate` compiles it. Declare each program in `topics`, so
that a reader can reach it. A topic is a complete app with a header, and it must
type-check. Each topic should put the findings for its area in comments, at the
line where a model would make the mistake.
`corpus/platforms/basic-cli/topics/cli_sqlite.roc` is an example. Its comments
say why it annotates every binding.

`checks` and `topics` do different jobs, and a plugin needs both. A `checks`
entry is a directory that `validate` compiles and that the server does not
serve. A `topics` entry is a program that `search_roc_syntax` returns, by name
or by keyword:

```json
"checks": ["topics", "verify"],
"topics": [
  {
    "name": "ray_game",
    "file": "topics/ray_game.roc",
    "description": "One line, in the shape a reader would ask the question.",
    "keywords": ["game", "architecture", "delta time", "state machine"]
  }
]
```

A topic name is its address. It must be unique across all corpora, and this
server's own names win a collision. The server matches keywords before the
prose, so write the words that a question would use, not the words in the code.
`validate` reports how many programs it compiles and how many a caller can
reach. Check the second number. A program in a `checks` directory is compiled,
but no caller can read it until a `topics` entry declares it.

Add a topic only for an area of the API that a model would otherwise get wrong.
A topic about an area that the compiler already makes obvious adds tokens to the
index and teaches nothing.

## Step 6: the scaffold and the sample

This step applies only to platforms. `roc_check` wraps bare source in a
platform's app, and its `scope` argument accepts only platforms. Thus a package
plugin declares no scaffold and no sample. Its programs are complete apps that
`roc_check(path:)` reads.

The scaffold is the app that `roc_check` wraps a caller's bare source in. Its
full contract is two markers:

| Marker | Means |
|---|---|
| `# @user-code` | Everything above this line is the prelude. The caller's source goes here |
| `# @default <name>` | The block below this line is used only if the caller's source does not declare `<name>` |

Thus a caller who submits a bare expression gets an app that compiles, and a
caller who submits their own `main!` gets their own `main!`. Put nothing
third-party in a scaffold. If a package stops building, every `roc_check` call
shows errors that the caller cannot fix.

`sample.roc` is bare source with no header, which is the input that `roc_check`
receives. `validate` puts the sample through the scaffold and compiles the
result. Thus the check covers the prelude together with caller source, not the
prelude alone.

## Step 7: packages, if you serve one

A platform corpus declares no dependencies. The `packages { ... }` block in the
platform's header lists what the platform was compiled against. This server
reads the pins from that block, not from a manifest field that can drift. A
package header gives the same information in the brace group after its public
module list, and the server reads it in the same way.

A package corpus is for a package that you document. If the platform's API uses
that package's types, put both corpora in one plugin. The loader then requires
the package to be the release that the platform pins, and refuses the plugin if
it is not. Packages have their own rules for which provider wins, when the host
refuses an override, and how an end-user overrides the refusal. See
`reference/package-plugin.md`.

## Step 8: validate, and read every line

```bash
roc-syntax-mcp plugin validate ./roc-ray
```

`validate` prints one line per check, in this order. `--offline` skips the last
three, which start other processes.

| Check | Fails when |
|---|---|
| `manifest` | The manifest does not load. No other check runs, because no other check can. Before `plugin index` runs, the manifest loads with no corpora, and the checks that need a release's kind wait |
| `name` | Checked once per corpus. The name is reserved, or it is a scope or documented package that this server already ships. The host's copy wins |
| `maintainer` | No maintainer is named. The listing would say so |
| `purpose` | A platform declares no purpose, so the list that a caller selects from prints its full description |
| `paths` | A declared path leaves the plugin, or does not exist |
| `package` | A `package.json` exists and has no name or no version. If there is no `package.json`, the check passes, because a plugin declared by path is never packed |
| `install` | `package.json` declares `preinstall`, `install`, `postinstall` or `prepare`. Neither installer runs these scripts unless the user passes a flag |
| `tarball` | `files` omits `plugin.json` or a path that the manifest names. Such a plugin validates here, and the file is missing after install |
| `index` | `index.json` holds no snapshot of a release that the manifest names. Run `plugin index` |
| `corpus` | The named releases parsed to zero items |
| `duplicates` | One namespace declares a name twice. This is a parser gap, not a legitimate collision |
| `collisions` | Never. A collision across namespaces is legitimate. The check counts collisions, because one lookup returns both items |
| `packages` | Never. It reports which bundled platform's API each declared package crosses |
| `topics` | A declared topic is in no `checks` directory, so nothing compiles it. The check also reports how many programs are compiled but served to no caller |
| `overview` | The page is over 4000 tokens |
| `snippets` | A fenced Roc block on the overview page is in no app under `checks` |
| `index current` | `index.json` differs from what its releases parse to today, or a release cannot be fetched |
| `budget` | The plugin alone does not fit the 180-token growth allowance of some tool, so that tool names part of the plugin only through `list_roc_index`. The check prints the growth of each tool |
| `roc check` | A `.roc` file in `examples` or `checks` does not type-check |
| `roc_check` | The sample does not compile when the scaffold wraps it, or detection does not recognize your header |

Two checks never fail, by design. `collisions` and `packages` only report,
because either result is legitimate, and a count that you can read is more
useful than a rule that guesses. Read them anyway. An unexpected collision count
usually means that a module got the wrong namespace.

Then examine what the host would do with the plugin:

```bash
roc-syntax-mcp plugin inspect ./roc-ray
```

The counts by tier are the fastest way to find an exposes list that the host did
not read. If almost every item is at host tier, the release's `main.roc` gave no
exposes list.

## Step 8b: ask the server what a caller gets

The checks above measure the corpus. None of them measures whether a caller can
reach it. Every plugin written so far lost time at this point. A corpus that is
compiled, indexed and unreachable passes every check in the table.

Start a server with `--plugin=<dir>` from a workspace that has the app header
that a real user would have. Then ask the questions that a user would ask.

| Ask | Because |
|---|---|
| `list_roc_index(kind: "scopes")` | A platform appears as a scope, with the item count that `inspect` reported. A package appears under "Documented packages", and the entry says whether this app pins it |
| A topic, by its own name | The name is an address, and it must resolve |
| A topic, as the question that its description states, with no `scope` | This is the query that fails. Retrieval takes the first match across all installed corpora, and your corpus is the newest |
| One name, with `lookup_builtin` and no `scope` | Ask once. If the name gets two answers, the server indexes one tree twice. For a package, ask from a workspace that pins it and from one that does not. In the second workspace, the answer is a miss that names your package |
| `roc_overview scope="<name>"` for a platform, `search_roc_syntax("<name>")` for a package | The server returns the full page, and it is the page that you wrote |

A wrong answer here is not always a defect in your plugin. If the corpus is
correct and retrieval is wrong, the bug is in the host.
`reference/finding-traps.md` lists the host bugs found this way. It also lists
more that were found by reading the tool calls of an agent that used a plugin.
That transcript is the cheapest source of defects. It costs nothing to collect,
and it shows the calls that a caller wasted, which no check measures.

## Step 9: publish

A plugin is a usual npm package that contains no JavaScript. `init` wrote its
`package.json`, and three of its fields are often wrong. This table lists them
with the related manifest fields.

| Site | Carries |
|---|---|
| `plugin.json` `release` | The platform release, not your plugin's own version |
| `plugin.json` `compiler` | The nightly that you built against |
| `plugin.json` `maintainer` | The person who answers for the corpus |
| `package.json` `name` | The id that users install and declare. `plugin add @you/roc-ray` installs it, and `--plugin=@you/roc-ray` resolves `@you/roc-ray/plugin.json` |
| `package.json` `version` | Your version. Increase it when the corpus changes. The manifest records the release that the plugin documents |
| `package.json` `files` | Every path that the manifest names, plus `plugin.json`. `init` derives the list, so keep it derived |
| CI | `roc-syntax-mcp plugin validate .`, so that each published version has passed the checks, and users do not have to trust the author |

No script may run on install. Both npm and bun block a package's install
scripts until the user passes a flag. Thus a `prepare` script that assembles
your corpus gives a half-built plugin to each user who did not pass the flag,
and that plugin fails at the first lookup. If your plugin needs a build step,
put it in `build` and run it before you publish.

```bash
cd plugins/roc-ray
roc-syntax-mcp plugin validate .
npm publish
```

In the roc-syntax-mcp repository, each directory under `plugins/` is a separate
child package. It has its own version, and it is not in the server's own
tarball. `plugins/README.md` describes that contract.

Tell users how to declare the plugin, in the form that they will paste:

```bash
roc-syntax-mcp plugin add @you/roc-ray
```

That command installs the plugin for every workspace.
`roc-syntax-mcp plugin list` shows what is installed, and
`roc-syntax-mcp plugin remove @you/roc-ray` removes it. `--plugin=@you/roc-ray` and `ROC_MCP_PLUGINS` are the other two
declaration sources, and the server adds the declarations from all three
sources together. Only `plugin add` installs anything, and only when the user
runs it.

## Repinning to a newer release

A repin does not need a rewrite. The release version appears in more places
than a search for the tag finds, because most of them carry the tarball hash.
The version and the hash change together.

| Site | Change |
|---|---|
| `plugin.json` | `compiler`, if the nightly changed with the release |
| A `roc: "nightly-..."` entry in any vendored header | Remove it. It pins a compiler, and a nightly that is one day off gives a warning on every file. `validate` counts that warning as a failure |
| `scaffold.roc`, `sample.roc` if it has a header | The tarball URL |
| `topics/*.roc`, `verify/*.roc` | The same header |
| `examples/*.roc` | Regenerate the repin patch against the new tag |
| `overview.md` | The header snippet. The page states no version, so no other line changes |
| `plugin.json` `release` | The new tarball URL, then `plugin index`. The `index current` check in `validate` fails until you run it |

Then do Step 3 again against the new release, and run `validate`. An incomplete
repin fails the `roc check` check and does not ship, because every app in the
plugin pins the URL by hand.

## Invariants

Keep these true. `validate` enforces most of them. Reread the ones that it does
not enforce.

- The plugin declares nothing outside its directory, and nothing in it is code.
- Every claim on the overview page came from source that was compiled, and every
  fenced Roc block on the page appears in an app under `checks`.
- Every topic file is a complete app that type-checks.
- The scaffold pins nothing third-party.
- Each corpus's `release` is the release that every app in the plugin pins. A
  package shipped beside a platform is the release that the platform pins.
- The exposes list sets what is app-facing. A host-tier module stays addressable
  and excluded from app-facing search.
- Each finding is written at the line where a model would make the mistake, not
  only in the overview.
- The manifest names a maintainer, because the listing shows the maintainer
  field in all cases.
- No script runs on install, and `files` packs every path that the manifest
  names.
- A newer host never invalidates a published plugin. New fields are added, an
  existing field never gets a new meaning, and this host ignores a field that it
  does not know.
- The check results and the answers that a caller gets are two separate
  measurements. The answers that a caller gets are the goal.
