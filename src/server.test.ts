// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// A server is built from a config value, not from the process that it runs in.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { InMemoryTransport, LATEST_PROTOCOL_VERSION } from "@modelcontextprotocol/server";
import { createServer, type ServerConfig, serverConfig } from "./server.ts";
import { parserSource, type SignatureSource } from "./project_index.ts";

const ROOT = path.join(import.meta.dirname, "..");
const TSX_LOADER = import.meta.resolve("tsx/esm");
const RAY = path.join(ROOT, "plugins", "roc-ray");
let tmp: string;

before(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roc-server-"));
});
after(() => fs.rmSync(tmp, { recursive: true, force: true }));

// The plugin CLI, the check scripts and an embedder import these modules. A module that read
// `--plugin=` or opened stdio as it loaded would act on a process it does not own.
test("importing the server reads no configuration and starts nothing", () => {
  const r = spawnSync(
    process.execPath,
    [
      "--import",
      TSX_LOADER,
      "--input-type=module",
      "-e",
      'const S = await import("./src/scopes.ts"); await import("./src/server.ts");' +
        "console.log(JSON.stringify({ ray: S.CORE.scopes.includes('roc-ray'), problems: S.CORE.diagnostics.length }));",
      // This string is `process.argv[1]`, so the flags after it go where a server reads them.
      "ignored",
      `--plugin=${RAY}`,
      "--plugin=/no/such/plugin",
    ],
    // stdin stays open, so a server that started would never exit.
    { cwd: ROOT, encoding: "utf-8", timeout: 30_000, stdio: ["pipe", "pipe", "pipe"] }
  );
  assert.equal(r.signal, null, "the import started something that kept the process alive");
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { ray: false, problems: 0 });
  assert.doesNotMatch(r.stderr, /roc-syntax/);
});

/** A server for `argv`, connected in this process, and a way to call its tools. */
async function inProcess(argv: string[], extra: Partial<ServerConfig> = {}) {
  const config = { ...serverConfig(argv, { ...process.env, CLAUDE_PROJECT_DIR: tmp }), ...extra };
  const [client, server] = InMemoryTransport.createLinkedPair();
  const waiting = new Map<number, (m: any) => void>();
  client.onmessage = (m: any) => waiting.get(m.id)?.(m);
  await createServer(config).connect(server);
  await client.start();
  let id = 0;
  const send = (method: string, params: unknown) =>
    new Promise<any>((resolve) => {
      const n = ++id;
      waiting.set(n, resolve);
      void client.send({ jsonrpc: "2.0", id: n, method, params } as never);
    });
  await send("initialize", { protocolVersion: LATEST_PROTOCOL_VERSION, capabilities: {}, clientInfo: { name: "t", version: "1" } });
  await client.send({ jsonrpc: "2.0", method: "notifications/initialized" } as never);
  const call = async (name: string, args: unknown) =>
    (await send("tools/call", { name, arguments: args })).result.content[0].text as string;
  return { config, call, close: () => client.close() };
}

// Two servers in one process, each with the plugins that its own config declared.
// If the module read the plugin set at load, the second server would serve the
// plugins of the first.
test("two servers in one process each serve their own plugins", async () => {
  const withRay = await inProcess([`--plugin=${RAY}`]);
  const plain = await inProcess([]);
  try {
    assert.deepEqual(withRay.config.catalog.diagnostics, []);
    assert.match(await withRay.call("list_roc_index", { kind: "scopes" }), /roc-ray/);
    assert.doesNotMatch(await plain.call("list_roc_index", { kind: "scopes" }), /roc-ray/);
    assert.match(await withRay.call("get_roc_syntax", { scope: "roc-ray" }), /roc-ray/);
  } finally {
    await withRay.close();
    await plain.close();
  }
});

// `F32.floor_to_i64` names no builtin. The substring search must drop the
// module from the query, because it compares the query with bare names.
test("a missed qualified name lists close names in that module", async () => {
  const s = await inProcess([]);
  try {
    const text = await s.call("search_symbols", { query: ["F32.floor_to_i64"] });
    assert.match(text, /^Nothing is named `F32.floor_to_i64`. 1 name contains `floor_to_i64`:/);
    assert.match(text, /Num\.F32\.floor_to_i64_try/);
    assert.doesNotMatch(text, /Num\.F64\./);
  } finally {
    await s.close();
  }
});

