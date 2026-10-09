// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { LATEST_PROTOCOL_VERSION } from "@modelcontextprotocol/server";
import * as fs from "node:fs";
import * as path from "node:path";

const ROOT = path.join(import.meta.dirname, "..");

/** Run one JSON-RPC session against the server over stdio and collect replies. */
function rpc(requests: unknown[], serverArgs: string[] = []): Promise<Map<number, any>> {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["--import", "tsx/esm", path.join(ROOT, "src", "index.ts"), ...serverArgs], {
      cwd: ROOT,
      stdio: ["pipe", "pipe", "ignore"],
    });

    let buf = "";
    const replies = new Map<number, any>();
    child.stdout.on("data", (chunk) => {
      buf += chunk;
      const lines = buf.split("\n");
      buf = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.trim()) continue;
        const msg = JSON.parse(line);
        if (typeof msg.id === "number") replies.set(msg.id, msg);
        if (replies.size === requests.filter((r: any) => "id" in (r as object)).length) {
          child.kill();
          resolve(replies);
        }
      }
    });
    child.on("error", reject);
    child.on("exit", () => resolve(replies));

    for (const req of requests) child.stdin.write(JSON.stringify(req) + "\n");
  });
}

const INIT = {
  jsonrpc: "2.0",
  id: 0,
  method: "initialize",
  params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "test", version: "1" } },
};
const INITIALIZED = { jsonrpc: "2.0", method: "notifications/initialized" };

// Builtin.roc is ~800 KB. Serving it whole would cost a client ~228k tokens in
// one read, so the resource must stay an index.
test("roc-syntax://builtin serves an index, not the whole file", async () => {
  const replies = await rpc([
    INIT,
    INITIALIZED,
    { jsonrpc: "2.0", id: 1, method: "resources/read", params: { uri: "roc-syntax://builtin" } },
  ]);

  const text = replies.get(1)?.result?.contents?.[0]?.text as string;
  assert.ok(text, "no content returned");
  assert.ok(
    text.length < 20_000,
    `builtin resource is ${text.length} chars; it must not serve Builtin.roc in full`
  );
  assert.match(text, /\| Module \| Methods \|/);
  assert.match(text, /get_roc_module/);
  // A module table, not source: no method implementations.
  assert.ok(!text.includes("|_, state, count,"), "resource contains Builtin.roc source");
});

test("every static resource stays small enough to read", async () => {
  const replies = await rpc([
    INIT,
    INITIALIZED,
    { jsonrpc: "2.0", id: 1, method: "resources/list", params: {} },
  ]);
  const resources = replies.get(1)?.result?.resources as { uri: string }[];
  assert.ok(resources?.length, "no resources listed");

  const reads = resources.map((r, n) => ({
    jsonrpc: "2.0",
    id: n + 1,
    method: "resources/read",
    params: { uri: r.uri },
  }));
  const bodies = await rpc([INIT, INITIALIZED, ...reads]);

  for (const [i, r] of resources.entries()) {
    const text = bodies.get(i + 1)?.result?.contents?.[0]?.text as string;
    assert.ok(text != null, `${r.uri} returned nothing`);
    assert.ok(text.length < 100_000, `${r.uri} is ${text.length} chars, too large for one read`);
  }
});

// A package is not a scope, so its page needs its own address next to
// `get_roc_syntax(topic: <name>)`. A resource costs nothing on `tools/list`.
test("a documented package's page is a resource", async () => {
  const replies = await rpc([
    INIT,
    INITIALIZED,
    { jsonrpc: "2.0", id: 1, method: "resources/read", params: { uri: "roc-syntax://package/roc-random" } },
  ]);
  const text = replies.get(1)?.result?.contents?.[0]?.text as string;
  assert.match(text, /^# roc-random\n/);
  assert.match(text, /^This page documents roc-random \d+\.\d+\.\d+\.$/m);
  assert.match(text, /^Topics: random_generators\.$/m);
});

// `List` has 94 methods whose docstrings and `expect` blocks are about 6x the
// size of the signatures. Thus "what methods exist" must not cost a full read of
// all of them.
test("get_roc_module lists signatures by default and docs on request", async () => {
  const replies = await rpc([
    INIT,
    INITIALIZED,
    { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "get_roc_module", arguments: { module: "List" } } },
    { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "get_roc_module", arguments: { module: "List", detail: "full" } } },
  ]);

  const brief = replies.get(1).result;
  const full = replies.get(2).result;

  assert.match(brief.content[0].text, /94 methods\./);
  assert.ok(
    brief.content[0].text.length * 3 < full.content[0].text.length,
    `default output is ${brief.content[0].text.length} chars vs full ${full.content[0].text.length}; it should be far smaller`
  );

  // The method set is the same in both modes. Only the detail differs. The test
  // counts from the text, because the text is the only channel that the client reads.
  const sigs = (text: string) => new Set([...text.matchAll(/^(\w+!?) :/gm)].map((m) => m[1]));
  assert.deepEqual([...sigs(brief.content[0].text)].sort(), [...sigs(full.content[0].text)].sort());
  assert.ok(brief.content[0].text.includes("map : List(a), (a -> b) -> List(b)"));

  // The default has no docstrings, but `full` has them.
  assert.ok(!brief.content[0].text.includes("Put two lists together"));
  assert.match(full.content[0].text, /Put two lists together/);
});

