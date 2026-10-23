#!/usr/bin/env bash
# Linux host health report: resources, services, ports, platform components.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

echo "================ SYSTEM CHECK $(date '+%F %T') ================"
echo "Host:    $(hostname)   Kernel: $(uname -r)   Uptime: $(uptime -p)"
echo "User:    $(id -un) (groups: $(id -Gn))"
echo

load=$(cut -d' ' -f1 /proc/loadavg); cores=$(nproc)
echo "CPU:     load $load on $cores cores"
mem_pct=$(free | awk '/Mem:/ {printf "%.0f", ($2-$7)/$2*100}')
echo "Memory:  ${mem_pct}% used ($(free -h | awk '/Mem:/ {print $3 " / " $2}'))"
[[ $mem_pct -gt 90 ]] && warn "Memory usage above 90%"

echo "Disk:"
df -h -x tmpfs -x squashfs -x overlay | awk 'NR==1 || /^\/dev/' | sed 's/^/  /'
df -P -x tmpfs -x squashfs -x overlay | awk 'NR>1 && /^\/dev/ && int($5) > 85 {print "  WARNING: " $6 " is " $5 " full"}'
echo

echo "Services:"
if docker info >/dev/null 2>&1; then ok "docker daemon running"; else warn "docker daemon not reachable"; fi
for svc in jenkins ssh sshd; do
  systemctl is-active --quiet "$svc" 2>/dev/null && ok "$svc active"
done
echo

echo "Platform containers:"
docker ps --filter "label=com.docker.compose.project=nexvion" --format '  {{.Names}}\t{{.Status}}' 2>/dev/null || true
echo

echo "Listening ports of interest:"
ss -ltn 2>/dev/null | awk 'NR>1 {print $4}' | grep -E ':(22|80|443|3000|5001|5601|8080|8081|8082|8088|9090|9200)$' | sed 's/^/  /' || echo "  none"
echo

if command -v kubectl >/dev/null && kubectl cluster-info >/dev/null 2>&1; then
  echo "Kubernetes ($(kubectl config current-context)):"
  kubectl get nodes --no-headers 2>/dev/null | sed 's/^/  /'
  kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null | sed 's/^/  /'
fi
echo "==========================================================="
