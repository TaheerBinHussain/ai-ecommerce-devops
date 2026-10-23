# Deployment guide

## A. Local, Docker Compose
```bash
scripts/setup.sh
scripts/deploy.sh compose                                   # app only
scripts/deploy.sh compose --with-monitoring --with-logging  # full stack (~4 GB RAM)
logging/elk/kibana-setup.sh                                 # once, creates the Kibana data view
scripts/stop.sh compose
```
| Service | URL |
|---|---|
| Store | http://localhost:8082 |
| Grafana | http://localhost:3000 (admin / `GRAFANA_ADMIN_PASSWORD` in `docker/.env`) |
| Prometheus | http://localhost:9090 (Status → Targets, Alerts) |
| Kibana | http://localhost:5601 → Discover → "NEXVION logs" |

## B. Local, Kubernetes (kind)
```bash
scripts/kind-cluster.sh create          # cluster "nexvion", registry localhost:5001, ingress on :8088
scripts/k8s-observability.sh install    # prints the Grafana password
scripts/deploy.sh kind                  # build, push, helm upgrade --install, health check
scripts/k8s-observability.sh open       # Grafana http://localhost:3001, Prometheus http://localhost:9091
```
Useful commands:
```bash
kubectl -n ecommerce get all,ingress,hpa,pdb
helm -n ecommerce history nexvion
helm test nexvion -n ecommerce
helm rollback nexvion <revision> -n ecommerce
```

## C. Jenkins
1. Give Jenkins access to Docker and restart it:
   `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins`
2. Plugins: Pipeline, Git, GitHub, Credentials Binding, JUnit, Timestamper (the "suggested plugins" set
   covers these).
3. Credentials (Manage Jenkins → Credentials → Global):
   - `kubeconfig-kind`, Secret file: `kind get kubeconfig --name nexvion > kubeconfig-kind.yaml`
   - for AWS: `kubeconfig-aws` (Secret file = `ansible/kubeconfig-dev.yaml`) and `aws-credentials`
     (Username = access key ID, Password = secret access key)
4. New Item → **Pipeline** (or Multibranch Pipeline) → "Pipeline script from SCM" → Git → your GitHub repo
   URL → branch `*/main` → Script Path `jenkins/Jenkinsfile`.
5. GitHub → repo Settings → Webhooks → `http://<jenkins-host>:8081/github-webhook/` (if Jenkins is not
   reachable from the internet, the Jenkinsfile's `pollSCM` checks GitHub every 5 minutes).
6. "Build with Parameters" → `DEPLOY_TARGET=kind` → Build.

## D. AWS (Terraform → Ansible → Jenkins)
Requires an AWS account, the AWS CLI configured (`aws configure`), and an SSH key (`ssh-keygen -t ed25519`).
```bash
cd terraform
# set admin_cidrs in environments/dev.tfvars to your IP: curl -s https://checkip.amazonaws.com
terraform init
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
terraform output

cd ../ansible
pip install --user ansible-core
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/dev.ini playbook.yml
```
Then upload `ansible/kubeconfig-dev.yaml` to Jenkins as `kubeconfig-aws` and run the pipeline with
`DEPLOY_TARGET=aws`, `ECR_REPOSITORY=<ecr_repository_url>`, `APP_URL=http://<node_public_ip>`, and set
`ingress.host` in `helm/ecommerce/values-aws.yaml` to your domain or `<ip>.nip.io`.

Monitoring on the cloud cluster: `KUBECONFIG=ansible/kubeconfig-dev.yaml scripts/k8s-observability.sh install`.

**Cost control:** a t3.medium plus EIP and ECR costs roughly USD 1–1.5 per day. Destroy when finished:
`terraform destroy -var-file=environments/dev.tfvars`.
