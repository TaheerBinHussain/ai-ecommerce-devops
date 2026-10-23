#!/usr/bin/env bash
# Reclaims disk space and removes environments.
#   scripts/cleanup.sh            remove dangling images, build output, logs older than 7 days
#   scripts/cleanup.sh --all      also tear down compose stack + volumes and the kind cluster
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "Removing build artifacts"
rm -rf "$ROOT_DIR/application/dist" "$ROOT_DIR"/application/*.tgz

log "Pruning dangling Docker images and build cache"
docker image prune -f >/dev/null
docker builder prune -f >/dev/null 2>&1 || true

log "Removing exported logs/reports older than 7 days"
find "$ROOT_DIR/logs" "$ROOT_DIR/security/reports" -type f -mtime +7 -delete 2>/dev/null || true

if [[ "${1:-}" == "--all" ]]; then
  warn "Tearing down compose stack (including data volumes)"
  compose --profile monitoring --profile logging down -v --remove-orphans || true
  if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
    "$ROOT_DIR/scripts/kind-cluster.sh" delete
  fi
fi

ok "Cleanup complete. Disk usage:"; docker system df
