"""Knowledge base of known failure signatures for the NEXVION platform.

Each rule maps a log signature to a classification, a severity, the most likely
root cause, and what an on-call engineer should check and do next.
"""
import re
from dataclasses import dataclass, field

SEVERITY_ORDER = {"info": 0, "low": 1, "medium": 2, "high": 3, "critical": 4}


@dataclass(frozen=True)
class Rule:
    id: str
    category: str
    severity: str
    pattern: re.Pattern
    root_cause: str
    investigation: list = field(default_factory=list)
    remediation: list = field(default_factory=list)


def _r(pattern):
    return re.compile(pattern, re.IGNORECASE)


RULES = [
    Rule(
        "db_connection_timeout", "Database connectivity", "critical",
        _r(r"(database|db|postgres|mysql|mongo)[^\n]*(connection )?(timed? ?out|timeout|refused)"
           r"|could not connect to (server|database)|ECONNREFUSED[^\n]*(5432|3306|27017)"),
        "The application cannot reach its database: the database is down, unreachable on the network, "
        "rejecting the credentials, or out of connections.",
        ["Check database availability (pod/instance status, recent restarts)",
         "Test network connectivity from the app pod to the DB host/port (DNS, NetworkPolicy, security groups)",
         "Verify the credentials in the Kubernetes Secret match the database",
         "Check connection-pool usage against the database max_connections limit"],
        ["Restore the database service or fail over to a replica",
         "Fix the Secret/ConfigMap value and restart the deployment",
         "Raise max_connections or reduce the application pool size"],
    ),
    Rule(
        "oom_killed", "Resource exhaustion", "critical",
        _r(r"OOMKilled|out of memory|Cannot allocate memory|memory limit exceeded"),
        "A container exceeded its memory limit and was killed by the kernel.",
        ["kubectl describe pod <pod> -> Last State: OOMKilled",
         "Compare memory usage in Grafana ('Container memory') with resources.limits.memory",
         "Look for a traffic spike or memory leak introduced by the latest release"],
        ["Increase resources.limits.memory in the Helm values",
         "Roll back the release if the leak came from a new version (helm rollback)",
         "Enable/adjust the HorizontalPodAutoscaler"],
    ),
    Rule(
        "crash_loop", "Pod crash loop", "critical",
        _r(r"CrashLoopBackOff|Back-off restarting failed container"),
        "The container starts and exits repeatedly - usually a bad configuration, missing file, or failing start command.",
        ["kubectl logs <pod> --previous to see the last crash output",
         "kubectl describe pod <pod> for exit code and events",
         "Diff the ConfigMap/Secret and image tag against the last good release"],
        ["Fix the configuration and redeploy, or helm rollback to the previous revision"],
    ),
    Rule(
        "image_pull", "Image delivery", "high",
        _r(r"ImagePullBackOff|ErrImagePull|manifest unknown|pull access denied|repository does not exist"),
        "Kubernetes cannot pull the container image: wrong tag, image not pushed, or registry credentials missing/expired.",
        ["Confirm the tag exists in the registry (Jenkins 'Push Image' stage)",
         "Check imagePullSecrets (on AWS the ecr-pull secret is refreshed every 6h by cron)",
         "kubectl describe pod for the exact registry error"],
        ["Re-run the pipeline to push the image", "Run /usr/local/bin/ecr-refresh.sh on the node"],
    ),
    Rule(
        "nginx_config", "Web server configuration", "critical",
        _r(r"\[emerg\]|configuration file [^\n]* test failed|unknown directive|host not found in upstream"),
        "Nginx refused to start because its configuration is invalid.",
        ["Run nginx -t inside the container with the new ConfigMap",
         "Review the last change to the nginx config in Git"],
        ["Revert the ConfigMap change and restart the deployment"],
    ),
    Rule(
        "disk_full", "Resource exhaustion", "critical",
        _r(r"No space left on device|disk quota exceeded"),
        "A filesystem on the node or volume is full.",
        ["df -h on the node (scripts/system-check.sh)", "docker system df / old images and logs"],
        ["Run scripts/cleanup.sh", "Expand the volume (terraform root_volume_size)"],
    ),
    Rule(
        "probe_failure", "Health check failure", "high",
        _r(r"(Readiness|Liveness) probe failed"),
        "Pods are failing their /health probe so Kubernetes removes them from service or restarts them.",
        ["curl the /health endpoint from inside the cluster", "Check CPU throttling and response latency in Grafana"],
        ["Fix the failing dependency or increase probe timeouts if the app is slow to start"],
    ),
    Rule(
        "upstream_timeout", "Upstream latency", "high",
        _r(r"upstream timed out|504 Gateway Time-?out|context deadline exceeded"),
        "A backend behind the proxy is too slow to respond.",
        ["Check pod CPU/memory saturation and replica count",
         "Check latency panels in Grafana and slow requests in Kibana (http.request_time > 1)"],
        ["Scale out the deployment", "Roll back if latency started with a release"],
    ),
    Rule(
        "upstream_unavailable", "Upstream unavailable", "high",
        _r(r"connect\(\) failed|no live upstreams|502 Bad Gateway|connection refused while connecting to upstream"),
        "The proxy cannot reach any healthy backend pod.",
        ["kubectl get endpoints <service> - are there ready endpoints?", "Check whether all pods are failing readiness"],
        ["Restore healthy pods (rollback/restart)", "Verify Service selector labels match the pods"],
    ),
    Rule(
        "dns_failure", "Name resolution", "high",
        _r(r"could not be resolved|Temporary failure in name resolution|no such host|NXDOMAIN"),
        "A hostname used by the application cannot be resolved.",
        ["Check CoreDNS pods in kube-system", "Verify the hostname in the ConfigMap"],
        ["Fix the hostname or restart CoreDNS"],
    ),
    Rule(
        "tls_error", "TLS / certificates", "high",
        _r(r"certificate (has )?expired|x509:|SSL_do_handshake\(\) failed|certificate verify failed"),
        "A TLS handshake is failing - typically an expired or untrusted certificate.",
        ["Check certificate expiry: openssl s_client -connect host:443", "Check the Ingress TLS secret"],
        ["Renew the certificate and update the TLS secret"],
    ),
    Rule(
        "permission_denied", "Permissions", "medium",
        _r(r"permission denied|EACCES|Operation not permitted|forbidden"),
        "A process lacks permission to a file, directory or API - common after hardening (read-only FS, non-root user).",
        ["Identify the path/resource in the log line",
         "Check securityContext (runAsUser 101, readOnlyRootFilesystem) and mounted volumes"],
        ["Mount a writable emptyDir for the path, or fix ownership in the Dockerfile"],
    ),
    Rule(
        "rate_limited", "Traffic control", "medium",
        _r(r"limiting requests|429 Too Many Requests"),
        "Requests are being rejected by the ingress rate limit (possible traffic spike or abuse).",
        ["Identify top client IPs in Kibana", "Compare request rate to the limit-rps ingress annotation"],
        ["Block abusive IPs or raise the limit for legitimate traffic"],
    ),
    Rule(
        "missing_asset", "Broken content", "low",
        _r(r'open\(\) "[^"]+" failed \(2: No such file or directory\)'),
        "Pages reference files that are not in the image (broken links or missing assets).",
        ["Find the missing paths in the log lines", "Run the application tests (local href/src check)"],
        ["Add the missing asset or fix the link and redeploy"],
    ),
]
