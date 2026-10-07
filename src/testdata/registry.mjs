// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// A read-only npm registry for tests. Every `<name>-<version>.tgz` in the
// folder given as the first argument is a published version. The registry reads
// the folder on each request, so a test publishes a version by writing a
// tarball. Each version carries the package.json of its tarball, so npm installs
// its dependencies and links its bin. The script prints its port.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import zlib from "node:zlib";

/** The package.json inside an npm tarball: a gzipped tar of 512-byte blocks. */
function manifestOf(tgz) {
  const tar = zlib.gunzipSync(tgz);
  for (let at = 0; at + 512 <= tar.length; ) {
    const name = tar.toString("utf-8", at, at + 100).replace(/\0.*$/s, "");
    if (!name) break;
    const size = parseInt(tar.toString("utf-8", at + 124, at + 136).replace(/\0.*$/s, "").trim() || "0", 8);
    if (name.split("/").slice(1).join("/") === "package.json") {
      return JSON.parse(tar.toString("utf-8", at + 512, at + 512 + size));
    }
    at += 512 + Math.ceil(size / 512) * 512;
  }
  return {};
}

const dir = process.argv[2];
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url ?? "");
  if (url.endsWith(".tgz")) {
    res.end(fs.readFileSync(path.join(dir, path.basename(url))));
    return;
  }
  const name = url.slice(1);
  const base = name.replace(/^@[^/]+\//, "");
  const versions = {};
  for (const file of fs.readdirSync(dir)) {
    const m = file.match(/^(.+)-(\d+\.\d+\.\d+)\.tgz$/);
    if (!m || m[1] !== base) continue;
    const buf = fs.readFileSync(path.join(dir, file));
    versions[m[2]] = {
      ...manifestOf(buf),
      name,
      version: m[2],
      dist: {
        tarball: `http://127.0.0.1:${server.address().port}/-/${file}`,
        shasum: crypto.createHash("sha1").update(buf).digest("hex"),
        integrity: `sha512-${crypto.createHash("sha512").update(buf).digest("base64")}`,
      },
    };
  }
  const all = Object.keys(versions).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  if (all.length === 0) {
    res.statusCode = 404;
    res.end("{}");
    return;
  }
  res.setHeader("content-type", "application/json");
  res.end(JSON.stringify({ name, "dist-tags": { latest: all.at(-1) }, versions }));
});
server.listen(0, "127.0.0.1", () => process.stdout.write(`${server.address().port}\n`));
