// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Runs the TypeScript source of this server, for an install that has no build.
//
// Node can strip types by itself, but it refuses to do so under node_modules,
// where an installed package lives. This load hook uses the same stripper. It
// removes the types from `.ts` files and changes nothing else. Other files load
// unchanged. bin/roc-syntax-mcp.js does not load this file when a build made
// dist/.
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import * as fs from 'node:fs';

if (typeof registerHooks !== 'function' || typeof stripTypeScriptTypes !== 'function') {
  throw new Error(
    `roc-syntax-mcp: running from TypeScript source needs Node 22.15 or newer (this is ${process.version}). ` +
      `Upgrade Node, or build this install once with: npm install && npm run build:ts`
  );
}

// Node warns that the stripper is experimental. Hide that warning, because the
// user did not ask for an experimental feature, and the stderr of the server
// goes to the log of a client. Other warnings pass through.
const warned = process.listeners('warning');
process.removeAllListeners('warning');
process.on('warning', (warning) => {
  if (warning.name === 'ExperimentalWarning' && /stripTypeScriptTypes|type strip/i.test(warning.message)) return;
  if (warned.length > 0) for (const listener of warned) listener(warning);
  else console.error(`${warning.name}: ${warning.message}`);
});

registerHooks({
  load(url, context, next) {
    if (!url.startsWith('file:') || !url.endsWith('.ts')) return next(url, context);
    return {
      format: 'module',
      shortCircuit: true,
      source: stripTypeScriptTypes(fs.readFileSync(new URL(url), 'utf-8'), {
        mode: 'strip',
        sourceURL: url,
      }),
    };
  },
});
