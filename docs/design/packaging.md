# Packaging

This page describes how this repository gets to a user, and why its manifest
does not declare it as a monorepo. `docs/design/plugins.md` describes the
plugin contract. This page describes the npm side of the server and of the
plugins.

## Two install paths

| Path | Gets | Entry |
|---|---|---|
| `npm i -g roc-syntax-mcp` | The published tarball: `dist/`, and no `src/` | `dist/index.js` |
| `bun i -g git:...`, `npm i -g git+https://...` | The repository tree, with no `dist/` | `src/index.ts`, types stripped at load |

The second path sets the constraints for the rest of this page. npm 11 and
bun 1.3 both block the install scripts of a package by default. With a
`prepare` script that ran `tsc`, the install had no `dist/`, and the binary
failed on its first import. Bun printed `Blocked 1 postinstall`. npm linked a
temporary clone and deleted it. Neither printed a message that a user would
read as an error.

## Why allowing install scripts does not help

A user can remove the block: `bun i -g --trust`, or
`npm i -g --allow-scripts=roc-syntax-mcp`. It would be fair to ask users for
this flag if it built the package. It does not build the package, because the
installer does not install the devDependencies of a dependency. Thus the
compiler that `prepare` needs is not available.

npm has an exception for git dependencies. It clones the repository, installs
the clone with `--include=dev`, and runs `prepare` in the clone. This exception
works, but not under `-g`. The table below was measured with a package whose
`prepare` reports what it can see, on npm 11.19.0 and bun 1.3.14:

| Install | What `prepare` sees | `prepare: tsc` |
|---|---|---|
| `npm i git+...`, project-scoped, `allowScripts` in package.json | The clone, with `node_modules/.bin/tsc` in it | Builds. `dist/` is there |
| `npm i -g git+...`, `--allow-scripts=` | The clone, with no `node_modules` at all | Exit 127. Nothing is installed, and the global link points into a temp clone npm then deletes |
| `bun add --trust`, project-scoped | The installed package, with no `node_modules`. Only the production dependency is hoisted beside it | Exit 127 |
| `bun i -g --trust` | The same | Exit 127 |

The npm rows differ because the prepare step inherits the configuration of the
outer command. Under `-g`, this configuration includes `--global` and
`--prefix`. Thus the install that must fill the clone installs the clone
globally as a `file:` dependency. `prepare` then runs in a directory that has
no installed packages. bun does not install the devDependencies of a git
dependency in either scope, so a `prepare` that needs a compiler cannot work
with bun.

Users install an MCP server globally. In a global install, neither installer
can build the package, whatever the user allows. A package that needs no build
avoids all of these problems. `npm run build:ts` is available to anyone who
wants a built tree.

These parts let the package start with no build:

| Piece | Does |
|---|---|
| `.ts` in every relative import, with `rewriteRelativeImportExtensions` | One source tree that Node can run and `tsc` can still emit `.js` from |
| `erasableSyntaxOnly` in tsconfig.json | Forbids parameter properties, enums and namespaces. Syntax that a type stripper cannot erase fails the build, not an install |
| `bin/strip-types.js` | Registers a load hook that strips types with Node's own stripper, because Node refuses to do it itself under `node_modules` |
| `bin/roc-syntax-mcp.js` | Runs `dist/` if a build made it. If not, it runs `src/` through the hook |

The source path needs Node 22.15 or newer, the first version that has both
`module.registerHooks` and `module.stripTypeScriptTypes`. On an older Node, the
hook throws an error that gives the version and a one-line fix, not a stack
trace about an unknown file extension.

Bun runs the same source without the hook. Bun cannot import the hook, because
its `node:module` exports neither function. `bin/roc-syntax-mcp.js` skips the
hook when `process.versions.bun` is set, and Bun's own loader reads the `.ts`
files. This behavior was verified in the Bun source back to Bun 1.0.36. The
installed command starts under Node with both installers, because both link
the bin, and the shebang reads `#!/usr/bin/env node`. `bunx roc-syntax-mcp`
starts the Bun path. A machine with no Node must use it.

The shebang is `node`, not a `#!/bin/sh` polyglot that runs the first runtime
that it finds. npm's `cmd-shim` takes the interpreter for its Windows `.cmd`
and `.ps1` shims from that line. Thus a `sh` shebang would need an `sh` on each
Windows machine, and most Windows users likely do not have one. That cost is
too high to fix a machine that has Bun and no Node.

Read this before you extend the hook. Node does not strip types under
`node_modules` on purpose, "to discourage package authors from publishing
packages written in TypeScript" (`nodejs.org/api/typescript.html`).
`nodejs/node#57215` is the open request to make this behavior opt-in. This
rule is a policy, and the hook opts out of it. A package that publishes a built
`dist/` never uses the hook, and the registry tarball publishes `dist/`.

