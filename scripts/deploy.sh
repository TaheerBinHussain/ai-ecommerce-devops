#!/usr/bin/env bash
# Deploys the NEXVION store.
#   scripts/deploy.sh compose [--with-monitoring] [--with-logging]   Docker Compose (local)
#   scripts/deploy.sh kind    [--tag TAG]                            build -> push to local registry -> Helm on kind
#   scripts/deploy.sh k8s     --image REPO --tag TAG [--values FILE] Helm on the current kube-context (e.g. AWS k3s)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

target="${1:-compose}"; shift || true
tag="$(git_sha)"; image_repo=""; values=""; profiles=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-monitoring) profiles+=(--profile monitoring) ;;
    --with-logging)    profiles+=(--profile logging) ;;
    --tag)    tag="$2"; shift ;;
    --image)  image_repo="$2"; shift ;;
    --values) values="$2"; shift ;;
    *) die "unknown option $1" ;;
  esac
  shift
done

helm_deploy() {
  local repo="$1" extra=()
  [[ -n "$values" ]] && extra+=(-f "$values")
  # Roll back automatically if the release does not become healthy (flag renamed in Helm 4)
  if helm version --short | grep -q '^v3'; then extra+=(--atomic); else extra+=(--rollback-on-failure); fi
  # Namespace with Pod Security "restricted" enforcement (Helm's --create-namespace adds no labels)
  sed "s/name: ecommerce/name: $NAMESPACE/" "$ROOT_DIR/kubernetes/namespace.yaml" | kubectl apply -f - >/dev/null
  log "Helm upgrade --install $RELEASE ($repo:$tag) into namespace $NAMESPACE"
  helm upgrade --install "$RELEASE" "$ROOT_DIR/helm/ecommerce" \
    --namespace "$NAMESPACE" --create-namespace \
    --set image.repository="$repo" --set image.tag="$tag" \
    "${extra[@]}" --wait --timeout 5m
  kubectl -n "$NAMESPACE" rollout status "deployment/$RELEASE-ecommerce" --timeout=120s
  ok "Release deployed"; helm -n "$NAMESPACE" history "$RELEASE" --max 5
}

case "$target" in
  compose)
    require docker
    [[ -f "$ENV_FILE" ]] || "$ROOT_DIR/scripts/setup.sh"
    log "Building and starting containers"
    GIT_COMMIT="$tag" compose "${profiles[@]}" up -d --build
    "$ROOT_DIR/scripts/health-check.sh" "http://localhost:$(grep -E '^APP_PORT=' "$ENV_FILE" | cut -d= -f2 || echo 8082)"
    compose "${profiles[@]}" ps
    ;;
  kind)
    require docker kind kubectl helm
    kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER" || "$ROOT_DIR/scripts/kind-cluster.sh" create
    kubectl config use-context "kind-$KIND_CLUSTER" >/dev/null
    log "Building image $REGISTRY/$IMAGE_NAME:$tag"
    docker build -f "$ROOT_DIR/docker/Dockerfile" --build-arg GIT_COMMIT="$tag" \
      -t "$REGISTRY/$IMAGE_NAME:$tag" "$ROOT_DIR"
    docker push "$REGISTRY/$IMAGE_NAME:$tag"
    values="${values:-$ROOT_DIR/helm/ecommerce/values-kind.yaml}"
    helm_deploy "$REGISTRY/$IMAGE_NAME"
    "$ROOT_DIR/scripts/health-check.sh" "http://nexvion.localtest.me:8088"
    ;;
  k8s)
    require kubectl helm
    [[ -n "$image_repo" ]] || die "--image is required for k8s deployments"
    helm_deploy "$image_repo"
    ;;
  *) die "unknown target '$target' (compose|kind|k8s)" ;;
esac
