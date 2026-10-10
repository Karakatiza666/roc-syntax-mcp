# plugin.json, field by field

The manifest holds only data. It contains no regex, no code and no path that
leaves the plugin directory. Its type is `PluginManifest` in `src/scopes.ts`,
and `fromManifest` is its only constructor. This repo builds its own scopes
through `fromManifest`, from manifests stored beside their corpora. Thus a
plugin goes through the same code that every check in this repo already runs.

## The shape

A plugin is a list of corpora. Each corpus documents one release, a platform or
a package, and all corpora take the same fields.

```json
{
  "schema": 1,
  "maintainer": "niclas-ahden",
  "compiler": "nightly-<date>-<commit>",
  "corpora": [
    {
      "release": "https://github.com/niclas-ahden/joy/releases/download/<tag>/<hash>.tar.zst",
      "description": "...", "purpose": "web apps in the browser",
      "overview": "joy/overview.md", "examples": "joy/examples",
      "scaffold": "joy/scaffold.roc", "sample": "joy/sample.roc",
      "checks": ["joy/topics", "verify"], "topics": [...]
    },
    {
      "release": "https://github.com/niclas-ahden/joy-html/releases/download/<tag>/<hash>.tar.zst",
      "description": "...", "overview": "joy-html/overview.md", "topics": [...]
    }
  ]
}
```

## What the release decides

A `release` is any value that an app header can pin, which is any URL that
`roc deps` fetches. That is an https URL whose file name is the tarball's
content hash.
A GitHub release URL is the usual case, and it gives the most information. The
URL and the release's own header set the values in this table. No manifest field
may repeat them, so no field can disagree with the release contents.

| Read from | GitHub release URL | Any other https URL |
|---|---|---|
| Identity, the package namespace | The repo, `owner/repo` | The host and directory, `host/dir` |
| Default name | The repo name | The last directory. Required as `name` when that directory is not a valid name, such as `1.0.0` |
| Version | The tag | The first 12 characters of the hash. Hashes have no order, so the host reports a different bundle as different, never as older or newer |
| What detection matches | Any tag of that repo | Any bundle under that directory |
| Platform or package | The header keyword in `index.json`, written by `plugin index` | Same |

A local path is not a release, because no other machine can fetch it. To
document code that has no release, bundle it with `roc build --bundle .tar.br`,
host the file at any https URL, and name that URL.

| Kind | `description` | Becomes | Its package loads at |
|---|---|---|---|
| Platform | Required | A scope. Detected from an app header | Not a package |
| Package | Present | A page and topics, but no scope | Tier 1, or tier 3 for a package that this server ships |
| Package | Absent | Signatures only. No page, and nothing in `tools/list` | Same |

The loader refuses `overview`, `examples`, `topics` and `checks` on a package
with no `description`. With no description, nothing lists the package, so
nothing reads those fields. `reference/package-plugin.md` covers packages.

## Top-level fields

| Field | Type | Required | Is |
|---|---|---|---|
| `schema` | positive integer | Yes | The manifest's schema version, `1`. The host reports it when it is older than the host's version, and never refuses it |
| `maintainer` | string | By `validate` | The person who answers for every corpus here. The scope listing prints it unchanged. If it is absent, the listing says that no maintainer is named |
| `compiler` | string | No | The nightly that the corpora were built against. The host reports it when it differs from the host's nightly, and never refuses it. `validate` checks the programs that pin these releases with it |
| `corpora` | array, not empty | Yes | See below |

## Corpus fields

