#!/usr/bin/env bash
# Backs up platform configuration and observability data.
#   scripts/backup.sh [--keep N]
# Creates backups/<timestamp>/ with: repo config, docker volumes (Grafana, Prometheus),
# Kubernetes release state (if a cluster is reachable). Keeps the newest N (default 7).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

keep=7
[[ "${1:-}" == "--keep" ]] && keep="$2"
stamp="$(date +%Y%m%d-%H%M%S)"
dest="$ROOT_DIR/backups/$stamp"
mkdir -p "$dest"

log "Backing up configuration"
tar -czf "$dest/config.tar.gz" -C "$ROOT_DIR" \
  --exclude='node_modules' --exclude='dist' --exclude='.terraform' \
  docker monitoring logging kubernetes helm ansible terraform
[[ -f "$ENV_FILE" ]] && install -m 600 "$ENV_FILE" "$dest/docker.env"

for volume in nexvion_grafana-data nexvion_prometheus-data; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    log "Backing up docker volume $volume"
    docker run --rm -v "$volume:/data:ro" -v "$dest:/backup" alpine:3.20 \
      tar -czf "/backup/$volume.tar.gz" -C /data .
  fi
done

if command -v kubectl >/dev/null && kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
  log "Exporting Kubernetes state for namespace $NAMESPACE"
  kubectl -n "$NAMESPACE" get deploy,svc,ingress,configmap,hpa -o yaml > "$dest/k8s-$NAMESPACE.yaml"
  helm -n "$NAMESPACE" get values "$RELEASE" -o yaml > "$dest/helm-values.yaml" 2>/dev/null || true
fi

sha256sum "$dest"/* > "$dest/SHA256SUMS"
ok "Backup written to $dest ($(du -sh "$dest" | cut -f1))"

# Rotation: keep only the newest $keep backups
mapfile -t old < <(ls -1dt "$ROOT_DIR"/backups/*/ 2>/dev/null | tail -n +$((keep + 1)))
for dir in "${old[@]}"; do rm -rf "$dir"; log "Removed old backup $dir"; done
