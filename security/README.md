# DevSecOps

| Control | Tool / mechanism | Where it runs | Gate |
|---|---|---|---|
| Secret detection | Gitleaks (`gitleaks.toml`) | Jenkins, GitHub Actions | Any finding fails |
| Dependency vulnerabilities | Trivy fs on `package-lock.json` | Jenkins, GitHub Actions | Fixable CRITICAL fails |
| IaC / K8s misconfiguration | Trivy config (Dockerfile, K8s, Helm, Terraform) | Jenkins, GitHub Actions | Reported (HIGH+) |
| Image vulnerabilities | Trivy image; ECR scan-on-push | Jenkins, GitHub Actions, AWS | Fixable CRITICAL fails |
| Secure container | non-root uid 101, read-only FS, `cap_drop: ALL`, no shell needed at runtime | Docker / K8s | — |
| Kubernetes | Pod Security "restricted", NetworkPolicy, Secrets, no SA token automount | Cluster | Admission rejects violations |
| Linux hardening | SSH keys only / no root login, UFW default-deny, fail2ban, unattended upgrades, sysctl, auditd | Ansible `hardening` role | — |
| Cloud least privilege | IAM role limited to ECR pull on one repo, IMDSv2, encrypted EBS, SG admin ports restricted | Terraform | — |
| Secrets handling | `docker/.env` (600, git-ignored), Jenkins credentials, K8s Secrets; `secret.yaml` is a template | Everywhere | Gitleaks |

Run locally: `security/scan.sh all <image>`. Reports go to `security/reports/`, which is git-ignored and
archived by Jenkins.

## Latest results
| Scan | Result |
|---|---|
| Gitleaks | no leaks found |
| Trivy dependencies | 0 vulnerabilities (no runtime npm dependencies) |
| Trivy config | 0 HIGH/CRITICAL after fixes |
| Trivy image (`nexvion-store`, Alpine 3.21) | 0 vulnerabilities (all severities) |

## Accepted risks
| ID | Resource | Reason | Mitigation |
|---|---|---|---|
| AVD-AWS-0104 | EC2 security group egress 0.0.0.0/0 | Node must reach apt, ECR, get.k3s.io, get.helm.sh (dynamic IPs) | UFW, no inbound admin ports except `admin_cidrs`, review quarterly |
| — | Elasticsearch security disabled in Compose | Local lab only, bound to 127.0.0.1 | Enable xpack security for any shared/cloud deployment |
