#!/usr/bin/env bash
# Local Kubernetes for development: kind cluster + local image registry + ingress-nginx.
#   scripts/kind-cluster.sh create | delete | status
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require docker kind kubectl

REG_NAME="kind-registry"
REG_PORT="5001"
# Dedicated docker network so this cluster never interferes with other kind clusters
export KIND_EXPERIMENTAL_DOCKER_NETWORK="${KIND_EXPERIMENTAL_DOCKER_NETWORK:-nexvion-kind}"

create_registry() {
  if [[ "$(docker inspect -f '{{.State.Running}}' "$REG_NAME" 2>/dev/null || true)" != "true" ]]; then
    log "Starting local registry localhost:$REG_PORT"
    docker run -d --restart=always -p "127.0.0.1:$REG_PORT:5000" --network bridge --name "$REG_NAME" registry:2 >/dev/null
  fi
  ok "Registry running on localhost:$REG_PORT"
}

create_cluster() {
  if kind get clusters | grep -qx "$KIND_CLUSTER"; then
    ok "kind cluster '$KIND_CLUSTER' already exists"
  else
    log "Creating kind cluster '$KIND_CLUSTER'"
    kind create cluster --name "$KIND_CLUSTER" --config "$ROOT_DIR/kubernetes/kind-config.yaml" --wait 120s
  fi
  kubectl config use-context "kind-$KIND_CLUSTER" >/dev/null

  # Let cluster nodes pull localhost:5001/* from the registry container
  for node in $(kind get nodes --name "$KIND_CLUSTER"); do
    docker exec "$node" mkdir -p "/etc/containerd/certs.d/localhost:$REG_PORT"
    printf '[host."http://%s:5000"]\n' "$REG_NAME" | docker exec -i "$node" cp /dev/stdin "/etc/containerd/certs.d/localhost:$REG_PORT/hosts.toml"
  done
  docker network connect "$KIND_EXPERIMENTAL_DOCKER_NETWORK" "$REG_NAME" 2>/dev/null || true
  kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:$REG_PORT"
YAML

  log "Installing ingress-nginx"
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/kind/deploy.yaml >/dev/null
  kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s

  log "Installing metrics-server (needed by the HorizontalPodAutoscaler)"
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml >/dev/null
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null 2>&1 || true
  ok "Cluster ready: kubectl context kind-$KIND_CLUSTER, ingress on http://nexvion.localtest.me:8088"
}

case "${1:-create}" in
  create) create_registry; create_cluster ;;
  delete) kind delete cluster --name "$KIND_CLUSTER"; docker rm -f "$REG_NAME" >/dev/null 2>&1 || true; ok "Deleted" ;;
  status) kind get clusters; kubectl get nodes -o wide ;;
  *) die "usage: $0 create|delete|status" ;;
esac
