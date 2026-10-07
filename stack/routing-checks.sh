#!/usr/bin/env bash
# Checks how a whole Secretli is put together, from the outside: one origin,
# where /api/ reaches the server and everything else the web app. The web
# image's own headers and caching are checked in secretli/web.
#
#   routing-checks.sh [base URL]   (default http://localhost:8080)
set -euo pipefail

BASE="${1:-http://localhost:8080}"
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

curl -fsS "$BASE/api/v1/health/ready" > /dev/null || fail "the server is not ready behind $BASE"
version="$(curl -fsS "$BASE/api/v1/version")"
[[ "$version" == *'"version"'* ]] || fail "the API answers through the gateway: $version"
pass "/api/ reaches the server ($version)"

# The server marks every answer with a request id; the web app's nginx does
# not. An unknown API path must come from the server, not the app's index.
headers="$(curl -sS -D - -o /dev/null "$BASE/api/v1/no-such-endpoint" | tr -d '\r')"
[[ "$(echo "$headers" | head -1)" == *' 404'* ]] || fail "an unknown API path should be a 404: $(echo "$headers" | head -1)"
grep -i '^x-request-id:' <<< "$headers" > /dev/null || fail "an unknown API path should be answered by the server"
pass "unknown API paths are the server's 404s"

for path in / /s /c /share; do
  [[ "$(curl -fsS "$BASE$path")" == *'<div id="root">'* ]] || fail "$path should serve the web app"
done
pass "everything else is the web app"

echo "all routing checks passed against $BASE"
