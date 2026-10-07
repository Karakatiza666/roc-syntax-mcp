# Third-party notices

This package bundles source, and signature indexes generated from source, from
the projects below. All of these projects are under the Universal Permissive
License, Version 1.0. The one condition of the UPL is that the copyright notice
and a reference to the UPL travel with the copies. This file is that reference.
The full text is in [`LICENSES/UPL-1.0.txt`](LICENSES/UPL-1.0.txt).

[`REUSE.toml`](REUSE.toml) records, per path, which files carry which notice.
The `UPSTREAM` file beside each tree records the release that the tree is
pinned to. A refresh updates that `UPSTREAM` file.

| Bundled at | From | Copyright |
|---|---|---|
| `corpus/language/Builtin.roc`, `corpus/language/langref/`, `corpus/language/examples/all_roc_syntax.roc` | [roc-lang/roc](https://github.com/roc-lang/roc) | © 2019 Richard Feldman and subsequent Roc authors \<roc-lang.org/authors\> |
| `corpus/platforms/basic-cli/examples/`, `corpus/platforms/basic-cli/index.json` | [roc-lang/basic-cli](https://github.com/roc-lang/basic-cli) | © 2022 Richard Feldman and subsequent basic-cli authors \<github.com/roc-lang/basic-cli/graphs/contributors\> |
| `corpus/platforms/basic-webserver/examples/`, `corpus/platforms/basic-webserver/docs/`, `corpus/platforms/basic-webserver/index.json` | [roc-lang/basic-webserver](https://github.com/roc-lang/basic-webserver) | © 2023 Richard Feldman and subsequent Roc authors \<roc-lang.org/authors\> |
| `corpus/packages/http/index.json` | [roc-lang/http](https://github.com/roc-lang/http) | © 2025 Richard Feldman and subsequent Roc authors \<roc-lang.org/authors\> |
| `corpus/packages/roc-parser/examples/`, `corpus/packages/roc-parser/index.json` | [lukewilliamboswell/roc-parser](https://github.com/lukewilliamboswell/roc-parser) | © 2023 Luke Boswell and subsequent authors \<github.com/lukewilliamboswell/roc-parser/graphs/contributors\> |
| `corpus/packages/roc-random/index.json` | [kili-ilo/roc-random](https://github.com/kili-ilo/roc-random) | © 2022 Jan Van Bruggen and subsequent roc-random authors \<github.com/JanCVanB/roc-random/graphs/contributors\> |

## Modifications

Where a bundled tree differs from its source release, the patch that makes the
difference is kept beside the tree.

| Tree | Change |
|---|---|
| `corpus/platforms/basic-cli/examples/` | Repinned to the bundled platform release. See `patches/` |
| `corpus/platforms/basic-webserver/examples/` | Repinned to the bundled platform release, the gregorian dependency removed because it does not compile under the pinned nightly, and one effectful helper renamed to end in `!`. See `patches/` |
| `corpus/packages/roc-parser/examples/` | The basic-cli pin moved to the release this server bundles, which builds on the pinned nightly. See `patches/` |
| `corpus/language/Builtin.roc`, `corpus/language/langref/`, `corpus/language/examples/all_roc_syntax.roc` | None. Exact copies |
| Every `index.json` | Not a copy. The signatures, docstrings and header of each module in the release, as `scripts/build-index.ts` parses them |

`src/builtin_hints.ts` is an original work, written from the docstrings in
`corpus/language/Builtin.roc`. UPL permits this without condition. The file is
licensed MPL-2.0 with the rest of the server.

## Not bundled, and separately licensed

`plugins/` is not part of this package. Each directory there is a separate npm
package, with its own license and its own notices.

| Plugin | License |
|---|---|
| `plugins/roc-ray/` | UPL-1.0, © 2024 Luke Boswell and subsequent authors |
| `plugins/joy/` | Apache-2.0, © 2024 Niclas Åhdén |
| `plugins/weaver/` | Vendors source that upstream has not licensed yet. See [`plugins/weaver/LICENSE`](plugins/weaver/LICENSE) and [`LICENSES/LicenseRef-weaver-no-license.txt`](LICENSES/LicenseRef-weaver-no-license.txt) |

This package does not bundle its two runtime dependencies,
`@modelcontextprotocol/server` and `zod`. Your package manager installs them,
and their notices ship in their own tarballs.