// `Text.Builder.size` has the module path `Text.Builder`. A page with only
// the items of `Text` shows the `Builder` type and none of its methods.
test("a module page lists the methods of its nested types, up to a cap", async () => {
  const ray = await inProcess([`--plugin=${RAY}`]);
  const plain = await inProcess([]);
  try {
    const text = await ray.call("get_roc_module", { module: "Text", scope: "roc-ray" });
    assert.match(text, /^## Text\.Builder\n\n5 methods\.\n\n```roc\n[^`]*prepare! : Builder => /m);
    const num = await plain.call("get_roc_module", { module: "Num" });
    assert.match(num, /Nested modules, with the item count of each: [^\n]*`Num\.U64` \(\d+\)/);
    assert.doesNotMatch(num, /^## Num\./m);
  } finally {
    await ray.close();
    await plain.close();
  }
});

// A name and a type: the name filters, and the type ranks. `-> F32` matches
// `ceiling_to_i32_try : F32 -> Try(I32, ..)` as a substring only, and that
// match must not read as an answer.
test("a name and a type search the names, ranked by type", async () => {
  const s = await inProcess([]);
  try {
    const dec = await s.call("search_symbols", { query: ["ceil : -> Dec"] });
    assert.match(dec, /^\*\*Num\.Dec\.ceiling\*\* \(return_type, score 90\)/);
    assert.doesNotMatch(dec, /Num\.Dec\.round/);
    // Both score 90. The whole name `floor` breaks the tie, before the order by name.
    const floor = await s.call("search_symbols", { query: ["floor : -> Dec"] });
    assert.ok(floor.indexOf("**Num.Dec.floor**") < floor.indexOf("**Num.Dec.div_floor_by**"), floor);
    const f32 = await s.call("search_symbols", { query: ["ceil : -> F32"] });
    assert.match(f32, /^No symbol similar to `ceil` matches `-> F32`\. \d+ symbols have a different type\. Closest matches:/);
    assert.doesNotMatch(f32, /substring/);
    // A type that names `F32` is closer than `Num.Dec.ceiling : Dec -> Dec`.
    assert.match(f32, /Closest matches:\n\n\*\*Num\.F32\.ceiling_/);
  } finally {
    await s.close();
  }
});

// A list of partial names shows a prefix match before a match inside the name,
// and one line of docs for each, not the whole docstring.
test("a partial name lists compact entries, prefixes first", async () => {
  const s = await inProcess([]);
  try {
    const text = await s.call("search_symbols", { query: ["ceil"], limit: 100 });
    assert.ok(text.indexOf("**Num.Dec.ceiling**") >= 0, text);
    assert.ok(text.indexOf("**Num.Dec.ceiling**") < text.indexOf("div_ceil_by**"), "a prefix ranks first");
    // The default order puts the shallower `Num.F32.infinity` first.
    const fini = await s.call("search_symbols", { query: ["fini"] });
    assert.ok(fini.indexOf(".finish**") >= 0 && fini.indexOf(".finish**") < fini.indexOf(".infinity**"), fini);
    assert.doesNotMatch(text, /expect /);
    assert.match(await s.call("search_symbols", { query: ["ceil"], limit: 3 }), /Showing 3 of \d+\./);
  } finally {
    await s.close();
  }
});

// One word is a name, and `Try` is a type with its docs. `: Str` is a type query.
test("a one-word query is a name, and a colon makes it a type", async () => {
  const s = await inProcess([]);
  try {
    assert.match(await s.call("search_symbols", { query: ["Try"] }), /`Try` is also a module/);
    assert.match(await s.call("search_symbols", { query: [": Str"] }), /\(return_type, score 80\)/);
  } finally {
    await s.close();
  }
});

const GEO = [
  "Geo := [].{",
  "\t## Scales a point.",
  "\t## By a factor.",
  "\tscale : (F64, F64), F64 -> (F64, F64)",
  "\tscale = |(x, y), k| (x * k, y * k)",
  "",
  "\tPoint : { x : F64, y : F64 }",
  "",
  "\tnorm : Point -> F64",
  "\tnorm = |p| p.x",
  "}",
  "",
].join("\n");

/** A project in the workspace, at `proj/Geo.roc`. */
function geoProject(): string {
  const dir = path.join(tmp, "proj");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "Geo.roc"), GEO);
  return dir;
}