## The oldest package manager that works

The minimum versions in the README were measured on 2026-10-07. Each install
went into an empty global prefix, from `npm pack` for the tarball and from a
git server on localhost for the git path. An install passed if the reply to an
`initialize` request was the first line on stdout. Node 20.11.1, 22.15.0 and
26.7.0 gave the same results, except that the git path needs Node 22.15.

| Manager | Last fail | First pass | Why the older one fails |
|---|---|---|---|
| pnpm, tarball | 6.35.1 | 7.0.0 | pnpm 6 cannot reach the registry on Node 20 and newer (`ERR_INVALID_THIS`) |
| pnpm, git | 8.7.5 | 8.7.6 | It runs `prepublishOnly` on a git package, and `tsc` is not installed |
| Yarn 1, tarball and git | 1.6.0 | 1.7.0 | It stops after "Resolving packages" and installs nothing |
| Yarn 2 and newer, `dlx -q` | 3.2.1 | 3.2.2 | The PnP loader breaks Node's hook chain (`ERR_LOADER_CHAIN_INCOMPLETE`). 2.4.2 and 3.0.0 fail with `ERR_REQUIRE_ASYNC_MODULE` on the bin's top-level `await` |

`pnpm dlx` passes from 7.0.0, and its progress goes to stderr. `yarn dlx`
without `-q` writes its progress to stdout, which a client reads as a corrupt
reply. Yarn 2 and newer have no global install, so `dlx` is their only path.

## What the root manifest must not declare

From `pacote/lib/git.js`, which is what npm runs for a git dependency:

```js
if (!mani.workspaces && (!scripts || !(scripts.postinstall ||
    scripts.build || scripts.preinstall || scripts.install ||
    scripts.prepack || scripts.prepare))) { return }
```

In the early return, npm installs the dependency by copying the tree. In all
other cases, npm first runs `npm install` inside its clone. When install
scripts are blocked, that branch ends with a link to a directory that npm then
removes.

| Declared | Consequence |
|---|---|
| `workspaces` | npm's git install breaks. bun's does not |
| A script named `build`, `prepack`, `prepare`, `install`, `preinstall`, `postinstall` | The same |
| `prepublishOnly` | Nothing. It runs on `npm publish` and on nothing else, which is where the build belongs |

For this reason, the build script is `build:ts`, and the manifest has no
`workspaces` field. `src/package.test.ts` quotes the rule and asserts both
facts against that list. Thus a rename that causes the breakage again fails a
test, not the install of a user.

## The children

`plugins/*` are npm packages, each published with its own version. The
repository is a monorepo in its layout and tooling, but its manifest does not
declare one:

| Property | How |
|---|---|
| Absent from the server's published tarball | The root `files` list does not name `plugins/`. A git install copies the whole repository, and loads none of them: a plugin is served when it is declared, never because it is present |
| Never built by installing the root | Nothing links them, and no plugin has a build: a plugin runs no JavaScript |
| Published independently | `cd plugins/<name> && npm publish` |
| Checked against the contract | `plugin validate` reads their package.json, and `src/package.test.ts` checks every child |

Without a `workspaces` field, npm does not hoist dependencies across the
children. A package of Roc source and prose that declares no dependencies does
not need hoisting.

## What ships

`files` is a whitelist, so a new top-level directory is not in the tarball
until someone adds it to `files`. The server reads `corpus/` at runtime, and
`plugin validate` starts two scripts that load the server's modules through
`scripts/tree.mjs`, so these ship. `docs/`, the tests, `src/testdata/` and the
other scripts do not ship.

One `files` list serves both install paths, because npm packs a git dependency
with the same list. The two need different trees:

| Path | Ships | Why |
|---|---|---|
| Registry tarball | `dist/`. No `src/`, no `tsconfig.json` | A build is there, so nobody runs the source |
| Git install | `src/` and `tsconfig.json` | No build ran, so the source is what runs, and `npm run build:ts` needs the config |

Thus `files` lists the source, and the publish step removes the source. The
publish workflow runs `scripts/registry-files.mjs` before `npm pack`.
`prepublishOnly` runs the same script with `--check`, so an `npm publish` that
skipped that step stops before it ships the source.

`scripts/tree.mjs` selects the tree that a gate script loads:

| Install | Tree | Loader |
|---|---|---|
| A checkout | `src/` | tsx, a dev dependency |
| From git | `src/` | `bin/strip-types.js` |
| From npm | `dist/` | None |
| Any, under Bun | As above | None. Bun reads `.ts` |

`src/package.test.ts` runs `npm pack --dry-run` and asserts both directions for
both lists. Every file that the server reads at runtime is in the list, and no
test file, no child and no fixture is in it. The registry list must also
contain no source.
