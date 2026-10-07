// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// scripts/gate-overrides.json lists the releases that `check:platforms`
// compiles with an upstream fix applied. An entry must go when its release is
// repinned.

import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { cachedReleaseDir } from "./release.ts";

const ROOT = path.join(import.meta.dirname, "..");
const LIST = path.join(ROOT, "scripts", "gate-overrides.json");

type Override = { release: string; patch: string; reason: string; until: string };
const overrides = (): Override[] => (fs.existsSync(LIST) ? JSON.parse(fs.readFileSync(LIST, "utf-8")) : []);

/** Every bundled `.roc` file, which is everything `check:platforms` can compile. */
function rocFiles(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) return rocFiles(p);
    return e.name.endsWith(".roc") ? [p] : [];
  });
}

test("every gate override is used, and says why and until when", () => {
  const sources = [...rocFiles(path.join(ROOT, "corpus")), ...rocFiles(path.join(ROOT, "plugins"))].map((f) =>
    fs.readFileSync(f, "utf-8")
  );
  for (const o of overrides()) {
    // A repin removes the last pin, and with it every reason for the entry.
    assert.ok(
      sources.some((s) => s.includes(`"${o.release}"`)),
      `no bundled file pins ${o.release}. Remove its entry and ${o.patch}`
    );
    assert.ok(fs.existsSync(path.join(ROOT, o.patch)), `${o.patch} does not exist`);
    // The `check:platforms` output names the patch. The `gate-` prefix marks a
    // patch that only the check applies and the served corpus never applies.
    assert.match(path.basename(o.patch), /^gate-/);
    assert.ok(o.reason && o.until, `${o.release} needs a reason and an until`);
  }
});

test("every gate override patch applies to its release", (t) => {
  for (const o of overrides()) {
    const cached = cachedReleaseDir(o.release);
    if (!cached) {
      t.skip(`${o.release} is not in the package cache`);
      continue;
    }
    const copy = fs.mkdtempSync(path.join(os.tmpdir(), "gate-override-"));
    try {
      fs.cpSync(cached, copy, { recursive: true });
      execFileSync("patch", ["-p1", "--forward", "--silent", "-d", copy, "-i", path.join(ROOT, o.patch)]);
    } finally {
      fs.rmSync(copy, { recursive: true, force: true });
    }
  }
});
