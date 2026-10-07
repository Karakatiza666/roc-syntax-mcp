// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The entry point that an MCP client launches. Reads the process arguments and
// environment once, then serves over stdio. `src/server.ts` decides what to
// serve, and an import of `src/server.ts` does not start a server.

import { StdioServerTransport } from "@modelcontextprotocol/server/stdio";
import { createServer, serverConfig } from "./server.ts";
import { topicsFor } from "./topics.ts";

const config = serverConfig(process.argv.slice(2), process.env);

// stdout carries JSON-RPC, so the operator sees on stderr that the server does
// not serve a declared plugin.
for (const d of config.catalog.diagnostics) {
  console.error(`roc-syntax: ${d.kind} ${d.subject} (${d.source}): ${d.problem}`);
}
for (const c of topicsFor(config.catalog).conflicts) console.error(`roc-syntax: ${c}`);

// A top-level await, so a transport that fails to open makes the process exit
// non-zero. A caught error would log and exit 0, and the client would get no
// response.
await createServer(config).connect(new StdioServerTransport());
console.error("roc-syntax-mcp: serving MCP over stdio");
