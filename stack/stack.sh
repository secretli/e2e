#!/usr/bin/env bash
# Starts or stops the stack (see compose.yml) and waits until the gateway
# answers for both the web app and the API.
#
#   stack.sh up     fetch the latest published images, start everything, wait
#   stack.sh down   stop everything and drop the data
#   stack.sh logs   print every service's logs
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
compose=(docker compose -f "$here/compose.yml")

case "${1:-}" in
  up)
    # Images built locally (WEB_IMAGE, SERVER_IMAGE) are not on a registry;
    # only the published ones are refreshed.
    "${compose[@]}" pull --quiet --ignore-pull-failures 2> /dev/null || true
    "${compose[@]}" up -d
    for _ in $(seq 1 90); do
      if curl -fsS http://localhost:8080/api/v1/health/ready > /dev/null 2>&1 &&
         curl -fsS http://localhost:8080/ > /dev/null 2>&1; then
        echo "Secretli is up at http://localhost:8080"
        exit 0
      fi
      sleep 1
    done
    "${compose[@]}" ps
    "${compose[@]}" logs
    exit 1
    ;;
  down)
    "${compose[@]}" down -v
    ;;
  logs)
    "${compose[@]}" logs
    ;;
  *)
    echo "usage: $0 up|down|logs" >&2
    exit 2
    ;;
esac