// This server writes the hints, so they must never mix into upstream's docstrings.
test("hints appear only in the signature list, never with the real docs", async () => {
  const HINT = "moves the last item into the gap";
  const replies = await rpc([
    INIT,
    INITIALIZED,
    { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "get_roc_module", arguments: { module: "List" } } },
    { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "get_roc_module", arguments: { module: "List", detail: "full" } } },
    { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "search_symbols", arguments: { query: ["List.drop_swap"] } } },
  ]);

  const brief = replies.get(1).result;
  assert.match(brief.content[0].text, /^# O\(1\): moves the last item into the gap, breaking order$/m);

  const full = replies.get(2).result;
  assert.ok(!full.content[0].text.includes(HINT), "hint leaked into detail=full");

  const single = replies.get(3).result;
  assert.ok(!single.content[0].text.includes(HINT), "hint leaked into search_symbols");
  // Upstream's own prose stays in the reply.
  assert.match(single.content[0].text, /order of the remaining items is not preserved/);
});

// The overview is the first thing a client should read, and it tells the reader
// which tool to call next. A renamed tool would make that advice wrong. The same
// applies to the server instructions that a client injects at connect time.
test("the overview names only tools the server actually registers", async () => {
  const replies = await rpc([
    INIT,
    INITIALIZED,
    { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} },
    { jsonrpc: "2.0", id: 2, method: "resources/read", params: { uri: "roc-syntax://overview" } },
    { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "get_roc_syntax", arguments: {} } },
    { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "get_roc_syntax", arguments: { scope: "builtin" } } },
  ]);

  const registered = new Set((replies.get(1).result.tools as { name: string }[]).map((t) => t.name));
  assert.ok(registered.has("get_roc_syntax"), "get_roc_syntax is not registered");

  const instructions = replies.get(0).result.instructions as string;
  assert.ok(instructions, "the server sends no instructions");
  assert.ok(instructions.length < 1400, `instructions are ${instructions.length} chars; keep them a pointer`);

  // Both texts must name the trigger, not only describe the page. A model that
  // reads "an overview exists" and believes it knows Roc skips the call. This
  // entry point exists to prevent that failure.
  const overviewTool = (replies.get(1).result.tools as { name: string; description: string }[])
    .find((t) => t.name === "get_roc_syntax")!;
  for (const [source, text] of [["instructions", instructions], ["get_roc_syntax", overviewTool.description]] as const) {
    assert.match(text, /before (reading|writing)/i, `${source} states no precondition for calling get_roc_syntax`);
    assert.match(text, /Roc code/i, `${source} does not say the precondition is about Roc code`);
    assert.match(text, /even (when|if) you (believe|think)/i, `${source} does not override a model's own recall of Roc`);
  }

  const overview = replies.get(2).result.contents[0].text as string;
  // Tool names are the only snake_case tokens in these texts that contain `_` and
  // no `.`, so anything shaped like one is a claim about the tool list.
  for (const [source, text] of [["instructions", instructions], ["overview", overview]] as const) {
    const named = new Set(text.match(/\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b/g) ?? []);
    const toolish = [...named].filter((n) => n.startsWith("roc_") || n.startsWith("get_") ||
      n.startsWith("list_") || n.startsWith("search") || n.startsWith("lookup_"));
    assert.ok(toolish.length > 3, `${source} names only ${toolish.length} tools`);
    for (const name of toolish) {
      assert.ok(registered.has(name), `${source} names ${name}, which is not a registered tool`);
    }
  }

  // The tool returns the resource's page, then what this workspace adds: the
  // detected platform, or the list to choose one from if detection found none.
  // A resource is the same bytes for every reader and cannot carry that data.
  // Thus the page is a prefix of the answer, not the whole answer.
  const answer = replies.get(3).result.content[0].text as string;
  assert.ok(answer.startsWith(overview), "the tool's answer is not the resource's page plus notes");
  assert.ok(replies.get(4).result.content[0].text.length < overview.length / 1.5);
  assert.ok(overview.length < 12_000, `the overview is ${overview.length} chars; it must stay cheap to read`);
});

