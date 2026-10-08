# Roc Syntax MCP Server

An [MCP](https://modelcontextprotocol.io/) server that helps you write Roc, both
applications on a platform and standalone scripts. The server teaches your
coding agent the language and its idioms. It lets the agent check and format
the code that it wrote, and it finds functions by type signature, as Hoogle does.

The server bundles the language reference, the signatures of all builtin
methods, usage topics, and the basic-cli and basic-webserver platforms.
Third-party plugins can add more platforms and packages.

## Install

Requires Node 20.11 or newer, or Bun 1.1 or newer.

```bash
npm i -g roc-syntax-mcp
```

To upgrade the server and every plugin, run `roc-syntax-mcp upgrade`, then
restart your AI harness. For pnpm, Yarn, Bun, or the latest unreleased commit,
see [Running with other package managers](#running-with-other-package-managers).
To run it with no install, see [Running without installing](#running-without-installing).
For plugins, see [Registering third party plugins](#registering-third-party-plugins).
To remove the server, see [Uninstalling](#uninstalling).

### Connect to your AI harness

The server speaks MCP over stdio.

| Client | Add the server |
|---|---|
| Claude Code | `claude mcp add --scope user roc-syntax -- roc-syntax-mcp` |
| Codex CLI | `codex mcp add roc-syntax -- roc-syntax-mcp` |
| Gemini CLI | `gemini mcp add --scope user roc-syntax roc-syntax-mcp` |
| VS Code | `code --add-mcp '{"name":"roc-syntax","command":"roc-syntax-mcp"}'` |
| Cursor | The JSON below, in `~/.cursor/mcp.json`, or in `.cursor/mcp.json` for one project |
| Windsurf | The JSON below, in `~/.codeium/windsurf/mcp_config.json` |
| Claude Desktop | The JSON below, in `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `~/.config/Claude/claude_desktop_config.json` (Linux) |
| Zed | `"context_servers": { "roc-syntax": { "command": "roc-syntax-mcp", "args": [] } }` in its `settings.json` |

```json
{
  "mcpServers": {
    "roc-syntax": {
      "command": "roc-syntax-mcp"
    }
  }
}
```

For Claude Code, `--scope user` makes the server available in every project.
Use `--scope project` to store the entry in `.mcp.json` and commit it for your
team.

To check the connection, ask the agent to call `roc_overview`. The reply
should contain the language and builtin pages, not an error.

### How the server finds your project

The server reads the `app [...]` header in your project to know the platform.
It finds the project in this order:

| Order | Source | Set by |
|---|---|---|
| 1 | `--workspace=<dir>` | You, in the client config. Cursor and VS Code replace `${workspaceFolder}` with the open folder |
| 2 | The MCP roots the client sends | Clients that support roots, such as Cursor |
| 3 | The `CLAUDE_PROJECT_DIR` environment variable | Claude Code |
| 4 | The directory the client starts the server in | Clients that start it in the folder you started them in |

If `list_roc_index` with `kind: "scopes"` says "No platform detected" in a
project that has an app header, the client started the server somewhere else.
Add `--workspace=` with your project's path, or with `${workspaceFolder}` where
the client supports it:

```json
{
  "mcpServers": {
    "roc-syntax": {
      "command": "roc-syntax-mcp",
      "args": ["--workspace=${workspaceFolder}"]
    }
  }
}
```

If the `--workspace=` value is not a folder, the server ignores it and writes
a line to the client's MCP log.

### Running with other package managers

| Package manager | Minimum version | Command |
|---|---|---|
| npm | The one that comes with Node 20.11 | `npm install -g roc-syntax-mcp` |
| pnpm | 7.0 | `pnpm add -g roc-syntax-mcp` |
| Yarn 1 | 1.7 | `yarn global add roc-syntax-mcp` |
| Yarn 2 and newer | 3.2.2 | None. Run `yarn dlx -q roc-syntax-mcp` in place of `roc-syntax-mcp` |
| Bun | 1.1 | None. Run `bunx roc-syntax-mcp` in place of `roc-syntax-mcp` |

pnpm installs a global command only after you run `pnpm setup` one time. Yarn 2
and newer have no global install. Keep the `-q` in the `yarn dlx` command.
Without it, Yarn writes its progress to stdout, and your client cannot read the
server's replies.

When the command is more than one word, give your client the first word as the
command and the rest as arguments. For Bun, in Claude Code:

```bash
claude mcp add --scope user roc-syntax -- bunx roc-syntax-mcp
```

To run the latest unreleased commit, install from the git repository. This
install needs Node 22.15 or newer, because the server then runs its TypeScript
source with no build step:

```bash
npm install -g github:Karakatiza666/roc-syntax-mcp
```

pnpm needs 8.7.6 or newer for this install. Older releases run the
`prepublishOnly` script of a git package, and that script needs TypeScript,
which is not installed. Yarn 1 installs it with
`yarn global add github:Karakatiza666/roc-syntax-mcp`.

### Running without installing

Your client can run the server with `npx`, with no install:

```json
{
  "mcpServers": {
    "roc-syntax": {
      "command": "npx",
      "args": ["-y", "roc-syntax-mcp@latest"]
    }
  }
}
```

In Claude Code:

```bash
claude mcp add --scope user roc-syntax -- npx -y roc-syntax-mcp@latest
```

`npx` asks npm for the newest release at each start. You get updates with no
`upgrade` command, but the server starts more slowly and needs the network. Run
the other commands in this README the same way, for example
`npx -y roc-syntax-mcp@latest plugin add @roc-syntax/roc-ray`.

### Uninstalling

```bash
roc-syntax-mcp uninstall
```

The command lists what it removes, and asks you to confirm. `--yes` skips the
question. Then the command does these steps:

1. It deletes the plugins that `plugin add` installed.
2. It deletes the nightlies that `roc install` downloaded, and the record of the
   compiler that the server runs. A compiler that you chose with `roc use`
   stays.
3. It removes the server with the package manager that installed it.

A package manager cannot do steps 1 and 2, because npm, pnpm, Yarn and Bun run
no script when they remove a package. Thus `npm uninstall -g roc-syntax-mcp`
alone leaves the plugins and the compiler in the server's data folder.
`plugin doctor` shows the path of that folder.

| Install | Step 3 |
|---|---|
| A global install by npm, pnpm, Yarn 1 or Bun | Removes the server |
| `npx`, `bunx`, `pnpm dlx` or `yarn dlx` | Removes nothing, because the runner keeps its copy in its own cache. Run the command as `npx -y roc-syntax-mcp@latest uninstall` |
| A git checkout | Removes nothing. Delete the folder of the checkout |

Your AI harness keeps its entry for the server. In Claude Code, run
`claude mcp remove roc-syntax`.

## Features

### Tools

| Tool | What it does |
|------|--------------|
| `roc_overview` | Call this tool first. It returns the whole language and its builtins as two compact pages, which answer most questions with no second call. The server also points to this tool in the MCP `instructions` that it sends when the client connects |
| `list_roc_index` | Every index, selected by `kind`: `scopes`, `topics`, `builtin_modules`, `examples`, `langref` |
| `search` | Ranked free-text search across topics, signatures, the langref and worked programs. Use it when you do not know which of them has the answer |
| `get_roc_syntax` | The full `all_roc_syntax.roc` reference, or one construct via `topic` |
| `search_roc_syntax` | One focused topic example, by name or keyword, or one worked program by its platform or package and file name, such as `basic-cli/hello` |
| `lookup_builtin` | One builtin by bare (`concat`) or qualified (`Str.concat`) name: signature and docstring |
| `get_builtin_module` | Every method of a module (`Str`, `List`, `U64`, ...) as a signature list, with one-line hints above the builtins whose name and type mislead. `detail: "full"` adds upstream docstrings |
| `search_builtin_signatures` | Hoogle-style structural search. `List x, (x -> y) -> List y` finds `List.map`. Put `->` before a type to search by return type |
| `search_project_signatures` | The same structural search over the `.roc` files in your own project. With this tool, an agent can find the API of a platform that this server does not bundle |
| `get_roc_langref` | Upstream's own prose, as a page or one section of a page. Where it overlaps a curated topic, use the langref |
| `roc_check` | Runs `roc check` over a code string or a path. It wraps code that has no header in a verified app for the platform in scope, and it reports line numbers in your own source |
| `roc_fmt` | Runs `roc fmt` the same way, and returns the canonical formatting. A path is read, never written |

`roc_check` and `roc_fmt` need the Roc compiler, a 2026 nightly. See
[The Roc compiler](#the-roc-compiler). Every other tool reads bundled files and
works offline. The only exception is the first call in a workspace, which can
download a release that the app header pins. All tools are read-only, so a
client that prompts for approval does not prompt for these tools.

### The Roc compiler

The server looks for the compiler again on every call, in this order:

| Order | Source |
|---|---|
| 1 | `--roc=<path>` on the command line your client starts the server with |
| 2 | The `ROC` environment variable |
| 3 | The compiler that `roc-syntax-mcp roc install` or `roc-syntax-mcp roc use` recorded |
| 4 | `roc` on the `PATH` the server started with |

| Command | Does |
|---|---|
| `roc-syntax-mcp roc` | Shows which compiler the server runs, where that choice came from, and the nightly the server was checked against |
| `roc-syntax-mcp roc install [nightly]` | Downloads a nightly from `roc-lang/nightlies` into the server's own folder, checks its sha256 against the release, and records it. Defaults to the nightly the server was checked against. About 70 MB |
| `roc-syntax-mcp roc use <path>` | Records a compiler you already have |

A running server uses the compiler that these commands record from its next
call, with no restart. Thus an agent can install the compiler in the same
session. When no compiler runs, `roc_check` replies with the exact command to
run.

### Topics

Topics are worked examples. Each topic shows one construct or one task, not a
whole program. `list_roc_index(kind: "topics")` prints them with descriptions.
The agent gets a topic through `search_roc_syntax` or `search`.

| Group | Topics |
|---|---|
| Language | `idioms`, `iterators`, `ranges`, `record_fields`, `derived_methods`, `json`, `hashing`, `operators`, `pattern_matching`, `list_patterns`, `tag_unions`, `try_operator`, `strings`, `effects`, `loops`, `conditionals`, `tuples`, `records`, `types`, `numbers`, `opaque`, `nominal`, `functions`, `static_dispatch`, `imports`, `testing`, `compiler`, `app_header`, `dbg_crash`, `platforms`, `builder_pattern`, `scripting`, `error_design` |
| basic-webserver | `webserver_handler`, `webserver_sqlite`, `webserver_sse`, `webserver_html`, `webserver_forms`, `webserver_static` |
| basic-cli | `cli_app`, `cli_files`, `cli_command`, `cli_http`, `cli_sqlite`, `cli_terminal`, `cli_net` |
| roc-parser | `parser_combinators`, `parser_csv`, `parser_yaml`, `parser_xml`, `parser_markdown`, `parser_http` |
| roc-random | `random_generators` |

The platform and package topics are complete apps. Each one passes
`roc check` against the pinned release.

### Resources

Clients that support MCP resources can attach these without a tool call:

| URI | What it is |
|-----|------------|
| `roc-syntax://overview` | Both overview pages in one read. Attach this resource first |
| `roc-syntax://reference` | The full `all_roc_syntax.roc` reference |
| `roc-syntax://builtin` | Index of the builtin modules and their method counts |
| `roc-syntax://topic/{name}` | One topic, with tab-completion of `{name}` |
| `roc-syntax://langref/{name}` | One langref page, with tab-completion of `{name}` |

### Choosing the platform

A Roc app pins exactly one platform, so the server uses the data of at most
one platform at a time.

| Scope | What it holds |
|-------|---------------|
| `language` | The language itself: syntax, types, modules, operators, and the upstream language reference. Always available |
| `builtin` | The standard library. Every builtin module, in scope with no import. Always available |
| `basic-webserver` | Platform: HTTP server, SQLite, files, commands, SSE, plus the `roc-lang/http` types it re-exports |
| `basic-cli` | Platform: stdio, files and paths, commands, HTTP client, SQLite, TCP, TTY, env, locale, random, time, plus the same `roc-lang/http` types |

In an existing project, the server finds the platform in the `app [...]`
header of your `.roc` files. A new project has no header yet, so the server
lists the platforms that it can serve, and the AI agent helps you select one.
To skip this question, name the platform on the command line that your client
starts the server with:

```bash
roc-syntax-mcp --platform=basic-cli
```

To do this for one project only, put the flag in the project's own client
config, such as the `.mcp.json` that `claude mcp add --scope project` writes.

The AI agent can pass an explicit `scope` argument on a tool call to look up
data for a specific platform.

### Automatic indexing of packages

The server documents the releases in the table below.
`list_roc_index(kind: "scopes")` gives the release of each platform and
package. The `UPSTREAM` file beside each corpus records its source, and for the
language, the commit.

| Content | Kind | Contents |
|---|---|---|
| The language and builtins | Language | Syntax, the language reference, every builtin module |
| `basic-webserver` | Platform | HTTP server, SQLite, files, commands, SSE |
| `basic-cli` | Platform | stdio, files and paths, commands, HTTP client, SQLite, TCP, TTY |
| `http` | Package | The HTTP types both platforms re-export |
| `roc-parser` | Package | Parser combinators, and parsers for CSV, YAML, XML, Markdown and HTTP/1.1 messages that decode into your own types |
| `roc-random` | Package | Pseudorandom values from a seed |

The packages work on any platform. `search_roc_syntax("roc-parser")` returns a
package's overview page.

Signature search covers every package that your app header pins, including
packages that this server does not document. You do not configure anything.
The server reads your app header and indexes each release that it pins. A
search finds the functions of a pinned package together with the builtins.

| Your header pins | Signatures come from |
|---|---|
| A release in the table above | The index that ships with the server |
| Any other release, in the compiler's package cache | That release, read from `~/.cache/roc/packages/<hash>/` |
| Any other release, not in the cache, a compiler the server can run | That release. The server runs `roc deps` one time to download it, and `roc deps` checks it against the hash in its URL. The first answer waits up to 60 seconds for the download. Until the download is done, later answers come from the documented release, with a note |
| Any other release, not in the cache, no `roc` | For a platform or package in the table, its documented release, with a note that the two differ. For any other package, nothing, with a note that says so |

The work is cached at two levels:

| Cache | Holds | Kept until |
|---|---|---|
| The compiler's package cache | The downloaded release | You delete it. Thus `roc deps` runs only one time for each release |
| The server's memory | The parsed index | The server stops, or your app header changes |

If the header does not pin a package from the table, a lookup does not return
the functions of that package as results. The answer tells which package has
the function, shows up to three matching signatures, and gives the line to add
to your app header.

The server serves the overview, topics and examples for any release that you
pin, even across a major version. They were written for the documented release,
and most of what they teach stays true. Only the signatures follow your pin.

Before a project has an app header, name the platform in `scope`. The
overview of that platform shows an app header to start from. After you write
the header, the server finds it within seconds, so later calls need no `scope`.

The server makes no network connection itself. Set `ROC_PACKAGE_CACHE` when your
compiler keeps packages somewhere else.

### Registering third party plugins

Add a plugin, then restart your AI harness:

```bash
roc-syntax-mcp plugin add @roc-syntax/roc-ray
```

| Command | Does |
|---|---|
| `plugin add <package>...` | Installs from npm, or from a path or tarball, and serves the plugin in every workspace. Refuses and undoes the install of a package that the server would not load, or of one that takes a name from an installed plugin. If `add` refuses a new release, the old release stays installed |
| `plugin update [name...]` | Installs the newest release of every plugin that `add` installed, or of the named ones. Each plugin updates separately, so a refused release does not stop the update of other plugins. A plugin linked to a folder always serves the contents of the folder |
| `plugin remove <name>...` | Uninstalls a plugin that `add` installed. Takes the package name, or the path you added it from |
| `plugin list` | Shows what `add` installed, its version, the release each corpus documents, and the folder it is in. Fails when an installed package is missing, for example a path plugin whose folder you deleted |
| `plugin doctor` | Shows the set a server started here would load, and why it skipped anything. It also shows the data folder that holds the plugins and the compiler |

A plugin is an npm package that holds only text: Roc source, docs and JSON.
No code in a plugin runs, and `add` runs no install scripts. `add` installs the
plugin into the server's own folder, which `plugin list` shows. The server then
serves the plugin in every workspace.

`roc-syntax-mcp upgrade` updates the server, then runs `plugin update` in the
new server, because the new server decides which plugins it serves. The command
updates a global install made by npm, pnpm, Yarn 1 or Bun. It updates an
install from the git repository from the repository again. For `npx`, `bunx`,
`pnpm dlx`, `yarn dlx` or a git checkout, it tells you what to run, and it
updates no plugin. The server never updates itself or a plugin when it starts.

`add` runs npm, or Bun when the server runs under Bun, so your `.npmrc`
registry and login settings apply. `add` works for every type of server
install, including `npx`, `bunx` and `yarn dlx`.

You can also name a plugin in two other places:

- On the command line that your client starts the server with, as
  `roc-syntax-mcp --plugin=@roc-syntax/roc-ray`.
- In `ROC_MCP_PLUGINS`, as a comma-separated or colon-separated list.

The value is a path to a plugin folder, or the name of a package. The package
must be one that `plugin add` installed, or one that your package manager
installed globally beside the server. npm, Yarn 1, Bun, and pnpm up to 10 can
do this. pnpm 11 and newer keep each global package apart from the others, so
use `plugin add` with them. To serve a plugin in one project only, put the flag
in the project's own client config, such as `.mcp.json`. The server reads all
of these values at startup, so restart it after a change.

If the server cannot find or load a plugin, it skips that plugin and serves
the rest. The server writes the reason to its log, and the first `roc_overview`
answer gives the reason to the agent.

## Plugins

A plugin can document a platform or package that this server does not bundle.
The same tools answer for a plugin, in the same shape as for a bundled platform.

This repository maintains the plugins below. Each one shows a different type of
plugin:

| Plugin | Kind | What it shows |
|---|---|---|
| `@roc-syntax/roc-ray` | Platform | RocRay, for games, graphics and sound. A platform plugin brings its own app scaffold, so `roc_check` wraps a bare snippet in a RocRay app. The plugin also pins its own compiler nightly, older than the server's, because the release requires that nightly |
| `@roc-syntax/weaver` | Package | Weaver, a command-line argument parser. A package plugin has no scaffold. In any app that pins the package, on any platform, its functions are searched with the builtins. Upstream states no license yet, so the plugin's `LICENSE` tells which files are upstream's |
| `@roc-syntax/joy` | Platform and package | Joy, for browser apps in WebAssembly, and joy-html, the package that Joy views are written in. One plugin holds both. The server refuses the plugin unless its joy-html is the release that the Joy platform pins. `render` returns joy-html's `Html` type, and the `Html` of another release is a different type |

To write your own plugin, read [`plugins/README.md`](plugins/README.md) and
[`docs/design/plugins.md`](docs/design/plugins.md). `roc-syntax-mcp plugin init`
creates the skeleton of a new plugin.

## Commercial use

This project aims to help grow the Roc community. You are welcome to use this
server in a hobby, educational or professional setting.

Commercial use of this server is permitted. Using, modifying and hosting it
carry no obligations. Obligations apply only when you distribute copies to
others in any form (source code, a build, or an image). They then apply only to
the files of this server that you distribute.

[License](#license) says which license applies to which files.

| Use | Obligation |
|---|---|
| Closed-source, commercial or client work | None |
| Shipping what an agent wrote with its help | None. The output is yours |
| Team-wide installs, CI | None |
| Modifying it for internal use | None. Internal use is not distribution |
| Hosting it, modified or not, for your engineers or for anyone | None. Hosting is not distribution |
| Paid consulting, training or workshops that use it, selling support or services around it | None |
| Redistributing it unmodified, in an image or an internal mirror | Keep the copyright notices, and include LICENSE and LICENSES/ |
| Distributing a modified copy, as a fork, a package or an image | The same, and make the source of the server's files you changed available under MPL-2.0. The public repository of a fork is enough |
| Shipping the server inside a larger product with closed-source parts | The same. The closed-source parts stay closed |
| Publishing a plugin under any license, including for your own commercial platform | None. A plugin is a separate package, not a derivative. What it vendors carries its own license |

Not permitted: distributing the server's own files, modified or not, without
their source, or under terms that remove MPL-2.0 from them.

## License

`SPDX-License-Identifier: MPL-2.0 AND UPL-1.0`

The server is licensed under `MPL-2.0`, so that changes to its files stay open
source, and any company can use it. MPL applies file by file. When you
distribute a copy, the server's own files, with your changes to them, stay
under MPL-2.0. The files that you add beside them can have any license,
including a closed-source license.

The bundled Roc corpus is licensed under `UPL-1.0`, the license of the
platforms and packages that it documents. Examples and snippets that an agent
takes from the corpus carry no obligations into your codebase.

| File | Holds |
|---|---|
| [`LICENSE`](LICENSE) | The map of licenses per file path |
| [`REUSE.toml`](REUSE.toml) | The same map, in a machine-readable format |
| [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) | The upstream copyright lines that UPL requires with the copies |

## Troubleshooting

| Symptom | Cause |
|---|---|
| The client lists no tools | The entry is not connected. `claude mcp list`, or check the client's MCP log |
| `roc-syntax-mcp: command not found` in a client that works in your shell | The client did not inherit `PATH`. Use the absolute path from `which roc-syntax-mcp` |
| `env: 'node': No such file or directory` | The machine has Bun and no Node. Start it as `bunx roc-syntax-mcp` |
| `roc_check` reports the compiler is missing | The server found no compiler. Run `roc-syntax-mcp roc install`, or `roc-syntax-mcp roc use <path>`. No restart is needed. Every other tool still works |
| Answers name a platform you are not using | The server found no app header, or the wrong one. Set `scope` explicitly, see [Choosing the platform](#choosing-the-platform) |
| "No platform detected" in a project with an app header | The client started the server outside the project. Add `--workspace=`, see [How the server finds your project](#how-the-server-finds-your-project) |
| A plugin you installed is not served | Your package manager installed it and no flag names it, it is a pnpm 11 global install, or the server started before the change. Use `roc-syntax-mcp plugin add`, or run `roc-syntax-mcp plugin doctor` |
| A warning that your platform version differs from the bundled one | Expected when the server cannot read the release. After `roc` fetches the release that your header pins, the signatures come from that release. The overview and topics stay those of the bundled release. The note appears once per session |
| The first answer in a new workspace takes up to a minute | Your app header pins a release this server does not bundle, and `roc deps` is downloading it. Later answers read it from the compiler's cache |

## Contributing

Pull requests of all sizes are welcome. Give the reason for each pull request.
Do not divide a large, cohesive pull request only to keep each part small.
[`CONTRIBUTING.md`](CONTRIBUTING.md) covers the repository layout, the check
scripts, how to refresh the bundled content from upstream, and how to write a
plugin.

You license your contribution under [UPL-1.0](LICENSES/UPL-1.0.txt). You keep
your copyright, everyone may use the contribution, and the project may ship it
under other terms, such as another open-source license. Each commit carries a
one-line agreement to [`CLA.md`](CLA.md). See the section "Contribution
license" in `CONTRIBUTING.md` for how to add the line.