// The project search reads the same grammar as `search_symbols`, and each entry
// says where the declaration is.
test("a project search finds names, types, and both", async () => {
  const root = geoProject();
  const s = await inProcess([]);
  try {
    const exact = await s.call("search_project_symbols", { query: ["Geo.scale"], root });
    assert.match(exact, /^## Geo\.scale at `Geo\.roc:4`\n```roc\nscale : \(F64, F64\), F64 -> \(F64, F64\)\n```\nScales a point\.\nBy a factor\./);
    assert.match(await s.call("search_project_symbols", { query: ["Point"], root }), /^## Geo\.Point at `Geo\.roc:7`\n```roc\nPoint : \{ x : F64, y : F64 \}/);
    assert.match(await s.call("search_project_symbols", { query: ["sca"], root }), /^Nothing is named `sca`\. 1 name contains `sca`:\n\n\*\*Geo\.scale\*\* at `Geo\.roc:4`/);
    assert.match(await s.call("search_project_symbols", { query: ["-> F64"], root }), /^\*\*Geo\.norm\*\* \(return_type, score 90\) at `Geo\.roc:9`/);
    // `norm` writes `Point`, which is `Geo.Point` in this file.
    assert.match(await s.call("search_project_symbols", { query: ["Geo.Point ->"], root }), /^\*\*Geo\.norm\*\* \(exact_args, score 70\)/);
    const both = await s.call("search_project_symbols", { query: ["nor : -> Bool"], root });
    assert.match(both, /^No symbol similar to `nor` matches `-> Bool`\. 1 symbol has a different type\./);
  } finally {
    await s.close();
  }
});

// The workspace is the default root. The bundled indexes never read it, and a
// project miss says when they have the name.
test("a project search reads the workspace, and only it does", async () => {
  geoProject();
  const s = await inProcess([]);
  try {
    assert.match(await s.call("search_project_symbols", { query: ["Geo.norm"] }), /^## Geo\.norm at `proj\/Geo\.roc:9`/);
    assert.doesNotMatch(await s.call("search_symbols", { query: ["Geo.norm"] }), /proj\/Geo|## Geo\.norm/);
    const miss = await s.call("search_project_symbols", { query: ["Str.concat"] });
    assert.match(miss, /^Nothing in \d+ \.roc files? under `[^`]+` is named `Str\.concat`\.\n\n`search_symbols` has 1 match for `Str\.concat` in the bundled indexes\./);
  } finally {
    await s.close();
  }
});

// A module of the project is answered with its file, because the file is the
// whole module. The page of a bundled module with the same name says that the
// project also declares one.
test("get_roc_module and search_symbols send a project module to its file", async () => {
  const dir = path.join(tmp, "own");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "Shape.roc"), "Shape := [].{\n\tarea : F64 -> F64\n\tarea = |r| r * r\n}\n");
  fs.writeFileSync(path.join(dir, "Str.roc"), "Str := [].{\n\tshout = |s| s\n}\n");
  const s = await inProcess([]);
  try {
    const pointer =
      "`Shape` is a module of this project, in `own/Shape.roc`. Read that file, or call `search_project_symbols` with `Shape.` for its signatures.";
    assert.equal(await s.call("get_roc_module", { module: "Shape" }), pointer);
    assert.equal(await s.call("search_symbols", { query: ["Shape"] }), pointer);
    assert.equal(await s.call("search_symbols", { query: ["Shape."] }), pointer);
    assert.match(
      await s.call("search_symbols", { query: ["Shape.area"] }),
      /^Nothing matched "Shape\.area"\..*\n\n`search_project_symbols` has 1 match for `Shape\.area` in this project\./
    );
    assert.doesNotMatch(await s.call("search_symbols", { query: ["zzqq"] }), /search_project_symbols/);
    const str = await s.call("get_roc_module", { module: "Str" });
    assert.match(str, /^# Str\n/);
    assert.match(str, /The page above is the bundled `Str`\. `Str` is a module of this project, in `own\/Str\.roc`\./);
  } finally {
    await s.close();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

// A name search finds a function with no annotation, and a type search skips
// it, because its lambda head is not a type. Without the skip, `: a` matches
// the text of `|a|`.
test("a project search finds an unannotated value by name only", async () => {
  const root = fs.mkdtempSync(path.join(tmp, "plain-"));
  fs.writeFileSync(path.join(root, "Geo.roc"), "Geo := [].{\n\thelper = |a| a\n}\n");
  const s = await inProcess([]);
  try {
    assert.equal(await s.call("search_project_symbols", { query: ["helper"], root }), "## Geo.helper at `Geo.roc:2`\n```roc\nhelper = |a|\n```");
    assert.match(await s.call("search_project_symbols", { query: [": a"], root }), /^No matches for `a`/);
  } finally {
    await s.close();
  }
});

// The reply marks a type that a compiler inferred, because the author did not write that type.
test("a project search marks an inferred type", async () => {
  const root = geoProject();
  const inferred: SignatureSource = {
    name: "fake",
    index: async () => [
      { kind: "value", name: "pair_up", modulePath: "Geo", fullName: "Geo.pair_up", signature: "a, b -> (a, b)", docs: "", file: "Geo.roc", line: 12, origin: "inferred" },
    ],
  };
  const s = await inProcess([], { projectSources: [parserSource, inferred] });
  try {
    assert.match(await s.call("search_project_symbols", { query: ["a, b -> (a, b)"], root }), /^\*\*Geo\.pair_up\*\* \(exact, inferred, score 100\) at `Geo\.roc:12`/);
    assert.match(await s.call("search_project_symbols", { query: ["pair_up"], root }), /^## Geo\.pair_up \(inferred\) at/);
  } finally {
    await s.close();
  }
});

// Several queries answer in one call, each in its own section, in the order sent.
// A list then shows 5 entries, so 8 queries cannot return 80.
test("a list of queries answers each one under its own heading", async () => {
  const s = await inProcess([]);
  try {
    const text = await s.call("search_symbols", { query: ["Str.concat", "-> Bool", "foo-bar : Str"] });
    const heads = [...text.matchAll(/^# `([^`]+)`$/gm)].map((m) => m[1]);
    assert.deepEqual(heads, ["Str.concat", "-> Bool", "foo-bar : Str"]);
    const bools = text.slice(text.indexOf("# `-> Bool`"), text.indexOf("# `foo-bar : Str`"));
    assert.equal(bools.match(/\(return_type, score 90\)/g)?.length, 5);
    // An invalid query gets its own error, and the others still answer.
    assert.match(text, /^## Str\.concat$/m);
    assert.match(text, /`foo-bar` is not a name\./);
    const wide = await s.call("search_symbols", { query: ["-> Bool", "-> Str"], limit: 7 });
    assert.equal(wide.match(/\(return_type, score 90\)/g)?.length, 14);
    // One query keeps the reply without a heading.
    assert.doesNotMatch(await s.call("search_symbols", { query: ["Str.concat"] }), /^# /m);
    // A lone string is one query.
    assert.match(await s.call("search_symbols", { query: "Str.concat" }), /^## Str\.concat$/m);
  } finally {
    await s.close();
  }
});

// A note about the index, as opposed to one query, prints once after all queries.
test("a project batch prints the index notes once", async () => {
  const root = geoProject();
  const broken: SignatureSource = { name: "lsp", index: async () => { throw new Error("no roc on PATH"); } };
  const s = await inProcess([], { projectSources: [parserSource, broken] });
  try {
    const text = await s.call("search_project_symbols", { query: ["Geo.scale", "-> F64"], root });
    assert.equal(text.match(/Not indexed: lsp: no roc on PATH/g)?.length, 1);
    assert.match(text, /\n\nNot indexed: lsp: no roc on PATH$/);
    assert.match(text, /^# `Geo\.scale`\n\n## Geo\.scale at/);
  } finally {
    await s.close();
  }
});

// Each word must occur in the name, and a module joins the first word with a dot.
test("words find names that contain all of them", async () => {
  const s = await inProcess([]);
  try {
    const text = await s.call("search_symbols", { query: ["F32.ceiling try"], limit: 50 });
    assert.match(text, /^\d+ names contain `ceiling` and `try` in `F32`:/);
    const names = [...text.matchAll(/^\*\*([^*]+)\*\*/gm)].map((m) => m[1]);
    assert.ok(names.length > 0 && names.every((n) => n.startsWith("Num.F32.") && n.includes("ceiling") && n.includes("try")), names.join(" "));
    assert.match(await s.call("search_symbols", { query: ["zzz qqq"] }), /^No name contains `zzz` and `qqq`\./);
  } finally {
    await s.close();
  }
});

// A type's name has a type reading too. A count of it says if that search is worth a call.
test("an exact type counts the functions that take it and return it", async () => {
  const s = await inProcess([]);
  try {
    assert.match(
      await s.call("search_symbols", { query: ["Dict"] }),
      /\n\n\d+ functions take a `Dict` \(`Dict\(k, v\) ->`\)\. \d+ return one \(`-> Dict\(k, v\)`\)\./
    );
    assert.doesNotMatch(await s.call("search_symbols", { query: ["Str.concat"] }), /functions? take/);
  } finally {
    await s.close();
  }
});

// `Str.Utf8Problem.is_eq` writes `Utf8Problem` and `Str.from_utf8` writes
// `Str.Utf8Problem`. Each query form finds both, as roc-ray's `Frame` and `Draw.Frame`.
test("a type query reads a type that its own module writes without the module", async () => {
  const s = await inProcess([]);
  try {
    assert.match(await s.call("search_symbols", { query: ["Str.Utf8Problem ->"] }), /^\*\*Str\.Utf8Problem\.is_eq\*\* \(args_prefix, score 50\)/);
    const from = "-> Try(Str, [BadUtf8({ problem : Utf8Problem, index : U64 })])";
    assert.match(await s.call("search_symbols", { query: [from] }), /^\*\*Str\.from_utf8\*\* \(return_type, score 90\)/);
  } finally {
    await s.close();
  }
});

// The queries an agent wrote on roc-ray, and the shape each reply teaches.
test("a miss names the query shape that answers it", async () => {
  const s = await inProcess([`--plugin=${RAY}`]);
  try {
    const call = (q: string) => s.call("search_symbols", { query: [q], scope: "roc-ray" });
    assert.equal(await call("Keys"), '`Keys` is a module. Call `get_roc_module("Keys")` for its page.');
    assert.match(await call("Frame.text!"), /^`Frame` is a type in `Draw`\. Its functions are in their module, so search `text!`, or `Frame ->`/);
    const tags = await call("Space");
    assert.match(tags, /^No symbol is named `Space`\. Tags that contain it: .*`KeySpace` in `Keys\.Key`/);
    assert.doesNotMatch(tags, /Host\./, "a host tag is not one an app writes");
    assert.match(await call("Frame"), /\n\n\d+ functions take a `Frame` \(`Frame ->`\)\./);
  } finally {
    await s.close();
  }
});

test("a project search reads words, modules and the shape of a miss", async () => {
  const root = geoProject();
  const s = await inProcess([]);
  try {
    const call = (q: string) => s.call("search_project_symbols", { query: [q], root });
    assert.match(await call("Geo.sc ale"), /^1 name contains `sc` and `ale` in `Geo`:\n\n\*\*Geo\.scale\*\* at/);
    assert.match(await call("Geo.zz qq"), /^No name in .* contains `zz` and `qq`\./);
    assert.match(await call("Geo.norm"), /^## Geo\.norm at/);
    assert.equal(await call("Geo"), "`Geo` is a module. `Geo.` lists its 3 symbols.");
    // A query that ends in `.` asks for the contents of the module, so it is not a miss.
    assert.match(await call("Geo."), /^3 symbols are in `Geo`:\n\n/);
    assert.match(await call("Point"), /\n\n1 function takes a `Point` \(`Point ->`\)\.$/);
    assert.match(await call("Point.length"), /^`Point` is a type in `Geo`\. Its functions are in their module, so search `length`, or `Point ->`/);
  } finally {
    await s.close();
  }
});