// No tool changes the user's files: the tools read bundled reference files, or
// run `roc check` / `roc fmt` on a scratch copy. Clients read `readOnlyHint` to
// decide if a call needs an approval prompt. A new tool without it costs the user
// a confirmation, and nothing reports the cause. A tool that can make the
// compiler download a release says so with `openWorldHint`. Only `roc_fmt`
// never downloads, so it alone is closed-world.
test("every tool advertises itself as read-only, and as open-world when it can download", async () => {
  const replies = await rpc([INIT, INITIALIZED, { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }]);
  const tools = replies.get(1).result.tools as { name: string; annotations?: Record<string, unknown> }[];
  assert.ok(tools.length >= 7, `only ${tools.length} tools listed`);

  for (const t of tools) {
    assert.deepEqual(
      t.annotations,
      { readOnlyHint: true, openWorldHint: t.name !== "roc_fmt" },
      `${t.name} does not advertise the read-only annotations`
    );
  }

  // The annotations cost tokens on every request, so keep the whole list in the
  // budget that the rest of this server is designed for.
  const bytes = JSON.stringify(tools).length;
  assert.ok(bytes < 15_500, `the tool list is ${bytes} chars; it must stay cheap to send`);
});

// serverInfo must report the version from package.json. The server sends
// websiteUrl and description once at connect, not per request, so they are
// worth their bytes.
test("serverInfo reports the packaged version and points at the repo", async () => {
  const replies = await rpc([INIT]);
  const info = replies.get(0).result.serverInfo as Record<string, string>;
  const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf-8"));

  assert.strictEqual(info.version, pkg.version, "serverInfo.version has drifted from package.json");
  assert.match(info.websiteUrl, /^https:\/\/github\.com\//);
  assert.ok(info.description?.includes("Roc"));
});

// The rest of the suite negotiates 2024-11-05, four revisions behind the latest
// revision of the SDK. A server that works only on legacy revisions would pass
// every other test here, so this test pins the latest revision.
test("the server serves the latest protocol revision, not just the legacy era", async () => {
  const init = {
    ...INIT,
    params: { ...INIT.params, protocolVersion: LATEST_PROTOCOL_VERSION },
  };
  const replies = await rpc([
    init,
    INITIALIZED,
    { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} },
    { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "get_roc_syntax", arguments: { part: "language" } } },
    { jsonrpc: "2.0", id: 3, method: "resources/read", params: { uri: "roc-syntax://overview" } },
  ]);

  assert.strictEqual(replies.get(0).result.protocolVersion, LATEST_PROTOCOL_VERSION);
  assert.strictEqual((replies.get(1).result.tools as unknown[]).length, 7);
  assert.match(replies.get(2).result.content[0].text, /Roc/);
  assert.ok(!replies.get(2).result.isError);
  assert.match(replies.get(3).result.contents[0].text, /Roc/);
});

// Zod v3 schemas compile against the v2 SDK but fail at runtime: `tools/list`
// emits a schema with no properties, and nothing rejects a bad argument. Neither
// symptom gives an error, so assert that the schema reached the wire and that
// validation rejects a bad value.
test("tool input schemas survive the trip to the wire", async () => {
  const replies = await rpc([
    INIT,
    INITIALIZED,
    { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} },
    { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "get_roc_syntax", arguments: { scope: "nonsense" } } },
  ]);

  const tools = replies.get(1).result.tools as { name: string; inputSchema: any }[];
  const overview = tools.find((t) => t.name === "get_roc_syntax")!;
  assert.deepEqual(overview.inputSchema.properties.scope.enum, [
    "language",
    "builtin",
    "basic-webserver",
    "basic-cli",
  ]);
  assert.ok(overview.inputSchema.properties.scope.description, "the describe() text was dropped");

  // Every tool takes arguments, so every tool must declare them.
  for (const t of tools) {
    assert.ok(
      Object.keys(t.inputSchema.properties ?? {}).length > 0,
      `${t.name} reached the wire with no input properties`
    );
  }

  assert.ok(replies.get(2).result.isError, "an invalid enum value was accepted");
});

