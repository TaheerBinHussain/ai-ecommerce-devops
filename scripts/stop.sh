#!/usr/bin/env bash
# Gracefully stops the application.
#   scripts/stop.sh compose      stop all compose services (data volumes kept)
#   scripts/stop.sh k8s          scale the deployment to zero (release kept)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

case "${1:-compose}" in
  compose)
    log "Stopping Docker Compose services"
    compose --profile monitoring --profile logging stop
    ok "Stopped (volumes preserved; use scripts/cleanup.sh to remove)"
    ;;
  k8s)
    require kubectl
    kubectl -n "$NAMESPACE" scale "deployment/$RELEASE-ecommerce" --replicas=0
    ok "Scaled $RELEASE-ecommerce to 0 replicas"
    ;;
  *) die "usage: $0 compose|k8s" ;;
esac
