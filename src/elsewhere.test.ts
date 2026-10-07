// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import { elsewhere } from "./elsewhere.ts";

/** Two platforms and two other corpora, the same shape as the shipped scopes. */
const base = {
  from: ["language", "builtin", "basic-webserver", "basic-cli"],
  shown: [] as string[],
  platform: null as string | null,
  isPlatform: (s: string) => s.startsWith("basic-"),
  count: () => 3,
};

test("a scope the answer already read is not somewhere else to look", () => {
  const found = elsewhere({ ...base, reach: "pinned", shown: ["language", "builtin"] });
  assert.deepEqual(found.map((c) => c.scope), ["basic-webserver", "basic-cli"]);
});

// A retry that finds nothing costs a call and teaches the caller to ignore the
// hint.
test("a scope with nothing in it is never offered", () => {
  const counts: Record<string, number> = { builtin: 0, "basic-webserver": 4, "basic-cli": 0 };
  const found = elsewhere({
    ...base,
    reach: "pinned",
    shown: ["language"],
    count: (s) => counts[s] ?? 0,
  });
  assert.deepEqual(found, [{ scope: "basic-webserver", count: 4 }]);
});

// A footer follows this rule because a retry in a platform that the app cannot
// compile against produces code that does not build.
test("a footer never offers a platform this workspace does not pin", () => {
  const found = elsewhere({ ...base, reach: "pinned", platform: "basic-cli", shown: ["builtin"] });
  assert.deepEqual(found.map((c) => c.scope), ["language", "basic-cli"]);
});

// On a total miss the opposite rule applies, because the platform that the
// workspace does not pin is the answer.
test("a miss names the platform this workspace does not pin", () => {
  const found = elsewhere({
    ...base,
    reach: "anywhere",
    platform: "basic-cli",
    shown: ["language", "builtin", "basic-cli"],
  });
  assert.deepEqual(found.map((c) => c.scope), ["basic-webserver"]);
});

// With no platform pinned, the caller can mean any platform, so the result
// includes each one.
test("with no platform pinned, both are offered under either rule", () => {
  for (const reach of ["pinned", "anywhere"] as const) {
    const found = elsewhere({ ...base, reach, shown: ["language", "builtin"] });
    assert.deepEqual(found.map((c) => c.scope), ["basic-webserver", "basic-cli"], reach);
  }
});

// The caller supplies the count, but not the order. The footer and the miss
// note sort and cap the candidates themselves.
test("candidates come back in declaration order, uncapped", () => {
  const found = elsewhere({ ...base, reach: "anywhere", count: (s) => s.length });
  assert.deepEqual(found, [
    { scope: "language", count: 8 },
    { scope: "builtin", count: 7 },
    { scope: "basic-webserver", count: 15 },
    { scope: "basic-cli", count: 9 },
  ]);
});
