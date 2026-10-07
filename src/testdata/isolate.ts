// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// Loaded before every test file. It points ROC_MCP_HOME to a missing folder, so
// the plugins that the developer installed with `plugin add` do not load into
// a server that a test starts.
import * as os from "node:os";
import * as path from "node:path";

export const NO_HOME = path.join(os.tmpdir(), "roc-syntax-mcp-tests-have-no-home");
process.env.ROC_MCP_HOME = NO_HOME;

// The environment for a test that passes its own `env` in place of
// `process.env`. Without ROC_MCP_HOME, `pluginHome` reads the real data folder.
export const BARE_ENV = { ROC_MCP_HOME: NO_HOME };
