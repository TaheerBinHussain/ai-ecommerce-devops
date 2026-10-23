# AI-Powered E-Commerce DevOps & Cloud-Native Delivery Platform

A production-style DevOps platform built around **NEXVION**, a ready-made e-commerce storefront
(HTML/CSS/JavaScript). The project does not change what the shop does. It automates and secures how
the shop is built, tested, shipped, run, monitored and debugged.

![Architecture](docs/images/architecture.png)

## What's inside

| Layer | Implementation | Folder |
|---|---|---|
| Application | NEXVION storefront + 14 automated tests + HTML lint + build stamping (`version.json`) | `application/` |
| Linux & Bash automation | setup, deploy, stop, health-check, backup, cleanup, logs, system-check, kind-cluster, k8s-observability | `scripts/` |
| Web server | Non-root Nginx: `/health` endpoint, JSON access logs, security headers, gzip, `stub_status` metrics | `docker/nginx/` |
| Containers | Multi-stage Dockerfile (test → build → 62 MB runtime), Compose with `monitoring` and `logging` profiles | `docker/` |
| CI/CD | Jenkins declarative pipeline (13 stages, auto-rollback, AI report on failure) + GitHub Actions CI | `jenkins/`, `.github/` |
| Infrastructure as Code | Terraform modules: network, compute (EC2 + IAM + EIP), registry (ECR); dev/prod environments | `terraform/` |
| Configuration management | Ansible roles: common, hardening, docker, k3s, platform | `ansible/` |
| Orchestration | Namespace, Deployment, Service, ConfigMap, Secret, Ingress, HPA, PDB, NetworkPolicy, Blue-Green, Canary | `kubernetes/` |
| Packaging | Helm chart `ecommerce` with kind / AWS values, ServiceMonitor, `helm test` | `helm/` |
| Monitoring | Prometheus (+ 8 alert rules), blackbox probes, Grafana dashboard (provisioned) | `monitoring/` |
| Logging | Filebeat → Logstash → Elasticsearch → Kibana | `logging/` |
| DevSecOps | Gitleaks, Trivy (dependencies, IaC/K8s config, image) with CI gates, hardening | `security/` |
| AI | Incident analyzer: rule engine + optional Claude enrichment, reads files/stdin/Elasticsearch | `ai/incident-analysis/` |
| Docs | Architecture, implementation, deployment, troubleshooting | `docs/` |

## Quick start (local)

Prerequisites: Linux, Docker, Docker Compose, Node 20+, kubectl, kind, Helm, Python 3 (`scripts/setup.sh` checks them).

```bash
scripts/setup.sh                                          # checks tools, creates docker/.env, installs deps
scripts/deploy.sh compose --with-monitoring --with-logging
#   Store       http://localhost:8082
#   Grafana     http://localhost:3000   (admin / password in docker/.env)
#   Prometheus  http://localhost:9090
#   Kibana      http://localhost:5601   (run logging/elk/kibana-setup.sh once)

scripts/kind-cluster.sh create                            # 3-node Kubernetes + registry + ingress
scripts/k8s-observability.sh install                      # Prometheus/Grafana inside the cluster
scripts/deploy.sh kind                                    # build → push → Helm rolling update → health check
#   Store       http://nexvion.localtest.me:8088
```

Day-2 operations:

```bash
scripts/health-check.sh http://localhost:8082     # external verification
scripts/system-check.sh                           # host resources, services, ports, cluster
scripts/logs.sh errors k8s                        # 4xx/5xx and error lines
scripts/logs.sh analyze k8s                       # AI incident report from live logs
python3 ai/incident-analysis/analyze.py --es-url http://localhost:9200   # AI analysis over ELK
scripts/backup.sh --keep 7                        # config + Grafana/Prometheus volumes + K8s state
security/scan.sh all nexvion-store:latest         # all security scans
scripts/cleanup.sh [--all]
```

## Cloud (AWS)

```bash
cd terraform && terraform init
terraform apply -var-file=environments/dev.tfvars        # VPC, EC2, ECR, IAM; writes ansible/inventory/dev.ini
cd ../ansible && ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/dev.ini playbook.yml       # hardening, Docker, k3s, Helm; writes kubeconfig-dev.yaml
# Jenkins: run the pipeline with DEPLOY_TARGET=aws and ECR_REPOSITORY=<terraform output ecr_repository_url>
```

Full guides: [deployment](docs/deployment.md) · [implementation](docs/implementation.md) ·
[architecture](docs/architecture.md) · [troubleshooting](docs/troubleshooting.md)

## Git workflow

`main` (always deployable, protected) ← `develop` ← `feature/<name>` branches. All changes go through a
Pull Request that must pass GitHub Actions CI before review and merge. Jenkins deploys only from `main`.
Releases are tagged `vX.Y.Z`. Commit messages follow `type(scope): summary` (e.g. `feat(helm): add PDB`).

## Verified results (local environment)

| Check | Result |
|---|---|
| Application tests / HTML lint | 14/14 passing, 0 lint errors |
| Docker image | 62 MB, runs as uid 101, Trivy: 0 vulnerabilities |
| Secret scan / config scan | 0 leaks / 0 HIGH-CRITICAL misconfigurations |
| Rolling update under load | 695/695 requests succeeded (0 errors) |
| Broken release (bad image tag) | Helm auto-rollback, site stayed HTTP 200, AI analyzer classified "Image delivery - HIGH" |
| Monitoring | 7/7 Prometheus targets up (Compose), 3/3 pod targets via ServiceMonitor (K8s) |
| Logging | Access logs parsed into `nexvion-logs-*`, 404s queryable in Kibana |