| Field | Type | Platform | Package | Is |
|---|---|---|---|---|
| `release` | tarball URL | Required | Required | The release that this corpus documents. The host reads it from `index.json` beside the manifest. The loader refuses a `dir`, because a plugin ships the release's index, never its source |
| `name` | `^[a-z][a-z0-9-]*$` | Optional | Optional | Defaults to the repo name. A platform's scope name, or the name that a package's page answers to. Must not be `language`, `builtin`, a name that this server ships, or the name of another corpus |
| `description` | string | Required | For a page | One line, shown by `list_roc_index(kind: "scopes")` |
| `purpose` | string, at most 60 chars | By `validate` | Optional | A few words for the list that a caller selects from. If absent, the list uses `description` |
| `overview` | path | Optional | Optional | The page that `get_roc_syntax(scope: "<name>")` returns for a platform, or that `get_roc_syntax(topic: "<name>")` returns for a package |
| `examples` | path | Optional | Optional | Worked programs, listed by `list_roc_index(kind: "examples")` |
| `topics` | array | Optional | Optional | Programs served by name. Each one must also be under a `checks` directory |
| `checks` | array of paths | By the `roc check` check | By the `roc check` check | Directories of complete programs that `validate` compiles, in addition to `examples`. Two corpora can share one directory |
| `docs` | path | Optional | Refused | Prose bundled unchanged. Only a scope serves it |
| `scaffold` | path | For `roc_check` | Refused | The app that `roc_check` wraps a caller's bare source in |
| `sample` | path | By the `roc_check` check | Refused | Bare source with no header, which is the input that `roc_check` receives. `validate` compiles it through the scaffold |

Every path is relative to the manifest. This host resolves each path against the
directory that it read the manifest from. It refuses a path that climbs out with
`..`, and does not follow it.

## A platform and its package in one plugin

When a platform's API uses a package's types, ship both. joy's `render` returns
joy-html's `Html`, so the two are one plugin.

The loader applies one rule to the pair: a package that a plugin ships must be
the release that the plugin's own platform pins. The compiler treats two
releases of one package with different content as two nominal types. Thus any
other release documents an app that nobody can write, and the loader refuses the
plugin and names both versions.

The host reads what the platform was compiled against from the
`packages { ... }` block in the platform's header. The manifest never repeats
it, because a manifest field can drift and the header cannot.

## Detection

The host detects a platform by its release URL, and the host builds the
pattern:

```
<repo>/releases/download/(\d+\.\d+\.\d+(?:-<prerelease>)?)/      a GitHub release
https://<host>/<dir>/(<12 hash chars>)\w*\.tar\.(zst|br|gz)        anywhere else
```

The manifest declares fields and not a pattern, by design. A regex from a
manifest that this server did not write adds no value. It only gives a way to
hang the process with a crafted app header, and a release URL already pins every
Roc platform. Capture group 1 is the version that the app pinned.

Result for you: an app header must contain a real release URL, or detection does
not match. The `roc_check` check in `validate` also needs that URL to give a
meaningful result, so do not try to work around this requirement.

## Packages and the boundary

A package's id is the repo path in its URL, and that id is the namespace
identity. Thus one package keeps one namespace across releases. Two providers of
`roc-lang/http` are two candidates for one namespace, not two separate corpora.

No manifest field overrides a boundary refusal, and there will be none. `force`
belongs to the end-user, who sets it in their own configuration, so a plugin
cannot vouch for itself. `reference/package-plugin.md` lists the two places
where the end-user can set it.

## The compatibility contract

| Rule | Means |
|---|---|
| The host ignores unknown fields | A plugin built for a newer host still loads on an older one |
| Every field added later is optional, with a default | An older plugin still loads on a newer host |
| A field never gets a new meaning under an existing name | Fields are added, never repurposed |
| The host reports the `schema` version and never refuses a plugin because of it | A host update never invalidates an installed plugin |

`src/testdata/plugin-v1/` is the frozen fixture that holds this repo to the
contract. It has a platform and a package in one manifest, it uses every field,
and `src/scopes.test.ts` asserts it field by field. It can gain fields as the
schema grows. No field in it may change meaning.

## What a bad manifest costs

Only the failure in the first row makes the server exit. It is the one failure
that the server cannot partly accept, because the operator wrote a name and it
resolved to nothing.

| Failure | The server |
|---|---|
| A declared plugin does not resolve at all | Exits with a non-zero code, and writes the reason to stderr |
| The manifest is unreadable or malformed, or a release is not indexed | Skips that plugin, loads the rest, and reports a diagnostic |
| It carries fields that this host does not know | Loads it |
| A corpus file fails to parse | Skips the file, keeps the plugin, and reports a diagnostic |
| Two plugins claim one name | Keeps the first plugin, skips all of the second plugin, and reports a diagnostic |
| A package override is refused, and the namespace has no provider | Resolves, reports a diagnostic, and answers lookups with a note |

Diagnostics go to stderr at startup, where an operator looks, and to
`list_roc_index(kind: "scopes")`, where a model looks. `plugin doctor` prints
both without a server start, so use it to find all of these problems.
