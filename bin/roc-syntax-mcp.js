#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The command-line entry point:
//
// | Arguments   | Action                                                    |
// |-------------|-----------------------------------------------------------|
// | none        | runs the MCP server, which a client starts                |
// | `plugin`    | runs the commands for plugin authors                      |
// | `roc`       | installs or selects the Roc compiler                      |
// | `upgrade`   | updates the server and its plugins                        |
// | `uninstall` | deletes the plugins and compiler, then removes the server |
//
// Only the MCP server speaks JSON-RPC. Only the `index` module starts a server.
// The `server` module builds one and starts nothing, so any command can import
// it.
//
// The bin runs dist/ when a build made it. Otherwise it runs the TypeScript
// source through `strip-types.js`, because an install from the git repository
// runs no build. npm and bun block the install scripts of a package until the
// user passes a flag. With no build step, no user has to pass that flag.
import * as fs from 'node:fs';

const ROOT = new URL('../', import.meta.url);
const built = fs.existsSync(new URL('dist/index.js', ROOT));
// Bun runs TypeScript itself and has no `node:module` load hooks, so the bin
// does not import the stripper under Bun.
if (!built && !process.versions.bun) await import('./strip-types.js');
const entry = (name) => new URL(built ? `dist/${name}.js` : `src/${name}.ts`, ROOT).href;

if (process.argv[2] === 'plugin') {
  const { main } = await import(entry('plugin_cli'));
  process.exit(await main(process.argv.slice(3)));
}
if (process.argv[2] === 'roc') {
  const { main } = await import(entry('roc_bin'));
  process.exit(await main(process.argv.slice(3)));
}
if (process.argv[2] === 'upgrade') {
  if (process.argv.length > 3) {
    console.error('usage: roc-syntax-mcp upgrade\n\nUpdates the server, then every plugin that `plugin add` installed.');
    process.exit(process.argv[3] === '--help' || process.argv[3] === '-h' ? 0 : 2);
  }
  const { upgrade } = await import(entry('plugin_cli'));
  process.exit(upgrade(process.env));
}
if (process.argv[2] === 'uninstall') {
  const rest = process.argv.slice(3);
  if (rest.some((a) => a !== '--yes')) {
    console.error(
      'usage: roc-syntax-mcp uninstall [--yes]\n\n' +
        'Deletes the plugins that `plugin add` installed and the compiler that `roc install` downloaded,\n' +
        'then removes the server with the package manager that installed it. It asks you to confirm\n' +
        'first, and --yes skips that question.'
    );
    process.exit(rest[0] === '--help' || rest[0] === '-h' ? 0 : 2);
  }
  const { uninstall } = await import(entry('plugin_cli'));
  process.exit(await uninstall(rest, process.env));
}
await import(entry('index'));
