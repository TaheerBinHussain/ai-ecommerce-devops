#!/usr/bin/env bash
# Verifies a deployment from the outside, the way a customer would reach it.
#   scripts/health-check.sh [BASE_URL] [--retries N]
# Exit code 0 = healthy, 1 = unhealthy (used by Jenkins to gate/rollback releases).
set -uo pipefail
source "$(dirname "$0")/lib.sh"

base_url="${1:-http://localhost:8082}"; retries=10
[[ "${2:-}" == "--retries" ]] && retries="${3:-10}"

checks=(
  "/health|200|\"status\":\"UP\""
  "/|200|NEXVION"
  "/products.html|200|"
  "/payment.html|200|"
  "/version.json|200|nexvion-store"
)

log "Waiting for $base_url/health"
for ((i = 1; i <= retries; i++)); do
  curl -sf -o /dev/null --max-time 5 "$base_url/health" && break
  [[ $i -eq $retries ]] && die "$base_url/health not reachable after $retries attempts"
  sleep 3
done

failed=0
for check in "${checks[@]}"; do
  IFS='|' read -r path expected_code expected_body <<<"$check"
  body="$(curl -s --max-time 5 -w '\n%{http_code} %{time_total}' "$base_url$path")"
  read -r code seconds <<<"$(tail -n1 <<<"$body")"
  if [[ "$code" != "$expected_code" ]]; then
    warn "$path -> HTTP $code (expected $expected_code)"; failed=$((failed + 1))
  elif [[ -n "$expected_body" ]] && ! grep -q "$expected_body" <<<"$body"; then
    warn "$path -> HTTP $code but body missing '$expected_body'"; failed=$((failed + 1))
  else
    ok "$path -> HTTP $code in ${seconds}s"
  fi
done

if [[ $failed -gt 0 ]]; then
  die "$failed health check(s) failed for $base_url"
fi
ok "All health checks passed for $base_url"