// A client pays for the tool list on every request, whether it calls a tool or
// not. Thus the list has a fixed budget, not a trend. The estimate is the same
// as in .claude/skills/refresh-roc-upstream/scripts/tool-cost.mjs.
//
// This test measures the shipped configuration. The tokens that installed
// plugins add have their own per-tool allowance, `PLUGIN_TOOL_GROWTH`, and do
// not use this budget, because the person who installed the plugins pays for them.
test("the whole tool list stays inside its token budget", async () => {
  const replies = await rpc([INIT, INITIALIZED, { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }]);
  const tools = replies.get(1).result.tools as unknown[];
  const cost = Math.round(JSON.stringify({ tools }).length / 3.5);
  assert.ok(cost < 2800, `tools/list costs ~${cost} tokens for ${tools.length} tools`);
});

/** `get_roc_syntax`'s description, which is where topic names are spelled out. */
async function syntaxToolDescription(serverArgs: string[] = []): Promise<string> {
  const replies = await rpc(
    [INIT, INITIALIZED, { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }],
    serverArgs
  );
  const tools = replies.get(1).result.tools as { name: string; description: string }[];
  return tools.find((t) => t.name === "get_roc_syntax")!.description;
}

// Only one platform is active at a time. The topics of a different platform
// would cost tokens on every request, for calls that this workspace cannot make.
// Language topics always apply, so the description always names them.
test("the topic enumeration names no platform when none is configured", async () => {
  const description = await syntaxToolDescription();

  assert.match(description, /pattern_matching/, "language topics are not enumerated");
  assert.doesNotMatch(description, /\bcli_\w+/, "an unconfigured platform's topics are named");
  assert.doesNotMatch(description, /\bwebserver_\w+/, "an unconfigured platform's topics are named");
  // Without the names, the description must still point to the listing.
  assert.match(description, /list_roc_index\(kind='topics'\)/);
});

test("a configured platform is enumerated and the others still are not", async () => {
  const description = await syntaxToolDescription(["--platform=basic-cli"]);

  assert.match(description, /cli_sqlite/, "the configured platform's topics are missing");
  assert.match(description, /pattern_matching/, "language topics are not enumerated");
  assert.doesNotMatch(description, /\bwebserver_\w+/, "a platform that is not configured is named");
  // Every topic it can reach is already listed, so the pointer would be noise.
  assert.doesNotMatch(description, /list_roc_index\(kind='topics'\)/);
});

// An installed plugin is the only data that `tools/list` has about this
// workspace. If the description names the plugin's topics, a model calls a topic
// by name. A model must guess an omitted topic, miss it and retry. That was the
// real cost after an install of roc-ray and a search for `ray_project`.
test("a declared platform's topics are enumerated without being configured", async () => {
  const description = await syntaxToolDescription([`--plugin=${path.join(ROOT, "plugins", "roc-ray")}`]);

  assert.match(description, /ray_project/, "the installed platform's topics are missing");
  assert.match(description, /pattern_matching/, "language topics are not enumerated");
  assert.doesNotMatch(description, /\bcli_\w+/, "a bundled platform nobody asked for is named");
  // Every topic it can reach is already listed, so the pointer would be noise.
  assert.doesNotMatch(description, /list_roc_index\(kind='topics'\)/);
});

// The working set holds a platform only when one is pinned or installed. Thus
// the server answers a question about an unpinned platform from the language and
// the builtins only. That answer reads as "no such thing", not as "not here".
test("every tool taking a scope says when to name a platform in it", async () => {
  const replies = await rpc([INIT, INITIALIZED, { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }]);
  const tools = replies.get(1).result.tools as { name: string; inputSchema: any }[];
  for (const name of ["get_roc_syntax", "search_symbols"]) {
    const scope = tools.find((t) => t.name === name)!.inputSchema.properties.scope.description as string;
    assert.match(scope, /Name a platform \(basic-webserver, basic-cli\)/, name);
    assert.match(scope, /rather than the language or the builtins/, name);
  }
});

