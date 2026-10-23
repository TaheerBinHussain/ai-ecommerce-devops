# Troubleshooting

Start every investigation with `scripts/system-check.sh`, then `scripts/logs.sh analyze <compose|k8s>`
for an automated first diagnosis.

| Symptom | Likely cause | Fix |
|---|---|---|
| `bind: address already in use` on 8080 | Another service (Oracle XE, Jenkins) uses 8080 | Store uses 8082 by default; change `APP_PORT` in `docker/.env` |
| Container exits with `exec /docker-entrypoint.sh: operation not permitted` | Snap-packaged Docker + `no-new-privileges` (AppArmor) | Option removed from Compose; use Docker CE from download.docker.com for full hardening |
| `docker compose: unknown command` | Compose v2 plugin missing | Scripts fall back to `docker-compose`; or install `docker-compose-plugin` |
| kind: `network ... does not exist` | Stale `kind` Docker network | Cluster uses its own network `nexvion-kind` (`KIND_EXPERIMENTAL_DOCKER_NETWORK`) |
| A few 5xx/connection errors during a rollout | Pod stops before the ingress removes it from endpoints | `preStop: sleep 10` + `terminationGracePeriodSeconds: 30` (in the chart) |
| Pods `ImagePullBackOff` | Tag not pushed / registry credentials | Check the Jenkins Push stage; on AWS run `sudo /usr/local/bin/ecr-refresh.sh` |
| Pods `CrashLoopBackOff` after a config change | Invalid nginx config in the ConfigMap | `kubectl logs <pod> --previous`; `helm rollback nexvion` |
| Pod rejected: `violates PodSecurity "restricted"` | Manifest lacks securityContext settings | Copy the securityContext block from `helm/ecommerce/templates/deployment.yaml` |
| HPA shows `cpu: <unknown>` | metrics-server not ready | Wait 1–2 min; `kubectl -n kube-system logs deploy/metrics-server` |
| No data in Kibana | Filebeat cannot read container logs | `DOCKER_ROOT` in `docker/.env` must match `docker info --format '{{.DockerRootDir}}'` |
| Elasticsearch exits immediately | `vm.max_map_count` too low | `sudo sysctl -w vm.max_map_count=262144` |
| Grafana panels "No data" | Prometheus target down | Prometheus → Status → Targets; check the exporter container |
| Jenkins: `error while creating mount source path '/var/lib/jenkins/workspace/...': read-only file system` | Snap-confined Docker cannot bind-mount paths under `/var/lib` | Pipeline uses `scripts/ci-volume.sh` (workspace streamed into a named volume) - no bind mounts needed |
| Jenkins: `Unable to find Jenkinsfile` | Job Script Path left at the default `Jenkinsfile` | Set Script Path to `jenkins/Jenkinsfile` |
| Jenkins: `permission denied ... docker.sock` | jenkins user not in docker group | `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins` |
| Jenkins cannot reach the cluster | Missing/incorrect `kubeconfig-*` credential | Re-export with `kind get kubeconfig --name nexvion` |
| Terraform `UnauthorizedOperation` | AWS credentials lack permissions | Use an IAM user with EC2, VPC, IAM, ECR permissions |
| Ansible `UNREACHABLE` | SG `admin_cidrs` does not include your IP / wrong key | Update `admin_cidrs`, `terraform apply`, check `ansible_ssh_private_key_file` |
| AI analyzer prints "no valid Anthropic credentials" | `--llm` used without an API key | `export ANTHROPIC_API_KEY=...` or run without `--llm` (rule engine) |

## Rollback procedures
- Kubernetes: `helm -n ecommerce history nexvion` → `helm -n ecommerce rollback nexvion <rev>`
- Blue-green: `kubernetes/strategies/bluegreen-switch.sh <previous colour>`
- Canary: `kubectl delete -f kubernetes/strategies/canary.yaml`
- Compose: `IMAGE_TAG=<previous> scripts/deploy.sh compose`
- Infrastructure: `git revert` the Terraform change, then `terraform apply`
