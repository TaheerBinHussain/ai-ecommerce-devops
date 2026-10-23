#!/usr/bin/env bash
# Installs the monitoring stack into the current Kubernetes context and loads the
# platform's alert rules and Grafana dashboard.
#   scripts/k8s-observability.sh install | uninstall | open
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require kubectl helm

MON_NS=monitoring

install() {
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update prometheus-community >/dev/null

  local password
  password="$(kubectl -n "$MON_NS" get secret monitoring-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || true)"
  [[ -n "$password" ]] || password="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"

  log "Installing kube-prometheus-stack into namespace $MON_NS"
  helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
    --version 62.7.0 --namespace "$MON_NS" --create-namespace \
    -f "$ROOT_DIR/monitoring/prometheus/kube-prometheus-values.yaml" \
    --set grafana.adminPassword="$password" --wait --timeout 10m

  log "Loading NEXVION alert rules as a PrometheusRule"
  python3 -I - "$ROOT_DIR/monitoring/prometheus/alert.rules.yml" <<'PY' | kubectl apply -f -
import json, sys
groups = open(sys.argv[1]).read()
print(json.dumps({"apiVersion": "monitoring.coreos.com/v1", "kind": "PrometheusRule",
                  "metadata": {"name": "nexvion-alerts", "namespace": "monitoring"},
                  "spec": {"groups": __import__("yaml").safe_load(groups)["groups"]}}))
PY

  log "Loading Grafana dashboard"
  kubectl -n "$MON_NS" create configmap nexvion-dashboard \
    --from-file="$ROOT_DIR/monitoring/grafana/dashboards/nexvion-overview.json" \
    --dry-run=client -o yaml | kubectl label --local -f - grafana_dashboard=1 -o yaml | kubectl apply -f -

  ok "Monitoring installed. Grafana admin password: $password"
  echo "    Open Grafana:    scripts/k8s-observability.sh open   (http://localhost:3001)"
}

case "${1:-install}" in
  install) install ;;
  uninstall) helm -n "$MON_NS" uninstall monitoring; kubectl delete ns "$MON_NS" ;;
  open)
    log "Grafana on http://localhost:3001 and Prometheus on http://localhost:9091 (Ctrl+C to stop)"
    kubectl -n "$MON_NS" port-forward svc/monitoring-grafana 3001:80 &
    kubectl -n "$MON_NS" port-forward svc/monitoring-kube-prometheus-prometheus 9091:9090
    ;;
  *) die "usage: $0 install|uninstall|open" ;;
esac