// Each name in the enumeration must resolve. If the enumeration and the listing
// differ, a model reads a name from `tools/list` and gets "no topic matched".
test("the enumeration names exactly the topics list_roc_index offers", async () => {
  const replies = await rpc(
    [
      INIT,
      INITIALIZED,
      { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} },
      {
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: { name: "list_roc_index", arguments: { kind: "topics" } },
      },
    ],
    ["--platform=basic-cli"]
  );

  const tools = replies.get(1).result.tools as { name: string; description: string }[];
  const description = tools.find((t) => t.name === "get_roc_syntax")!.description;
  const enumerated = description
    .match(/Topics: ([^.]*(?:\.\w)?[^.]*)\./)![1]
    .split(", ")
    .map((n) => n.trim())
    .sort();

  const listing = replies.get(2).result.content[0].text as string;
  const listed = [...listing.matchAll(/^- \*\*(\w+)\*\*/gm)].map((m) => m[1]).sort();

  assert.deepEqual(enumerated, listed);
  assert.ok(enumerated.includes("cli_sqlite"), "the configured platform is missing from both");
});

// Measured against Claude Code 2.1.241 in docs/evals/agentic.md: if a reply
// carries `structuredContent`, the client gives the model that JSON and drops
// the text. Every scope footer, the detection note and the markdown formatting
// are in the text. Thus a tool that declares an output schema deletes them with
// no warning, and also makes the tool list cost more.
test("no tool declares an output schema or returns structured content", async () => {
  const calls: [string, Record<string, unknown>][] = [
    ["get_roc_syntax", {}],
    ["list_roc_index", { kind: "scopes" }],
    ["get_roc_syntax", { topic: "sort list" }],
    ["search_symbols", { query: ["Str.concat"] }],
    ["search_symbols", { query: ["-> Bool"] }],
  ];
  const replies = await rpc([
    INIT,
    INITIALIZED,
    { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} },
    ...calls.map(([name, args], i) => ({
      jsonrpc: "2.0", id: i + 2, method: "tools/call", params: { name, arguments: args },
    })),
  ]);

  for (const t of replies.get(1).result.tools as { name: string; outputSchema?: unknown }[]) {
    assert.strictEqual(t.outputSchema, undefined, `${t.name} declares an outputSchema`);
  }
  calls.forEach(([name], i) => {
    const result = replies.get(i + 2).result;
    assert.strictEqual(result.structuredContent, undefined, `${name} returned structuredContent`);
    assert.ok(result.content?.[0]?.text, `${name} returned no text`);
  });
});

// A scope value that a tool cannot act on is worse than no parameter. It costs
// tool-list tokens and invites a call that has no meaning. roc_check scaffolds
// an app, and only a platform has an app to scaffold.
test("roc_check offers only the scopes it can scaffold", async () => {
  const replies = await rpc([
    INIT,
    INITIALIZED,
    { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} },
    { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "roc_check", arguments: { code: "x = 1", scope: "builtin" } } },
  ]);
  const check = (replies.get(1).result.tools as { name: string; inputSchema: any }[])
    .find((t) => t.name === "roc_check")!;
  assert.deepEqual(check.inputSchema.properties.scope.enum, ["basic-webserver", "basic-cli"]);
  assert.ok(replies.get(2).result.isError, "a scope with no scaffold was accepted");
});

