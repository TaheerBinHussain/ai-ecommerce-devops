#!/usr/bin/env bash
# Prepares a Linux workstation/server for the platform:
# checks prerequisites, creates docker/.env, installs app dev dependencies.
#   scripts/setup.sh            check + configure
#   scripts/setup.sh --kind     also create the local kind cluster + registry
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "Checking prerequisites"
missing=0
for tool in git docker node npm kubectl helm kind terraform; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool found"
  else
    warn "$tool not found"; missing=$((missing + 1))
  fi
done
command -v ansible-playbook >/dev/null 2>&1 && ok "ansible found" || warn "ansible not found (pip install --user ansible-core)"
docker info >/dev/null 2>&1 || die "Docker daemon is not reachable for user $(whoami) (add the user to the 'docker' group)"
ok "Docker daemon reachable"

if [[ ! -f "$ENV_FILE" ]]; then
  log "Creating docker/.env from template"
  cp "$ROOT_DIR/docker/.env.example" "$ENV_FILE"
  password="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
  sed -i "s|^GRAFANA_ADMIN_PASSWORD=.*|GRAFANA_ADMIN_PASSWORD=$password|" "$ENV_FILE"
  docker_root="$(docker info --format '{{.DockerRootDir}}')"
  sed -i "s|^DOCKER_ROOT=.*|DOCKER_ROOT=$docker_root|" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  ok "docker/.env created (Grafana admin password generated, DOCKER_ROOT=$docker_root)"
else
  ok "docker/.env already exists"
fi

log "Installing application dev dependencies"
(cd "$ROOT_DIR/application" && npm ci --no-audit --no-fund >/dev/null)
ok "npm dependencies installed"

# Elasticsearch needs a higher mmap count
if [[ "$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)" -lt 262144 ]]; then
  warn "vm.max_map_count is low for Elasticsearch; run: sudo sysctl -w vm.max_map_count=262144"
fi

mkdir -p "$ROOT_DIR/backups" "$ROOT_DIR/logs"

if [[ "${1:-}" == "--kind" ]]; then
  "$ROOT_DIR/scripts/kind-cluster.sh" create
fi

[[ $missing -eq 0 ]] && ok "Environment ready" || warn "Environment ready with $missing missing optional tool(s)"
