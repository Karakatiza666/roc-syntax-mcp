Ship a Roc package: the compiler pin, the bundle, the bundle test, CI,
releases, docs and compiler updates. The conventions come from
ageron/roc-package-template (7113ff2) and roc-lang/release-package (af2f0cd),
with `src/` in place of `package/` (see `write_package`, which has the
package files). Tested with nightly-2026-10-09-258ab27.

### Checklist

| # | Step | Section |
|---|---|---|
| 1 | Pin one nightly. Install it with setup-roc in each workflow | `.roc-version`, `.github/actions/setup-roc/action.yml` |
| 2 | Bundle and list the files | `scripts/bundle.sh` |
| 3 | Run the examples against the bundle | `scripts/test_bundle.sh` |
| 4 | CI on 5 runners, one bundle for all | `.github/workflows/tests.yaml` |
| 5 | Version rules and `roc bump` | Versions |
| 6 | Release by hand, with release-package | `release.yml` |
| 7 | Docs on GitHub Pages | Docs |
| 8 | Weekly compiler-update PR | `update-roc.yml` |
| 9 | Repo settings | Repo settings |

### .roc-version

`.roc-version`
```text
nightly-2026-10-09-258ab27
```

`.roc-version` holds a tag of roc-lang/nightlies.

### .github/actions/setup-roc/action.yml

`.github/actions/setup-roc/action.yml`
```yaml
name: Set up Roc
description: Install the pinned Roc nightly
inputs:
  nightly-tag:
    description: Override .roc-version when testing a compiler update
    required: false
    default: ""
runs:
  using: composite
  steps:
    - name: Read Roc version
      id: version
      shell: bash
      env:
        OVERRIDE: ${{ inputs.nightly-tag }}
      run: |
        set -euo pipefail
        tag="${OVERRIDE:-$(tr -d '\r\n' < .roc-version)}"
        if [[ ! "$tag" =~ ^nightly-[0-9]{4}-([A-Za-z]+|[0-9]{2})-[0-9]{2}-[0-9a-f]{7,40}$ ]]; then
          echo "Invalid Roc nightly tag: $tag" >&2
          exit 1
        fi
        echo "tag=$tag" >> "$GITHUB_OUTPUT"
    - name: Install Roc
      uses: roc-lang/setup-roc@f5a74bf90aa694b43ab4a7cbfdb19273bc6aa697
      with:
        version: nightly-new-compiler
        nightly-tag: ${{ steps.version.outputs.tag }}
    - shell: bash
      run: roc version
```

- `nightly-new-compiler` is the Zig compiler. `nightly` and `alpha*-rolling`
  install the old Rust compiler (other syntax, `.tar.br` bundles, no Windows).
- Pin roc-lang actions by commit SHA.

### scripts/bundle.sh

`scripts/bundle.sh`
```sh
#!/usr/bin/env bash
# Writes dist/<hash>.tar.zst and lists its files.
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."

rm -rf dist
mkdir dist
"$ROC" bundle src/main.roc --output-dir dist
zstd -dc dist/*.tar.zst | tar -t
```

- `roc bundle` follows the imports of main.roc and puts main.roc at the
  archive root. It prints `Created: dist/<hash>.tar.zst`. The file name is the
  content hash. `--output-dir` must exist.
- A module that no module imports is not bundled. Do not pass a file list.
- An extra file (LICENSE) must be inside `src/`. Otherwise the error is
  "outside the entry point directory".

### scripts/test_bundle.sh

`scripts/test_bundle.sh`
```sh
#!/usr/bin/env bash
# Runs the examples against a bundle: a .tar.zst file (default dist/*.tar.zst)
# served on localhost, or a release URL. A path is from the repo root.
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."
target="${1:-$(echo dist/*.tar.zst)}"

if [[ $target == https://* ]]; then
	url="$target"
else
	port="${PORT:-8765}"
	url="http://localhost:$port/$(basename "$target")"
	python3 -m http.server "$port" --bind 127.0.0.1 --directory "$(dirname "$target")" >/dev/null 2>&1 &
	server=$!
	trap 'kill "$server"' EXIT
	sleep 1
fi
for f in examples/*.roc; do
	"$ROC" check "$f" --replace-dep ./src/main.roc "$url"
	"$ROC" "$f" --replace-dep ./src/main.roc "$url"
done
```

- A path dependency does not test the bundle. Plain http is allowed only for
  localhost.
- `--replace-dep OLD NEW` changes no file. OLD is the path from the current
  directory, with `./`. Do not copy or rewrite the examples.
- `roc test` does not run the `expect`s of a URL package. `all_tests.sh` runs
  them on the source.

### .github/workflows/tests.yaml

Every workflow sets `permissions: {}` at the top and gives each job only the
permissions that it needs.

