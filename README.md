# Roc Syntax MCP Server

An [MCP](https://modelcontextprotocol.io/) server that gives AI agents access to
the Roc programming language's **new compiler** syntax and standard library.

It bundles:

- A verbatim mirror of [`all_syntax_test.roc`](https://github.com/roc-lang/roc/blob/main/test/echo/all_syntax_test.roc)
- Per-topic focused syntax snippets in `examples/topics/`
- A copy of [`Builtin.roc`](https://github.com/roc-lang/roc/blob/main/src/build/roc/Builtin.roc),
  parsed into a lookup index of every builtin type and method (signatures + docstrings)

> **Note:** This targets Roc's new compiler. See
> [the mini tutorial](https://github.com/roc-lang/roc/blob/main/docs/mini-tutorial-new-compiler.md)
> for what's new (`Try` replacing `Result`, `Bool.True`/`Bool.False`, `List(U8)`
> instead of `List U8`, the `?` postfix operator, static dispatch, etc.).

## Installation

```bash
npm install
npm run build
```

Or install globally directly from the repo (builds automatically via the `prepare` hook):

```bash
# npm
npm install -g git+https://github.com/Karakatiza666/roc-syntax-mcp.git
```

### Upgrading a global npm install

Re-run the same install command — it replaces the existing version in-place:

```bash
# npm
npm install -g git+https://github.com/Karakatiza666/roc-syntax-mcp.git
```

After upgrading, restart any client that uses the server (Claude Desktop, Claude Code, etc.) so it picks up the new binary.

## Usage

```bash
# Development mode (tsx)
npm run dev

# Production mode
npm start

# If installed globally:
roc-syntax-mcp
```

### Configuring with Claude Desktop

`~/.config/claude/claude_desktop_config.json` (Linux) /
`~/Library/Application Support/Claude/claude_desktop_config.json` (macOS):

```json
{
  "mcpServers": {
    "roc-syntax": {
      "command": "node",
      "args": ["/absolute/path/to/roc-syntax-mcp/dist/index.js"]
    }
  }
}
```

Or for development:

```json
{
  "mcpServers": {
    "roc-syntax": {
      "command": "npx",
      "args": ["tsx", "/absolute/path/to/roc-syntax-mcp/src/index.ts"]
    }
  }
}
```

### Configuring with Claude Code

After building or installing globally, register the server from any terminal:

```bash
# If installed globally (available in all projects)
claude mcp add --scope user roc-syntax -- roc-syntax-mcp

# From a local build (project-scoped, stored in .mcp.json — commit to share with team)
claude mcp add --scope project roc-syntax -- node /absolute/path/to/roc-syntax-mcp/dist/index.js
```

Verify with `claude mcp list`.

## Available Tools

### Syntax reference

| Tool | What it does |
|------|--------------|
| `get_roc_syntax` | Returns the full `all_roc_syntax.roc` reference file (mirror of upstream). |
| `list_roc_topics` | Lists every available topic with a one-line description. |
| `search_roc_syntax` | Returns a focused per-topic example. Accepts a topic name or free-text keyword. |

### Builtin lookup (powered by `Builtin.roc`)

| Tool | What it does |
|------|--------------|
| `lookup_builtin` | Look up a builtin by name. Accepts bare (`concat`, `map`) or fully-qualified (`Str.concat`, `List.map`, `U64.from_str`) names. Returns signature + docstring. |
| `get_builtin_module` | Returns every method of a builtin module (`Str`, `List`, `Bool`, `U64`, `Dec`, `Num.F64`, ...). |
| `list_builtin_modules` | Enumerates every available module path. |

### Unified search

| Tool | What it does |
|------|--------------|
| `search` | Ranked free-text search across BOTH syntax topics AND `Builtin.roc`. Returns the top-N hits with a `kind` field (`topic` or `builtin`). Use this when you don't yet know which surface area answers the question. |
| `search_builtin_signatures` | Hoogle-style structural signature search. Type variables are renamed for isomorphism matching (`List x, (x -> y) -> List y` finds `List.map`). Prefix with `->` to search by return type only. Argument order matters. |

### Roc CLI integration

| Tool | What it does |
|------|--------------|
| `roc_check` | Runs `roc check` against either a `code` string (written to a temp file) or an absolute `path`. Returns exit code, stdout, and stderr. Requires the `roc` binary (new compiler) on PATH; returns a clear error if not found. |
| `roc_fmt` | Runs `roc fmt` on a `code` string and returns the canonical formatting (and whether it was already canonical). Same PATH requirement as `roc_check`. |

## Resources (MCP `resources/`)

Clients that support MCP resources (Claude Desktop, etc.) can attach these
without going through a tool call:

| URI | What it is |
|-----|------------|
| `roc-syntax://reference` | Full `all_roc_syntax.roc` reference. |
| `roc-syntax://builtin` | Complete `Builtin.roc`. |
| `roc-syntax://topic/{name}` | Templated — one per topic (e.g. `roc-syntax://topic/try_operator`). Supports tab-completion of `{name}`. |

## Available Topics

| Topic | Description |
|-------|-------------|
| `operators` | Arithmetic, comparison, and boolean operators. |
| `pattern_matching` | `match` expressions with tuple/tag patterns. |
| `list_patterns` | List destructuring (`..`, `as` bindings, match guards). |
| `tag_unions` | Sum types, `Try`, multi-payload tags, open tag unions. |
| `try_operator` | The `?` postfix operator (with err-mapping forms). |
| `strings` | Interpolation, multi-line `\\` strings, unicode escapes. |
| `effects` | Effectful functions (`!`, `=>`). `echo!` is built-in. |
| `loops` | `for`, `while`, `break`, and reassignable `var $name`. |
| `conditionals` | `if`/`else`/`else if` (always expression). |
| `tuples` | Tuples, destructuring, `.0`/`.1` access. |
| `records` | Records, destructuring, `{ ..base, x: y }` update. |
| `types` | Annotations, type variables, `where`, pure (`->`) vs effectful (`=>`). |
| `numbers` | Numeric literals (`5.U64`, `0x5`, `0o5`, `0b0101`). Default `Dec`. |
| `opaque` | Opaque types (`::`) with optional methods. |
| `nominal` | Nominal types (`:=`) with `is_eq` and other methods. |
| `functions` | Anonymous functions, blocks, `return`, `...` placeholder. |
| `static_dispatch` | `.method()` dispatch and `->fn(arg)` arrow application. |
| `imports` | Module imports, aliases, file embedding. |
| `testing` | `expect` (top-level and block form). |
| `app_header` | Headerless apps and full `app [main!] { pf: ... }` headers. |
| `dbg_crash` | `dbg`, `crash`, and `return` statements. |
| `platforms` | Writing/maintaining a Roc platform: header, `main_for_host!`, hosted FFI (wrapper + host-direct forms), closed-vs-open `Try`, single-variant tag discriminant, field-order ABI, nested `Try`. |
| `builder_pattern` | Fluent / builder pattern: nominal record + setter methods returning Self (Cmd-style). |
| `error_design` | Designing error tag unions: structured payloads, per-subsystem wrappers, open `[..]`, `?` vs `? Tag` vs `.map_err`. |

## Example queries an agent can make

- "Show me the whole Roc syntax reference" → `get_roc_syntax`
- "How does the `?` operator work in Roc?" → `search_roc_syntax` with `try_operator`
- "What methods does `Str` have?" → `get_builtin_module` with `Str`
- "Type signature of `List.map`?" → `lookup_builtin` with `List.map`
- "How do I parse an integer from a string?" → `lookup_builtin` with `from_str`
- "Find a function with signature `List a, (a -> b) -> List b`" → `search_builtin_signatures`

## Refreshing from upstream

To pick up new Roc changes, replace the two source-of-truth files:

```bash
curl -fsSL https://raw.githubusercontent.com/roc-lang/roc/main/test/echo/all_syntax_test.roc \
  -o examples/all_roc_syntax.roc

curl -fsSL https://raw.githubusercontent.com/roc-lang/roc/main/src/build/roc/Builtin.roc \
  -o builtin/Builtin.roc
```

Per-topic snippets in `examples/topics/` are hand-curated and should be reviewed
manually when upstream syntax changes.

## License

MIT
