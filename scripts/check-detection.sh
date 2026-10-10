#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Heorhii Bulakh and subsequent roc-syntax-mcp authors
# SPDX-License-Identifier: MPL-2.0

# Acceptance test of platform detection with a real MCP client (Claude Code).
#
# src/detect_server.test.ts tests the resolution order with a hand-written stdio
# client. That test cannot show that Claude Code starts the server in the
# project directory of the user and answers `roots/list` with that directory.
# This script tests that. It costs model tokens, so `npm test` does not run it.
#
# Each case checks the line that the server logs to stderr, never the reply of
# the model.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! command -v claude >/dev/null; then
	echo "claude CLI not found. Skipping" >&2
	exit 0
fi

PLATFORM_URL_BASE="https://github.com/roc-lang/basic-webserver/releases/download"
TARBALL="AC9goxhsjJJdrQtnc2ga3eTiESyh6ZLraZJsCVdEfeZT.tar.zst"
CLI_URL_BASE="https://github.com/roc-lang/basic-cli/releases/download"
CLI_TARBALL="CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst"

# The wrapper writes the stderr of the server to $ROC_MCP_LOG. Without the
# wrapper, the claude CLI writes that stderr into its own debug log.
cat > "$WORK/server.sh" <<EOF
#!/usr/bin/env bash
exec node --import "$(cd "$ROOT" && node -e 'process.stdout.write(import.meta.resolve("tsx/esm"))')" \\
	"$ROOT/src/index.ts" 2>> "\$ROC_MCP_LOG"
EOF
chmod +x "$WORK/server.sh"

cat > "$WORK/mcp.json" <<EOF
{ "mcpServers": { "roc-syntax": { "command": "$WORK/server.sh", "args": [] } } }
EOF

app_header() {
	printf 'app [Context, program] {\n\tpf: platform "%s/%s/%s",\n}\n\nimport pf.Server\n\nContext : {}\n' \
		"$PLATFORM_URL_BASE" "$1" "$TARBALL"
}

# The same header with one more package pinned beside the platform.
app_header_with_pin() {
	printf 'app [Context, program] {\n\tpf: platform "%s/%s/%s",\n\t%s\n}\n\nimport pf.Server\n\nContext : {}\n' \
		"$PLATFORM_URL_BASE" "$1" "$TARBALL" "$2"
}

cli_app_header() {
	printf 'app [main!] { pf: platform "%s/%s/%s" }\n\nimport pf.Stdout\n' \
		"$CLI_URL_BASE" "$1" "$CLI_TARBALL"
}

pass=0
fail=0

# $1 name, $2 launch directory, $3 expected stderr pattern
run_case() {
	local name="$1" dir="$2" expect="$3"
	local log="$WORK/$name.log"
	: > "$log"
	( cd "$dir" && ROC_MCP_LOG="$log" claude -p \
		"Call the roc-syntax tool list_roc_index with kind=scopes. Reply with just OK." \
		--mcp-config "$WORK/mcp.json" \
		--allowedTools "mcp__roc-syntax__list_roc_index" >/dev/null 2>&1 )
	if grep -qE "$expect" "$log"; then
		echo "PASS $name"
		pass=$((pass + 1))
	else
		echo "FAIL $name: expected /$expect/, log held:"
		sed 's/^/      /' "$log"
		fail=$((fail + 1))
	fi
}

# 1. An app in the launch directory that pins an older release than the bundled one.
mkdir -p "$WORK/pinned/.git"
app_header 0.15.0 > "$WORK/pinned/main.roc"
run_case pinned "$WORK/pinned" "Detected basic-webserver 0\.15\.0 from main\.roc"

# 2. The server starts in a subdirectory. Detection finds the app only if it
# searches the parent directories.
mkdir -p "$WORK/nested/.git" "$WORK/nested/src"
app_header 0.17.0 > "$WORK/nested/main.roc"
printf 'module [x]\n\nx = 1\n' > "$WORK/nested/src/helper.roc"
run_case nested "$WORK/nested/src" "Detected basic-webserver 0\.17\.0"

# 3. No app header anywhere, so the working set is only language and builtin.
mkdir -p "$WORK/plain/.git"
printf 'module [x]\n\nx = 1\n' > "$WORK/plain/lib.roc"
run_case plain "$WORK/plain" "No platform detected"

# 4. A second platform. Detection selects the corpus as well as the version, so
# this case checks that it selects basic-cli and not basic-webserver.
mkdir -p "$WORK/cli/.git"
cli_app_header 0.25.0 > "$WORK/cli/main.roc"
run_case cli "$WORK/cli" "Detected basic-cli 0\.25\.0 from main\.roc"

# 5. A package that the app pins and the active platform does not declare. The
# app header decides the namespaces, so the server must report the extra
# package through a real client, marked as having no provider.
mkdir -p "$WORK/apppin/.git"
app_header_with_pin 0.17.0 \
	'json: "https://github.com/example/json/releases/download/2.1.0/AAAA.tar.br",' \
	> "$WORK/apppin/main.roc"
run_case apppin "$WORK/apppin" "Also pinned: example/json 2\.1\.0 \(no provider\)"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
