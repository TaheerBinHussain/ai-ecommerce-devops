#!/usr/bin/env bash
# Runs containerised build/scan tools against the repository WITHOUT bind-mounting host paths.
# The workspace is streamed (tar) into a Docker named volume, tools run on the volume, and
# results are streamed back. Works with snap-confined Docker (which cannot mount /var/lib/...),
# remote Docker daemons and Docker-in-Docker agents.
#
#   scripts/ci-volume.sh sync  VOLUME                         copy the repo (no .git/node_modules) into VOLUME:/ws
#   scripts/ci-volume.sh run   VOLUME IMAGE WORKDIR CMD...    run CMD in IMAGE with VOLUME at /ws, cwd /ws/WORKDIR
#   scripts/ci-volume.sh fetch VOLUME PATH [DEST]             copy /ws/PATH back into DEST (default: repo root)
#   scripts/ci-volume.sh rm    VOLUME                         delete the volume
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_IMAGE="alpine:3.20"

cmd="${1:?usage: $0 sync|run|fetch|rm VOLUME ...}"
vol="${2:?volume name required}"
shift 2

case "$cmd" in
  sync)
    docker volume create "$vol" >/dev/null
    tar -C "$ROOT_DIR" -cf - \
      --exclude=./.git --exclude='./application/node_modules' --exclude='./application/dist' \
      --exclude='./terraform/.terraform' --exclude=./backups --exclude=./logs --exclude=./incident \
      --exclude='./security/reports' --exclude='./docker/.env' . |
      docker run --rm -i -v "$vol:/ws" "$HELPER_IMAGE" \
        sh -c 'rm -rf /ws/* /ws/.[!.]* 2>/dev/null; tar -xf - -C /ws'
    ;;
  run)
    image="${1:?image required}"; workdir="${2:?workdir required}"; shift 2
    docker run --rm -v "$vol:/ws" -w "/ws/$workdir" "$image" "$@"
    ;;
  fetch)
    path="${1:?path required}"; dest="${2:-$ROOT_DIR}"
    mkdir -p "$dest"
    docker run --rm -v "$vol:/ws" "$HELPER_IMAGE" tar -cf - -C /ws "$path" | tar -xf - -C "$dest"
    ;;
  rm)
    docker volume rm -f "$vol" >/dev/null
    ;;
  *)
    echo "usage: $0 sync|run|fetch|rm VOLUME ..." >&2; exit 2 ;;
esac