`.github/workflows/tests.yaml`
```yaml
name: Tests
on:
  push:
  pull_request:
  workflow_dispatch:
  workflow_call:
    inputs:
      roc-nightly: { required: false, type: string, default: "" }
permissions: {}
concurrency:
  group: tests-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  bundle:
    runs-on: ubuntu-24.04
    permissions: { contents: read }
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-roc
        with: { nightly-tag: "${{ inputs.roc-nightly || '' }}" }
      - run: scripts/bundle.sh
      - uses: actions/upload-artifact@v4
        with: { name: bundle, path: dist, if-no-files-found: error }
  test:
    needs: bundle
    runs-on: ${{ matrix.os }}
    permissions: { contents: read }
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-24.04, ubuntu-24.04-arm, macos-26, macos-26-intel, windows-2025]
    defaults: { run: { shell: bash } }
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-roc
        with: { nightly-tag: "${{ inputs.roc-nightly || '' }}" }
      - run: scripts/all_tests.sh
      - uses: actions/download-artifact@v4
        with: { name: bundle, path: dist }
      - run: scripts/test_bundle.sh
```

The `bundle` job runs once on Linux. Each runner tests that same file.

### Versions

Tags are semver with no `v`: `0.1.0`, `1.2.0-rc.1`. release-package rejects
`v1.2.3`, `1.2`, `0.0.0` and `+build`. The version is a segment of the URL,
and Roc uses it to pick one version (`packages`). Start at `0.1.0`. Below
1.0.0, a breaking change bumps the minor number.

```sh
roc bump src/main.roc --old <previous release URL> --expect 0.3.0
```

`roc bump` compares the public API and reports MAJOR, MINOR or PATCH. `--old`
also takes a `.tar.zst`, a directory or a main.roc (then add
`--old-version X.Y.Z`). The old release must compile with the pinned nightly.

### release.yml

Start from the template file. The workflow starts by hand
(`workflow_dispatch`, input `release_version`), and runs as a dry run on each
pull request. Each
release-package step is `roc-lang/release-package/actions/<name>@<sha>`. Use
the scripts above in place of the template Python scripts:

| Job | Steps |
|---|---|
| build-bundle | checkout, setup-roc, require a branch, validate-release, `scripts/all_tests.sh`, resolve-previous-release, run-bump-check (`bump_entrypoint: src/main.roc`, `warn` for the first release, else `require`), `scripts/bundle.sh`, prepare-bundles, upload the bundle and `generated-docs` |
| test-bundle | test-bundle on the 5 runners, `test_bundle_command: scripts/test_bundle.sh` (it gets the bundle path as its last argument) |
| create-release | make-release-notes, add "Built with Roc <nightly>" and the `pkg: "<url>"` line, publish-release (`additional_assets: dist/package-docs.tar.gz`) |
| publish-docs | calls `generate-docs.yaml`, for a stable release only |
| test-published | `scripts/test_bundle.sh "$BUNDLE_URL"` on the 5 runners |
| readme-pull-request | put the new URL in README.md, then create-followup-pr with `paths: README.md` |

Keep the template `concurrency` block, so that only one release runs at a
time. Users copy this URL into their headers:

```text
https://github.com/<owner>/<repo>/releases/download/0.1.0/<hash>.tar.zst
```

The release notes and README.md hold it. Examples keep `../src/main.roc`, so
`--replace-dep` always finds them. Write no CHANGELOG. The release notes are
the history.

### Docs

```sh
roc docs src/main.roc                      # writes ./generated-docs
roc docs src/main.roc --output=site --serve
```

- Each public module gets a page from its `##` comments. Links are relative,
  so the site works under `/<repo>/` on Pages. A `sed` on `href`, or
  `ROC_DOCS_URL_ROOT`, is for the old compiler.
- The title is the name of the directory of main.roc ("src Docs") when the package has 2
  or more public modules. Change the title after `roc docs`:
  `find generated-docs -name '*.html' -exec sed -i 's|<title>src Docs</title>|<title>my-pkg Docs</title>|' {} +`
- The release attaches the docs of the release commit as
  `package-docs.tar.gz`. `generate-docs.yaml` deploys that archive with
  upload-pages-artifact and deploy-pages. It runs on a release, by hand, or
  from release.yml. So the site shows the latest stable release. A prerelease
  does not replace it.
- For one site per version (`www/<version>/`), release-package has
  docs-snapshot, docs-index and docs-validate.

### update-roc.yml

Copy it from the template. It runs each Monday (`0 12 * * 1`) and by hand:

| Job | Does |
|---|---|
| candidate | newest tag from `gh release view --repo roc-lang/nightlies`. Stop if it equals `.roc-version` |
| test | calls `tests.yaml` with `roc-nightly: <tag>` |
| pull-request | writes the tag to `.roc-version` on `codex/update-roc-nightly`, then opens or edits one PR |

When a nightly breaks the package, fix the code in that PR.

### Repo settings

| Setting | Why |
|---|---|
| Pages source: GitHub Actions | `generate-docs.yaml` deploys the site |
| `github-pages` environment allows the release branches and tags | needed only with environment protection rules |
| Actions can create and approve pull requests | README and update PRs. The workflows do not merge them |

GITHUB_TOKEN is enough. A PR that GITHUB_TOKEN opens starts no
`pull_request` workflow, so the workflows test before they open the PR and
link that run. If branch protection requires PR checks, open the PRs with a
GitHub App token.
