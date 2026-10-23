#!/usr/bin/env bash
# Shared helpers sourced by every operational script.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
ENV_FILE="$ROOT_DIR/docker/.env"
NAMESPACE="${NAMESPACE:-ecommerce}"
RELEASE="${RELEASE:-nexvion}"
KIND_CLUSTER="${KIND_CLUSTER:-nexvion}"
REGISTRY="${REGISTRY:-localhost:5001}"
IMAGE_NAME="${IMAGE_NAME:-nexvion-store}"

if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

log()  { echo "${C_BLUE}[$(date '+%H:%M:%S')]${C_RESET} $*"; }
ok()   { echo "${C_GREEN}[ OK ]${C_RESET} $*"; }
warn() { echo "${C_YELLOW}[WARN]${C_RESET} $*" >&2; }
die()  { echo "${C_RED}[FAIL]${C_RESET} $*" >&2; exit 1; }

require() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required but not installed (run scripts/setup.sh)"
  done
}

# Supports both the Compose v2 plugin and the standalone docker-compose binary.
compose() {
  local args=(-f "$COMPOSE_FILE")
  [[ -f "$ENV_FILE" ]] && args+=(--env-file "$ENV_FILE")
  if docker compose version >/dev/null 2>&1; then
    docker compose "${args[@]}" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "${args[@]}" "$@"
  else
    die "Docker Compose is not installed"
  fi
}

git_sha() { git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "local"; }
