// SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
// SPDX-License-Identifier: MPL-2.0

// The topic registry: what a query matches, and what a plugin may add to it.

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { CORE, ROOT, type ScopeName, type ScopeTopic } from "./scopes.ts";
import { matchTopic, mergeTopics, topicPath, topicsFor, type TopicMeta } from "./topics.ts";

const TOPICS = topicsFor(CORE).topics;

const builtin: Record<string, TopicMeta> = {
  derived_methods: { file: "derived_methods.roc", description: "d", keywords: ["derive", "_"] },
};

const defs = (topics: ScopeTopic[]): Record<string, { topics?: readonly ScopeTopic[] }> => ({
  "roc-ray": { topics },
});

const topic = (name: string): ScopeTopic => ({
  name,
  file: `/opt/roc-ray/topics/${name}.roc`,
  description: `${name} description`,
  keywords: ["game", "delta time"],
});

// A plugin ships worked programs the way this server does, and the server
// serves them.
test("a plugin's topics are served under its own scope", () => {
  const merged = mergeTopics(builtin, ["roc-ray"] as ScopeName[], defs([topic("ray_game")]), []);
  assert.equal(merged.ray_game.scope, "roc-ray");
  assert.equal(merged.ray_game.file, "ray_game.roc");
  assert.equal(merged.ray_game.dir, "/opt/roc-ray/topics");
  assert.ok(merged.derived_methods, "the host's own topics are still there");
});

// `get_roc_syntax(topic:)` finds a topic by its name, so a plugin must never change
// the answer to an existing call.
test("a plugin cannot displace a topic this server ships", () => {
  const conflicts: string[] = [];
  const clash = { ...topic("derived_methods"), description: "mine" };
  const merged = mergeTopics(builtin, ["roc-ray"] as ScopeName[], defs([clash]), conflicts);
  assert.equal(merged.derived_methods.description, "d");
  assert.deepEqual(conflicts, ["roc-ray declares topic derived_methods, which is already served"]);
});

// A plugin's directory is absolute. Joined under `ROOT`, it gives a path that
// does not exist.
test("an absolute topic directory is read where it is", () => {
  assert.equal(
    topicPath({ file: "ray_game.roc", dir: "/opt/roc-ray/topics", description: "", keywords: [] }),
    "/opt/roc-ray/topics/ray_game.roc"
  );
  assert.equal(
    topicPath({ file: "idioms.roc", description: "", keywords: [] }),
    path.join(ROOT, "corpus", "language", "topics", "idioms.roc")
  );
});

// `_` is a keyword of `derived_methods`, and every snake_case query contains
// `_`. A substring match sends all of these queries to `derived_methods`.
test("a keyword under three characters is exact-match only", () => {
  assert.equal(matchTopic("_", undefined, TOPICS), "derived_methods");
  assert.notEqual(matchTopic("key_pressed", undefined, TOPICS), "derived_methods");
  assert.notEqual(matchTopic("with_camera", ["language"], TOPICS), "derived_methods");
});

// `str` is a keyword of `strings`, so a raw substring match sends "how do I
// structure a game" to string literals. The roc-ray architecture topic exists
// for that question.
test("a keyword matches a whole word, not a word that contains it", () => {
  assert.equal(matchTopic("how do I structure a game", ["language"], TOPICS), null);
  assert.equal(matchTopic("string interpolation", ["language"], TOPICS), "strings");
  // `_` and `.` are separators, so "pattern matching" finds `pattern_matching`.
  assert.equal(matchTopic("how do I use pattern matching", ["language"], TOPICS), "pattern_matching");
});

// A topic name wins over every keyword of every other topic.
test("an exact topic name is matched before anything else", () => {
  for (const name of Object.keys(TOPICS)) {
    assert.equal(matchTopic(name, [TOPICS[name].scope ?? "language"], TOPICS), name);
  }
});

// `json` has the keyword "parse" and comes before every plugin topic. If
// declaration order decides, `json` gets every question with "parse" in it,
// including questions about parsing arguments.
test("the topic accounting for more of the question wins, not the first declared", () => {
  const first: Record<string, TopicMeta> = {
    json: { file: "json.roc", description: "d", keywords: ["parse", "encode"] },
  };
  const merged = mergeTopics(
    first,
    ["roc-ray"] as ScopeName[],
    defs([
      {
        name: "weave_cli",
        file: "/opt/weave/topics/weave_cli.roc",
        description: "d",
        keywords: ["parse", "command line", "arguments"],
      },
    ]),
    []
  );
  assert.equal(matchTopic("how do I parse command line arguments", undefined, merged), "weave_cli");
  // When each topic covers one word, declaration order decides.
  assert.equal(matchTopic("how do I parse this", undefined, merged), "json");
});

// "program" is a webserver_handler keyword (its `program` export), and that
// topic comes first. A one-word tie sends CLI questions to the webserver topic.
test("a cli program question goes to basic-cli, not the webserver", () => {
  assert.equal(matchTopic("write a cli program", undefined, TOPICS), "cli_app");
  assert.equal(matchTopic("how do I write a cli tool", undefined, TOPICS), "cli_app");
});

// scripts/check-topics.roc checks the `@rejects` and `@warns` claims of the
// language topics only. A marker in a platform or plugin topic would be served
// as a checked claim that nothing checks.
test("only language topics carry @rejects and @warns claims", () => {
  const dirs = [
    ...fs.readdirSync(path.join(ROOT, "corpus", "platforms")).map((d) => path.join(ROOT, "corpus", "platforms", d, "topics")),
    ...fs.readdirSync(path.join(ROOT, "plugins")).map((d) => path.join(ROOT, "plugins", d, "topics")),
  ].filter((dir) => fs.existsSync(dir));
  const marked = dirs.flatMap((dir) =>
    fs
      .readdirSync(dir)
      .filter((f) => f.endsWith(".roc") && /^# @(rejects|warns) /m.test(fs.readFileSync(path.join(dir, f), "utf-8")))
      .map((f) => path.relative(ROOT, path.join(dir, f)))
  );
  assert.deepEqual(marked, []);
});

// `get_roc_syntax(topic:)` returns a topic whole, so every read pays for all of
// it. `platforms` gets more room, because it shows the platform header field by
// field, and `platform_abi` already holds what could move out of it.
const TOPIC_TOKENS = 3500;
const TOPIC_TOKENS_FOR: Record<string, number> = { platforms: 4000 };

test("every language topic stays inside its token budget", () => {
  const dir = path.join(ROOT, "corpus", "language", "topics");
  const over = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".roc"))
    .map((f) => ({ name: f.replace(/\.roc$/, ""), tokens: Math.ceil(fs.readFileSync(path.join(dir, f), "utf-8").length / 3.5) }))
    .filter((t) => t.tokens > (TOPIC_TOKENS_FOR[t.name] ?? TOPIC_TOKENS))
    .map((t) => `${t.name}: ${t.tokens} tokens`);
  assert.deepEqual(over, []);
});
