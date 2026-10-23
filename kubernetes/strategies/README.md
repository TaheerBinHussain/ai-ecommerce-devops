# Deployment strategies

| Strategy | How it works here | Rollback |
|---|---|---|
| **Rolling** (default) | `deployment.yaml` / Helm: `maxSurge: 1`, `maxUnavailable: 0`, readiness probe on `/health`. Pods are replaced one at a time and only receive traffic once ready. | `helm rollback nexvion` or `kubectl rollout undo deploy/nexvion-store -n ecommerce` |
| **Blue-Green** | Two full deployments (`blue`, `green`). The `nexvion-store-live` Service selects one colour. Deploy the new version to the idle colour, test it via `nexvion-store-preview`, then switch with `bluegreen-switch.sh`. | Run `bluegreen-switch.sh` back to the previous colour (instant). |
| **Canary** | `canary.yaml` runs the new version as a separate Deployment/Service and a second Ingress with `nginx.ingress.kubernetes.io/canary-weight`. Start at 10%, watch Grafana/Kibana, raise the weight, then promote. | `kubectl delete -f canary.yaml` (100% back to stable). |

```bash
# Blue-green
kubectl apply -f kubernetes/strategies/blue-green.yaml
kubernetes/strategies/bluegreen-switch.sh green      # cut over
kubernetes/strategies/bluegreen-switch.sh blue       # roll back

# Canary (requires the stable release from Helm/kustomize to be running)
kubectl apply -f kubernetes/strategies/canary.yaml
kubectl -n ecommerce annotate ingress nexvion-store-canary \
  nginx.ingress.kubernetes.io/canary-weight="50" --overwrite
```
