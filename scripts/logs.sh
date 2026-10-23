#!/usr/bin/env bash
# Log management for the storefront.
#   scripts/logs.sh tail    [compose|k8s]      follow live logs
#   scripts/logs.sh export  [compose|k8s]      save logs to logs/<timestamp>.log (gzips older exports)
#   scripts/logs.sh errors  [compose|k8s]      show only 4xx/5xx and nginx errors
#   scripts/logs.sh analyze [compose|k8s]      export + run AI incident analysis on the logs
set -euo pipefail
source "$(dirname "$0")/lib.sh"

action="${1:-tail}"; target="${2:-compose}"
mkdir -p "$ROOT_DIR/logs"

fetch() {
  local follow="${1:-}"
  if [[ "$target" == "k8s" ]]; then
    kubectl -n "$NAMESPACE" logs -l "app.kubernetes.io/instance=$RELEASE" --all-containers --prefix --tail=2000 $follow
  else
    docker logs $follow --tail 2000 nexvion-store 2>&1
  fi
}

case "$action" in
  tail) fetch -f ;;
  export)
    file="$ROOT_DIR/logs/nexvion-$(date +%Y%m%d-%H%M%S).log"
    fetch > "$file"
    find "$ROOT_DIR/logs" -name '*.log' ! -newer "$file" ! -samefile "$file" -exec gzip -f {} \;
    ok "Exported $(wc -l < "$file") lines to $file"
    ;;
  errors) fetch | grep -E '"status":(4|5)[0-9]{2}|\[(error|crit|alert|emerg)\]|Error|ERROR' || ok "No errors found" ;;
  analyze)
    file="$ROOT_DIR/logs/nexvion-$(date +%Y%m%d-%H%M%S).log"
    fetch > "$file"
    python3 -I "$ROOT_DIR/ai/incident-analysis/analyze.py" "$file" --output "$ROOT_DIR/logs/incident-report.md"
    ;;
  *) die "usage: $0 tail|export|errors|analyze [compose|k8s]" ;;
esac
