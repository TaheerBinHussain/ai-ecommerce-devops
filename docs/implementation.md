# Implementation notes

What was built, in the order it was built, and the decisions behind it.

## 1. Application preparation
- Moved the storefront into `application/src`, added `package.json`, `.htmlhintrc`, `build.js`.
- Tests (`node --test`, no extra framework): page/asset integrity, JS syntax, mobile meta tags,
  12-product catalogue integrity, currency formatting, XSS escaping, checkout validation rules
  (phone 10 digits, PIN 6, card 16, CVV 3, expiry MM/YY, UPI).
- `build.js` produces `dist/` plus `version.json` (version, commit, build number, timestamp) so every
  deployed copy can be traced back to a commit.

## 2. Web server and container
- `nginxinc/nginx-unprivileged` runs as uid 101 on port 8080.
- Nginx config adds `/health`, JSON access logs with request IDs, security headers, gzip, asset caching,
  and `/nginx_status` restricted to private networks for the metrics exporter.
- Multi-stage Dockerfile: the build stage runs lint and tests, so a broken commit cannot produce an image.
  The runtime stage runs `apk upgrade`, which removes all known OS CVEs. Final size 62 MB.
- Compose runs the app read-only with all capabilities dropped and memory/CPU limits. Monitoring and
  logging are opt-in profiles so a developer can run just the shop.

## 3. Bash automation
All scripts source `scripts/lib.sh` (colour logging, `require`, Compose v1/v2 detection), use
`set -euo pipefail`, and return meaningful exit codes so Jenkins can use them directly.

## 4. CI/CD
- Jenkins runs build tools in containers (`node:22-alpine`, Trivy, Gitleaks), so the agent only needs
  Docker, kubectl, Helm and Python.
- Image tag = `<build number>-<git sha>`, which is unique and traceable.
- Deploys use Helm with atomic rollback (`--atomic` on Helm 3, `--rollback-on-failure` on Helm 4).
- `post { failure }` gathers events, pod logs and Helm history and runs the AI analyzer.
- GitHub Actions gives fast PR feedback (tests, Terraform/Helm validation, scans) without Jenkins.

## 5. Infrastructure as Code
- Terraform modules keep network, compute and registry independent and reusable. Environments differ
  only in `.tfvars`.
- Security defaults: IMDSv2 only, encrypted gp3 root volume, default security group denies all, SSH and
  Kubernetes API open only to `admin_cidrs`, IAM role limited to pulling from one ECR repository, immutable
  ECR tags with scan-on-push and a lifecycle policy.
- Terraform renders the Ansible inventory, so no IP addresses are copied by hand.

## 6. Configuration management
Roles are idempotent and pass `ansible-lint` at the *production* profile. k3s was chosen over kubeadm
because it is a single binary that fits a t3.medium and includes an ingress controller (Traefik).

## 7. Kubernetes and Helm
- 3 replicas, `maxSurge 1 / maxUnavailable 0`, readiness and liveness on `/health`, and a `preStop` sleep
  so in-flight requests finish while the ingress controller removes the pod (this was needed for true
  zero downtime, see troubleshooting).
- Topology spread across nodes, PDB `minAvailable 2`, HPA 3–10 replicas at 70 % CPU.
- Pod Security "restricted" enforced on the namespace. Containers are non-root with a read-only root FS,
  no capabilities and RuntimeDefault seccomp. NetworkPolicy allows only the ingress controller and
  Prometheus.
- The nginx config lives in a ConfigMap. A checksum annotation restarts pods automatically when it changes.
- Strategies: rolling (default), blue-green (`kubernetes/strategies/blue-green.yaml` +
  `bluegreen-switch.sh`), canary (ingress-nginx `canary-weight` / `X-Canary` header).

## 8. Observability
- Compose: Prometheus scrapes nginx-exporter, node-exporter, cAdvisor and blackbox probes of three
  user-facing URLs. Kubernetes: kube-prometheus-stack plus the chart's ServiceMonitor, with the same alert
  rules loaded as a PrometheusRule.
- One Grafana dashboard works in both environments (12 panels).
- ELK: Filebeat autodiscovers the store container, Logstash parses the JSON log into `http.*` fields and
  derives `log_level` from the status code.

## 9. DevSecOps
See `security/README.md`. Gates: any secret, or any fixable CRITICAL CVE, fails the build.
Misconfiguration findings are reported. The one accepted risk (open egress on the EC2 node) is documented
inline with `#trivy:ignore`.

## 10. AI-assisted incident analysis
See `ai/incident-analysis/README.md`. A deterministic rule engine (14 failure signatures plus HTTP
statistics) always runs, works offline, and is unit tested. `--llm` sends only the condensed findings and
sample lines to Claude for a correlated root-cause write-up, returned as schema-validated JSON. Without
credentials it falls back to the rule engine.
