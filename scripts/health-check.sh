#!/usr/bin/env bash
# health-check.sh - quick status of the homelab.
# Run: bash scripts/health-check.sh
set -u

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

echo "== Services =="
for svc in docker k3s ollama; do
  state=$(systemctl is-active "$svc" 2>/dev/null)
  printf "  %-8s %s\n" "$svc" "$state"
done

echo
echo "== Kubernetes node =="
kubectl get nodes 2>/dev/null || echo "  cluster not reachable"

echo
echo "== Workloads (default namespace) =="
kubectl get deploy,pods -n default 2>/dev/null || echo "  none"

echo
echo "== Resource use =="
free -h | awk '/^Mem:/ {print "  RAM: "$3" used / "$2" total"}'
df -h / | awk 'NR==2 {print "  Disk: "$3" used / "$2" ("$5")"}'
