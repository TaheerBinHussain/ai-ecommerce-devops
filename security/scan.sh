#!/usr/bin/env bash
# DevSecOps scans, run in containers so no local installation is needed.
#   security/scan.sh secrets          Gitleaks - hard-coded secrets in the repository
#   security/scan.sh deps             Trivy fs - vulnerable dependencies (package-lock.json)
#   security/scan.sh config           Trivy config - Dockerfile/Kubernetes/Helm/Terraform misconfigurations
#   security/scan.sh image IMAGE      Trivy image - OS + library CVEs in the built image
#   security/scan.sh all IMAGE        everything above
# Reports are written to security/reports/. Exit code 1 when a gate fails.
# Gate: any secret, or any CRITICAL vulnerability with a fix available (SEVERITY_GATE to change).
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORTS="$ROOT_DIR/security/reports"
TRIVY_IMAGE="aquasec/trivy:0.56.2"
GITLEAKS_IMAGE="zricethezav/gitleaks:v8.21.2"
SEVERITY_GATE="${SEVERITY_GATE:-CRITICAL}"
mkdir -p "$REPORTS"

trivy() {
  docker run --rm -v "$ROOT_DIR:/src:ro" -v "$REPORTS:/reports" \
    -v trivy-cache:/root/.cache/ -v /var/run/docker.sock:/var/run/docker.sock \
    "$TRIVY_IMAGE" "$@"
}

secrets() {
  echo "== Secret detection (Gitleaks)"
  docker run --rm -v "$ROOT_DIR:/src:ro" -v "$REPORTS:/reports" "$GITLEAKS_IMAGE" \
    detect --source /src --no-git --config /src/security/gitleaks.toml \
    --report-format json --report-path /reports/gitleaks.json --redact --no-banner
}

deps() {
  echo "== Dependency scan (Trivy fs)"
  trivy fs --no-progress --scanners vuln --include-dev-deps --format table --output /reports/trivy-deps.txt /src/application &&
  trivy fs --no-progress --scanners vuln --severity "$SEVERITY_GATE" --ignore-unfixed --exit-code 1 --quiet /src/application
}

config() {
  echo "== Misconfiguration scan (Trivy config)"
  trivy config --quiet --skip-check-update --format table --output /reports/trivy-config.txt \
    --skip-dirs "**/node_modules" --skip-dirs "**/.terraform" --severity HIGH,CRITICAL /src
  grep -E "^(Tests|Failures):|^[A-Za-z0-9/._-]+ \(" "$REPORTS/trivy-config.txt" || true
}

image() {
  local img="${1:?image name required}"
  echo "== Image scan (Trivy image) $img"
  trivy image --no-progress --format table --output /reports/trivy-image.txt "$img" &&
  trivy image --no-progress --format json --output /reports/trivy-image.json --quiet "$img" &&
  trivy image --no-progress --severity "$SEVERITY_GATE" --ignore-unfixed --exit-code 1 --quiet "$img"
}

status=0
case "${1:-all}" in
  secrets) secrets || status=1 ;;
  deps)    deps || status=1 ;;
  config)  config ;;   # informational: findings are reviewed, not a hard gate
  image)   image "${2:-}" || status=1 ;;
  all)
    secrets || status=1
    deps || status=1
    config
    [[ -n "${2:-}" ]] && { image "$2" || status=1; }
    ;;
  *) echo "usage: $0 secrets|deps|config|image IMAGE|all [IMAGE]"; exit 2 ;;
esac

# Scanners run as root inside their containers: hand report ownership back to the caller (e.g. jenkins)
docker run --rm -v "$REPORTS:/r" alpine:3.20 chown -R "$(id -u):$(id -g)" /r >/dev/null 2>&1 || true

[[ $status -eq 0 ]] && echo "Security gate PASSED (reports in security/reports/)" || echo "Security gate FAILED (see security/reports/)"
exit $status
