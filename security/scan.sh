#!/usr/bin/env bash
# DevSecOps scans, run in containers so no local installation is needed.
#   security/scan.sh secrets          Gitleaks - hard-coded secrets in the repository
#   security/scan.sh deps             Trivy fs - vulnerable dependencies (package-lock.json)
#   security/scan.sh config           Trivy config - Dockerfile/Kubernetes/Helm/Terraform misconfigurations
#   security/scan.sh image IMAGE      Trivy image - OS + library CVEs in the built image
#   security/scan.sh all IMAGE        everything above
# Reports are written to security/reports/. Exit code 1 when a gate fails.
# Gate: any secret, or any CRITICAL vulnerability with a fix available (SEVERITY_GATE to change).
#
# The repository is streamed into a Docker named volume (scripts/ci-volume.sh) instead of being
# bind-mounted, so the scans also work where Docker cannot mount the workspace path
# (snap-confined Docker + Jenkins workspace under /var/lib/jenkins, remote/DinD agents).
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORTS="$ROOT_DIR/security/reports"
TRIVY_IMAGE="aquasec/trivy:0.56.2"
GITLEAKS_IMAGE="zricethezav/gitleaks:v8.21.2"
SEVERITY_GATE="${SEVERITY_GATE:-CRITICAL}"
VOL="nexvion-scan-$$"
mkdir -p "$REPORTS"

"$ROOT_DIR/scripts/ci-volume.sh" sync "$VOL"
"$ROOT_DIR/scripts/ci-volume.sh" run "$VOL" alpine:3.20 . mkdir -p /ws/security/reports
cleanup() {
  "$ROOT_DIR/scripts/ci-volume.sh" fetch "$VOL" security/reports "$ROOT_DIR" 2>/dev/null || true
  "$ROOT_DIR/scripts/ci-volume.sh" rm "$VOL" 2>/dev/null || true
}
trap cleanup EXIT

trivy() {
  docker run --rm -v "$VOL:/src" -v trivy-cache:/root/.cache/ \
    -v /var/run/docker.sock:/var/run/docker.sock "$TRIVY_IMAGE" "$@"
}

secrets() {
  echo "== Secret detection (Gitleaks)"
  docker run --rm -v "$VOL:/src" "$GITLEAKS_IMAGE" \
    detect --source /src --no-git --config /src/security/gitleaks.toml \
    --report-format json --report-path /src/security/reports/gitleaks.json --redact --no-banner
}

deps() {
  echo "== Dependency scan (Trivy fs)"
  trivy fs --no-progress --scanners vuln --include-dev-deps --format table --output /src/security/reports/trivy-deps.txt /src/application &&
  trivy fs --no-progress --scanners vuln --severity "$SEVERITY_GATE" --ignore-unfixed --exit-code 1 --quiet /src/application
}

config() {
  echo "== Misconfiguration scan (Trivy config)"
  trivy config --quiet --skip-check-update --format table --output /src/security/reports/trivy-config.txt \
    --skip-dirs "security/reports" --severity HIGH,CRITICAL /src
  "$ROOT_DIR/scripts/ci-volume.sh" run "$VOL" alpine:3.20 . \
    grep -E "^(Tests|Failures):|^[A-Za-z0-9/._-]+ \(" /ws/security/reports/trivy-config.txt || true
}

image() {
  local img="${1:?image name required}"
  echo "== Image scan (Trivy image) $img"
  trivy image --no-progress --format table --output /src/security/reports/trivy-image.txt "$img" &&
  trivy image --no-progress --format json --output /src/security/reports/trivy-image.json --quiet "$img" &&
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

[[ $status -eq 0 ]] && echo "Security gate PASSED (reports in security/reports/)" || echo "Security gate FAILED (see security/reports/)"
exit $status