// list_roc_index serves the indexes, and the tools list_roc_topics,
// list_builtin_modules, list_roc_langref and get_roc_langref must not be
// registered. The indexes share an item shape, so a `kind` that returned the
// wrong index would type-check and look plausible to a reader.
test("list_roc_index serves the topic and module indexes", async () => {
  const call = (args: Record<string, string>, id: number) => ({
    jsonrpc: "2.0", id, method: "tools/call", params: { name: "list_roc_index", arguments: args },
  });
  const replies = await rpc([
    INIT, INITIALIZED,
    { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} },
    call({ kind: "topics" }, 2),
    call({ kind: "modules" }, 3),
  ]);

  const names = (replies.get(1).result.tools as { name: string }[]).map((t) => t.name);
  assert.ok(names.includes("list_roc_index"));
  for (const gone of ["list_roc_topics", "list_builtin_modules", "list_roc_langref", "get_roc_langref"]) {
    assert.ok(!names.includes(gone), `${gone} is still registered`);
  }

  const body = (id: number) => replies.get(id).result.content[0].text as string;
  const entries = (text: string) => [...text.matchAll(/^- (?:\*\*)?([\w.-]+)/gm)].map((m) => m[1]);

  // Each index has its own heading and line shape, so this test finds a wrong
  // `kind` that would otherwise return a plausible wrong list.
  assert.match(body(2), /^# Roc Syntax Topics$/m);
  assert.match(body(3), /^# Modules$/m);

  // Derived from the bundled files, not from the server's own map, so the test
  // finds a topic that is missing from the map.
  // `scripting` is language-scoped but is filed under basic-cli. It is a complete
  // app that `npm run check:platforms` compiles, not a fragment that
  // `npm run check:roc` wraps.
  // The topics of a documented package are also filed under `language`.
  const packageTopics = fs
    .readdirSync(path.join(ROOT, "corpus", "packages"))
    .flatMap((p) => {
      const dir = path.join(ROOT, "corpus", "packages", p, "topics");
      return fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".roc")) : [];
    });
  const topicFiles = [
    ...fs.readdirSync(path.join(ROOT, "corpus", "language", "topics")).filter((f) => f.endsWith(".roc")),
    "scripting.roc",
    ...packageTopics,
  ];
  assert.strictEqual(entries(body(2)).length, topicFiles.length);
  // Topics have a detail after the name. Modules have no detail.
  assert.ok(entries(body(2)).every((n) => new RegExp(`\\*\\*${n}\\*\\*: \\S`).test(body(2))));

  assert.strictEqual(entries(body(3)).length, 49, "the builtin module count changed");
  assert.ok(!/^ /m.test(body(3)), "the module index grew nested lines");
});

// One tool answers the overview and the topics. `overview` is an address,
// because a model asks for the overview by that name, and a miss costs 6k characters.
test("get_roc_syntax answers the overview without a topic, and one topic with one", async () => {
  const call = (id: number, args: unknown) =>
    ({ jsonrpc: "2.0", id, method: "tools/call", params: { name: "get_roc_syntax", arguments: args } });
  const replies = await rpc([
    INIT,
    INITIALIZED,
    call(1, {}),
    call(2, { topic: "overview" }),
    call(3, { topic: "pattern_matching" }),
    call(4, { topic: "no_such_topic_here" }),
    call(5, { topic: "pattern_matching", scope: "builtin" }),
  ]);
  const text = (id: number) => replies.get(id).result.content[0].text as string;

  assert.match(text(1), /^# Roc in one page/);
  assert.equal(text(2), text(1));

  assert.match(text(3), /^## pattern_matching/);
  assert.ok(text(3).length < 6000, `a topic answered with ${text(3).length} chars`);

  assert.match(text(4), /^Nothing matched "no_such_topic_here"/);
  assert.ok(text(4).length < 6000, `a miss answered with ${text(4).length} chars`);

  // `scope` takes every corpus, because without a topic it selects a page. Some corpora have no topics.
  assert.match(text(5), /in scope=builtin\. This corpus has no topics\./);
});

// `roc_check` takes `code` or `path`, and `roc_fmt` must take the same inputs.
// Otherwise a model finds the difference only from a failed call and its schema
// error.
test("roc_fmt takes the same either/or as roc_check", async () => {
  const tool = (args: Record<string, unknown>, id: number) => ({
    jsonrpc: "2.0", id, method: "tools/call", params: { name: "roc_fmt", arguments: args },
  });
  const replies = await rpc([
    INIT,
    INITIALIZED,
    tool({}, 1),
    tool({ code: "module [x]\n", path: "/tmp/x.roc" }, 2),
    tool({ path: "relative.roc" }, 3),
    tool({ path: "/no/such/file.roc" }, 4),
  ]);
  const text = (id: number) => replies.get(id).result.content[0].text as string;

  for (const id of [1, 2, 3, 4]) assert.ok(replies.get(id).result.isError, `call ${id} was accepted`);
  assert.match(text(1), /Provide either `code` \(Roc source\) or `path`/);
  assert.match(text(2), /Pass `code` OR `path`, not both\./);
  assert.match(text(3), /`path` must be absolute/);
  assert.match(text(4), /Could not read \/no\/such\/file\.roc/);
});

