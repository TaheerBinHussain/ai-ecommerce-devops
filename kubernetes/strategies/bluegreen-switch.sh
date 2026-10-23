#!/usr/bin/env bash
# Switches live traffic to the given colour and points preview at the other one.
#   kubernetes/strategies/bluegreen-switch.sh blue|green
set -euo pipefail
target="${1:?usage: $0 blue|green}"
[[ "$target" == "blue" || "$target" == "green" ]] || { echo "colour must be blue or green" >&2; exit 1; }
other=$([[ "$target" == "blue" ]] && echo green || echo blue)
ns=ecommerce

kubectl -n "$ns" rollout status "deployment/nexvion-$target" --timeout=120s
kubectl -n "$ns" patch service nexvion-store-live    -p "{\"spec\":{\"selector\":{\"color\":\"$target\"}}}"
kubectl -n "$ns" patch service nexvion-store-preview -p "{\"spec\":{\"selector\":{\"color\":\"$other\"}}}"
echo "Live traffic -> $target, preview -> $other"
kubectl -n "$ns" get endpoints nexvion-store-live nexvion-store-preview
