# Current state inventory (5 Nov 2026)

How this was verified, so the numbers in the README are evidence, not claims.

## Host

- OS: Kali Linux (kernel 6.16)
- CPU: Intel Core i7-10750H
- RAM: 31 GiB total
- Disk: 449 GB partition, ~367 GB free. Capacity is fine; the drive is an HDD, so disk speed is the real constraint for heavy services.

## Services

| Service | How checked | Result |
|---|---|---|
| Docker | `systemctl is-active docker` | active, enabled |
| k3s | `systemctl is-active k3s` | active, enabled |
| Ollama | `systemctl is-active ollama` | active |

## Kubernetes (k3s)

```
$ kubectl get nodes
NAME        STATUS   ROLES           AGE     VERSION
ghostr00t   Ready    control-plane   2d17h   v1.37.1+k3s1
```

Running workload in `default`:
- `web-app` deployment, 1 replica, image `nginx`, Running 2d14h.

System components (kube-system), all Running/Completed:
- coredns, traefik, metrics-server, local-path-provisioner, svclb-traefik.

Traefik LoadBalancer has external IP `node-ip`, so the cluster is reachable on the home LAN.

## Gaps found during this audit

1. `web-app` was created imperatively, so no YAML existed on disk. Now captured in `kubernetes/web-app/`.
2. No Service was exposing `web-app`. A ClusterIP Service is now defined in code.
3. The user account is not in the `docker` group, so docker commands need sudo. Fix: `sudo usermod -aG docker $USER` then log out and back in.

## Not yet built (do not claim these)

Wazuh, Prometheus, Grafana, Suricata/Zeek, pfSense, CI/CD. These are on the roadmap, nothing is deployed yet.
