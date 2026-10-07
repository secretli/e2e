#!/usr/bin/env bash
# Checks a deployed Secretli from the outside, after a deploy or on a
# schedule.
#
#   SMOKE_URL             the Secretli to check (default https://secretli.app)
#   SMOKE_CREATE_SECRETS  1 also shares and opens a secret that expires after
#                         five minutes, and hands a link over with a code;
#                         off unless set, since it writes to the server
#   SECRETLI_CLI          the secretli binary, for SMOKE_CREATE_SECRETS
set -euo pipefail

URL="${SMOKE_URL:-https://secretli.app}"
here="$(cd "$(dirname "$0")" && pwd)"
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

"$here/../stack/routing-checks.sh" "$URL"

# DNS hands out every address of the name and a client takes whichever comes
# first, so each one is a way in of its own and must answer: the server and
# the web app, through that address. IPv4 only; GitHub's runners have no IPv6.
rest="${URL#*://}"
hostport="${rest%%/*}"
host="${hostport%%:*}"
port="${hostport#"$host"}"
port="${port#:}"
if [ -z "$port" ]; then
  if [ "${URL%%://*}" = https ]; then port=443; else port=80; fi
fi
addresses() {
  if command -v getent > /dev/null; then
    getent ahostsv4 "$1" | awk '{print $1}' | sort -u
  else
    dig +short A "$1" | grep -E '^[0-9.]+$' | sort -u || true
  fi
}
if [ "$host" = localhost ] || [[ "$host" =~ ^[0-9.]+$ ]]; then
  echo "skip  one address only: $host"
else
  count=0
  while read -r addr; do
    [ -n "$addr" ] || continue
    for path in /api/v1/health/ready /; do
      curl -fsS -o /dev/null --connect-timeout 10 --max-time 30 \
        --resolve "$host:$port:$addr" "$URL$path" || fail "$host at $addr does not answer $path"
    done
    count=$((count + 1))
  done < <(addresses "$host")
  [ "$count" -gt 0 ] || fail "$host has no IPv4 address"
  pass "each of the $count addresses of $host answers"
fi

if [ "${SMOKE_CREATE_SECRETS:-}" != 1 ]; then
  echo "smoke checks passed against $URL (no secrets created; set SMOKE_CREATE_SECRETS=1 for more)"
  exit 0
fi

CLI="${SECRETLI_CLI:-secretli}"
work="$(mktemp -d)"
trap 'kill $(jobs -p) 2> /dev/null || true; rm -rf "$work"' EXIT

text="smoke $(date -u +%Y-%m-%dT%H:%M:%SZ)"
link="$("$CLI" share --server "$URL" -e 5m -q -t "$text")"
[ "$("$CLI" open "$link" --yes 2> /dev/null)" = "$text" ] || fail "a shared secret does not open"
pass "a five-minute secret shares and opens"

text="smoke handover $(date -u +%Y-%m-%dT%H:%M:%SZ)"
link="$("$CLI" share --server "$URL" -e 5m -q -t "$text")"
"$CLI" send "$link" > "$work/code" 2> "$work/send.err" &
sender=$!
for _ in $(seq 1 100); do
  [ -s "$work/code" ] && break
  sleep 0.1
done
code="$(head -n 1 "$work/code")"
[ -n "$code" ] || fail "send printed no code: $(cat "$work/send.err")"
[ "$("$CLI" receive "$code" --server "$URL" --yes 2> /dev/null)" = "$text" ] || fail "the code did not hand the secret over"
wait "$sender" || fail "send did not finish: $(cat "$work/send.err")"
pass "a link is handed over with a code"

echo "smoke checks passed against $URL, secrets included"
