# Child projects

Each directory here is one npm package. Each package is a corpus that this
server can load, published on its own schedule, under its own name and
version. Nothing here is part of `roc-syntax-mcp`. The `files` list of the root
package does not name `plugins/`, so no child is in the server's published
tarball. An install directly from the git repository copies the repository,
including the children, but loads none of them. The server serves a plugin
only when it is declared, never because it is present.

## Why there is no `workspaces` field

A standard npm monorepo declares its children at the root. This repository
does not, because of this code in npm's own installer, `pacote/lib/git.js`:

```js
if (!mani.workspaces && (!scripts || !(scripts.postinstall ||
    scripts.build || scripts.preinstall || scripts.install ||
    scripts.prepack || scripts.prepare))) { return }
```

In the early return, npm installs a git dependency by copying the tree. If the
manifest declares `workspaces` or a script named `build`, npm does not return
early. It runs an install inside its clone. Install scripts are blocked by
default, so this install leaves a link to a temporary directory, and npm then
deletes the directory. `npm i -g git:...` gives a broken install and shows no
error.

Thus the root manifest declares neither of the two. The build script is
`build:ts`, and `src/package.test.ts` checks both facts against the rule above.
bun installs a workspace root from git with no error. Only npm has this
problem, and npm users are half of the users.

The cost is that npm does not hoist dependencies across children. Here that
has no value: a plugin runs no JavaScript, so a corpus has no dependencies to
hoist and nothing to build.

| Concern | Answer |
|---|---|
| Installing the server from git | Root `package.json` is the server, and an installer reads it and copies the tree |
| Installing a child's dependencies | `cd plugins/<name> && npm install`, if it ever has any |
| Building a child | Never on install. `cd plugins/<name>` and run its own scripts |
| Publishing a child | `cd plugins/<name> && npm publish`. Its version is its own |

## What a child owes

`roc-syntax-mcp plugin validate <dir>` checks all the rules. It reads the
package.json and the manifest. Three rules apply to the npm package, not to the
corpus:

| Rule | Because |
|---|---|
| No `preinstall`, `install`, `postinstall` or `prepare` script | npm and bun block install scripts until a user allows them, and a corpus does not need that permission |
| `files` covers `plugin.json` and every path the manifest names | A corpus path outside the tarball passes `validate` in your checkout, but it is missing after the install |
| The package name is the id users install and declare | `roc-syntax-mcp plugin add @you/roc-ray` installs it, and `--plugin=@you/roc-ray` resolves `@you/roc-ray/plugin.json` from node_modules |

One more rule applies to what a caller can read. `validate` compiles each
program under a `checks` directory, but the server serves such a program only
if a `topics` entry in the manifest names it. Then `search_roc_syntax` can
return the program. `validate` prints the number of programs and the number of
topics, so that you can see the difference.

## What a plugin can add

A plugin is data. It adds no tool and runs no code. No manifest field
registers a tool or names a script. A plugin extends the tools that this server
has:

| A plugin adds | A caller reaches it through |
|---|---|
| A platform scope, with its overview, API and examples | `scope` on every tool that takes one, and `roc_overview(scope: "<name>")` |
| A scaffold | `roc_check(scope: "<name>")`, which wraps a bare snippet in the platform's app |
| A package's signatures | The builtin lookups and searches, once an app header pins the package |
| A package's page | `search_roc_syntax("<name>")` |
| Topics | `search_roc_syntax`, by name or by keyword |

A plugin adds text to `tools/list`, and every request carries that text. The
plugin adds its scope name to the `scope` enum of each tool that takes one, and
its topic names to the `search_roc_syntax` description. `plugin add` serves a
plugin in every workspace, so the limit applies per tool, not per plugin. All
loaded plugins together add at most 180 tokens to one tool
(`PLUGIN_TOOL_GROWTH` in `src/scopes.ts`). Above that limit, the tool points to
`list_roc_index` for the rest:

| Over the limit | The tool says |
|---|---|
| Topic names | "N more topics: list_roc_index(kind='topics')" |
| Scope names | The `scope` argument becomes a string, checked against the same values, and its description points at `list_roc_index(kind='scopes')` |

The `budget` check in `validate` prints the growth of each tool. The check
fails a plugin that goes over the limit when it is the only installed plugin.

## What is here

| Directory | Package | Serves |
|---|---|---|
| `joy/` | `@roc-syntax/joy` | The Joy platform and the joy-html package its views are written in, two corpora in one plugin |
| `roc-ray/` | `@roc-syntax/roc-ray` | The RocRay platform |
| `weaver/` | `@roc-syntax/weaver` | The Weaver argument parser, as a page and as the `lukewilliamboswell/weaver` namespace |

## Starting one

```bash
roc-syntax-mcp plugin init plugins/roc-ray \
  --repo=lukewilliamboswell/roc-ray \
  --package=@you/roc-ray \
  --version=0.10.0-rc3

roc-syntax-mcp plugin init plugins/weaver --kind=package \
  --repo=lukewilliamboswell/weaver \
  --package=@you/weaver \
  --version=0.9.0
```

`--repo` is the repository that an app header pins, because detection reads
that repository. `--package` is the npm id. The npm id is different when the
person who curates a corpus is not the person who publishes the platform.
Without `--package`, `init` takes the npm scope from the repository owner, and
the curator would publish under the npm name of somebody else.

`--kind=package` writes a package skeleton. The manifest has the same shape as
for a platform: one corpus that names one release. The header of the release
makes it a package, and a package ships no scaffold. A package is not a scope.
It is the provider for each app whose header pins that release. In such an
app, searches include its items with the builtins, and
`search_roc_syntax("<name>")` returns its page. The apps in a package
skeleton pin a platform for I/O. `--platform=` names that platform, and the default is
the basic-cli that this server bundles.

`init` writes the manifest, the package.json and the skeleton corpus, but no
release source. Put the tarball URL of the release in the manifest and run
`roc-syntax-mcp plugin index <dir>`. This command reads the release from the
Roc package cache, fetches it with `roc deps` when necessary, and writes
`index.json`. Run it again each time that the release changes. `validate`
fails until `index.json` is current. `init` also writes `"license": "MIT"` as a
placeholder. A plugin vendors source from somebody else, so the package's
license is the license of the corpus. For that reason, `roc-ray/` ships
upstream's `LICENSE` and declares `UPL-1.0`.

`.claude/skills/author-roc-plugin/` has the rest: what to vendor, how to find
the findings worth shipping, and the shape of an overview page.
