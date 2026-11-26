# Azure labs

Hands-on Azure, built on the CLI. Each folder is one lab with its own write-up:
what I built, the commands, the errors I hit, and what I proved.

Working toward AZ-104, then AZ-500 / SC-200.

## Labs
- [01 - Secure network (NSG + ASG + segmentation)](01-secure-network-nsg-asg/README.md) - done. Two-tier VNet, NSG least-privilege (SSH locked to my IP), private backend tier reachable only from the web tier, ASG role-based rules, verified with Network Watcher.

More to come (VM scale, identity/RBAC, storage security, monitoring, IaC with Terraform).
