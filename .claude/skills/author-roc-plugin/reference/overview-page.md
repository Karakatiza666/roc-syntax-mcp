# The overview page

`roc_overview` returns this page whole. It is the first text that a model reads
about your platform, and often the only text that it reads before it writes
code. Thus each sentence on the page costs tokens on every call, and the model
guesses each fact that the page omits.

`corpus/platforms/basic-cli/overview.md` is the worked example that this repo
ships. Read it beside this page.

## The budget

`plugin validate` enforces a ceiling of 4000 tokens, at 3.5 characters per
token. The pages that this server ships are well under it.

A page near the ceiling usually has a problem. A long page usually started to
list the API. The API is already in the index, where `get_builtin_module` and
`search_symbols` return it at no cost until a caller asks for it.

To decide whether a paragraph belongs, ask this question: would a model that
read the index still get this wrong? If not, remove the paragraph.

## The parts

The page has up to seven parts, in this order. The order is important, because a
reader who stops early should still have the parts that prevent the worst
mistakes.

| Part | Holds | Length |
|---|---|---|
| Lead | The release and its packages, and how to get to the index from here | 3 to 5 lines |
| Project | Only when the platform needs it: the files of a project, and the commands that build and run it | A short section |
| Contract | The app header, the entry point, its type, and what the platform fixes | One snippet and a paragraph |
| Core modules | The one or two modules that all real code uses, with the misleading module named | A section |
| Area sections | One for each area that a real app uses, each with its findings | 3 to 6 sections |
| Errors | The shape of this platform's failures, and how to match them | A section |
| Traps | The findings that fit nowhere else, one line each | A short list |

The lead has the most value on the page, and it is the easiest part to waste.
It should tell a reader what the platform is built from and how to get more
information, not what the platform is for. For example:

```
The platform, with the HTTP types from the `roc-lang/http` package.
`get_builtin_module Path` for the full API, `search_symbols Cmd.exec_output!`
for one method, `search scope="basic-cli"` when you do not know the name,
`list_roc_index kind="examples"` for complete programs that all compile.
```

Write no version and no count. The server states the release below the page
when it serves the page, and each number on the page is one more line to edit
on every repin. A version belongs on the page only as an instruction, for
example a package release that an app must pin itself.

The example names four tool calls, each with the argument that makes it work. A
model that reads only the lead can still find everything else.

## Project

A model can write code that type-checks and still fail to run the app. That
happens when the build or the run of a project differs from `roc main.roc`, and
the index cannot tell the model how. Write this part only for such a platform.
Each line must change a file that the model writes or a command that it runs.

| Put in | Example |
|---|---|
| A build or run command that differs from `roc main.roc` | joy builds with `--target=wasm32` |
| Files that the app needs beside the build output | joy copies `runtime.js` from the package cache |
| The project layout that the platform expects | A packaged roc-ray game reads its assets beside the executable |
| A warning that every check prints and that is not in the caller's code | roc-ray's "roc version mismatch" under another nightly |

Leave out what is the same for every Roc project: how to install Roc, editor
setup, formatting and CI. basic-cli and basic-webserver run with `roc main.roc`,
so their pages have no Project part. `plugins/joy/joy-overview.md` and
`plugins/roc-ray/overview.md` show the part, under "Starting a project".

## Core modules

Almost every platform has one or two modules that all real code uses. It also
has a module whose name suggests that it is one of them, but it is not. Name
both together, as early on the page as possible.

basic-cli is the clearest case. The full filesystem API is on `Path`, and `File`
holds only the buffered reader. A page that lists both modules alphabetically,
and describes each one fairly, does not help the reader. The reader goes to
`File`, because of its name.

## Snippets

Every fenced `roc` block on the page also exists in an app under `checks`,
usually `verify/overview-snippets.roc`. `plugin validate` fails the page when a
block is in no such app.

This check prevents drift. If nothing compiles the page's snippets, the page
drifts. The release changes, a signature changes, and the page continues to
teach Roc that worked in the past. The verify app lets `validate` check what the
page claims.

Rules for how you write the snippets:

- Write them so that they can exist together in one app. Use distinct binding
  names, and do not let two blocks define the same thing.
- Prefer a snippet that compiles to a snippet that reads better. A block with an
  elision cannot be verified, so write that content as prose.
- When a block cannot compile alone, write it as prose and put no code fence on
  the page.

## Findings on the page

Write each finding as one clause in the paragraph that the reader is already
reading, not as a callout. The nanoseconds fact belongs in the sentence about
time. Do not put it in a box at the bottom, which a reader who looks for the
time API will skip.

The trap list at the end is for the findings that do not belong to one area.
Keep it short. A long trap list means that the findings are not in the sections
where they apply. `reference/finding-traps.md` explains why that costs more than
it seems to.

## What to leave out

| Leave out | Reason |
|---|---|
| Full module listings | `get_builtin_module` returns them, and only when a caller asks |
| Signature dumps | `search_symbols` returns one signature, and only that one |
| Anything about the platform's Rust or Zig host | An app author cannot call it and must not try |
| How to install Roc, editor setup, formatting, CI | They are the same for every Roc project. The Project part above holds only what this platform changes |
| A changelog | `version` and `compiler` are in the manifest, and the listing reports them |
| Praise of the platform | It costs tokens on every call and changes no output |
