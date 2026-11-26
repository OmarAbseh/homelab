# Azure Secure Network

## Project goals

Build a network where NSGs and an ASG allow only the intended traffic, using and learning the Azure CLI.

## Definitions

**What is a resource group?**
A resource group is a way of grouping all the different resources deployed into Azure under one management and permissions boundary.

**What is a VNet, and what is a subnet?**
A VNet is Azure's virtual network that connects the resources inside it for connectivity and communication between them, plus accessibility from outside sources and visibility. A subnet is a subdivision of that network with its own range of addresses, for example the Web-subnet ranges 10.0.1.0/24.

**Why did we split into two subnets instead of one?**
We split the web subnet from the app subnet so each one has different allowed inbound traffic.

**What is an NSG?**
Basically an NSG is a stateful firewall made of a prioritized list of allow/deny rules. It attaches to a subnet or a single NIC (one VM), and every packet going in or out of it gets checked against the rules.

## Approach

> Heads up: the first install below was broken, and the first region choice failed. I kept the real path I walked instead of cleaning it up. See [Corrections / gotchas](#corrections--gotchas) for how I recovered.

Installing the Azure CLI on my Linux environment:

```bash
apt-get update && apt install azure-cli -y
```

Upgrading the CLI version:

```bash
az upgrade
```

Started with `az resource create --help`, which wants properties `-p`, a group name `-g`, and a name `-n`.

Creating the resource group:

```bash
az group create -l westeurope -n azure-sc
```

Creating the VNet `securityVNet`. This got interrupted because of unavailability in West Europe, so I created it in North Europe:

```bash
az network vnet create -g azure-sc -n securityVNet \
  --address-prefix 10.0.0.0/16 \
  --subnet-name Web-subnet --subnet-prefixes 10.0.1.0/24 \
  --location northeurope
```

> Earlier I tried to create both subnets (Web-subnet, App-subnet) in the same prompt by adding a second `--subnet-name`. The az CLI ignored the first one and just proceeded with the second. Lesson: add the second subnet with its own command.

Creating the App-subnet:

```bash
az network vnet subnet create -n app-subnet --vnet-name securityVNet -g azure-sc \
  --address-prefixes 10.0.2.0/24
```

Verifying both exist:

```bash
az network vnet subnet list -g azure-sc --vnet-name securityVNet -o table
```

| AddressPrefix | Name       | ProvisioningState | ResourceGroup |
|---------------|------------|-------------------|---------------|
| 10.0.1.0/24   | Web-subnet | Succeeded         | azure-sc      |
| 10.0.2.0/24   | app-subnet | Succeeded         | azure-sc      |

Creating the NSG:

```bash
az network nsg create -g azure-sc -n web-nsg --location northeurope
```

Creating the NSG rules for HTTP (80) and SSH (22), with a lower priority number so they are checked before the deny rules:

```bash
az network nsg rule create -g azure-sc --nsg-name web-nsg -n allow-http \
  --priority 100 --direction Inbound --access Allow --protocol Tcp --destination-port-ranges 80

az network nsg rule create -g azure-sc --nsg-name web-nsg -n allow-ssh \
  --priority 101 --direction Inbound --access Allow --protocol Tcp --destination-port-ranges 22
```

Restricting SSH access to one specific IP (my PC) so no outside access to the network is allowed:

```bash
az network nsg rule update -g azure-sc --nsg-name web-nsg -n allow-ssh \
  --source-address-prefix 84.000.00.00
```

Attaching the NSG to the Web-subnet:

```bash
az network vnet subnet update -g azure-sc --vnet-name securityVNet -n Web-subnet --nsg web-nsg
```

Checking VM availability:

```bash
az vm list-usage -l northeurope -o table
```

Creating an Ubuntu 22.04 `Standard_B2ts_v2` VM and attaching it to the existing VNet and NSG.

> VM deployment in North Europe is full, switching to Sweden Central :/ , wanting terraform asf -_-

Creating the ASG, which makes CIDR managing easier by pointing rules at the ASG instead of at IPs:

```bash
az network asg create -g azure-sc-se -n asg-web --location swedencentral
```

Putting the web-vm NIC into the application security group. List the ipconfig name first, then update it:

```bash
az network nic ip-config list -g azure-sc-se --nic-name web-vmVMNic -o table

az network nic ip-config update -g azure-sc-se --nic-name web-vmVMNic \
  -n ipconfigweb-vm --application-security-group asg-web
```

Updating the NSG rule to source from the ASG instead of a raw CIDR:

```bash
az network nsg rule update -g azure-sc-se --nsg-name app-nsg -n allow-internal \
  --source-asgs asg-web --source-address-prefixes ""
```

Network Watcher IP flow verify, to prove the rules without sending real traffic:

```bash
az network watcher test-ip-flow -g azure-sc-se --direction Inbound --protocol Tcp \
  --local 10.0.2.4:80 --remote 8.8.8.8:12345 --vm app-vm
```

```json
{
  "access": "Deny",
  "ruleName": "defaultSecurityRules/DenyAllInBound"
}
```

```bash
az network watcher test-ip-flow -g azure-sc-se --direction Inbound --protocol Tcp \
  --local 10.0.2.4:80 --remote 10.0.1.4:12345 --vm app-vm
```

```json
{
  "access": "Allow",
  "ruleName": "securityRules/allow-internal"
}
```

Internet to app-vm on 80 is denied by the default `DenyAllInBound`. Web-vm (which is in `asg-web`) to app-vm on 80 is allowed by `allow-internal`. That second result also proves the ASG works: Network Watcher resolved web-vm's IP to its ASG membership and matched the rule.

---

## Corrections / gotchas

Fixing the record above, this is the stuff I got wrong and how I recovered.

- The Kali `apt install azure-cli` and `az upgrade` at the top were a **broken install**. The Kali package has broken modules (`az group create` crashed with a NoneType traceback). I switched to **Azure Cloud Shell** (az is built in and already logged in) and did everything there.
- `az resource create` was a **wrong turn**. It is a low-level command that wants raw JSON `--properties`. For a resource group the right command is `az group create`.
- **Region problems:** West Europe refused the VNet ("not accepting new customers"). North Europe took the network but had **no VM capacity** for my subscription (`SkuNotAvailable` on B2ts_v2, B2s_v2 and D2s_v3, that is capacity, not quota, I had quota). So I rebuilt the whole thing in **Sweden Central**.

## Part 2 , rebuild in Sweden Central + the VM + segmentation

- **Rebuilt everything in Sweden Central** in a fresh RG `azure-sc-se`: VNet `scVNet-se`, Web-subnet 10.0.1.0/24, App-subnet 10.0.2.0/24, `web-nsg` (allow-http 80 from `*`, allow-ssh 22 from my home IP only), attached to Web-subnet. Same commands as above, pointed at Sweden Central. Lesson I felt: doing this by hand is slow and error-prone, this is why Terraform / IaC exists (Project F).
- **Deployed the web VM:**

```bash
az vm create -g azure-sc-se -n web-vm --location swedencentral \
  --image Ubuntu2204 --size Standard_B2ts_v2 \
  --vnet-name scVNet-se --subnet Web-subnet \
  --public-ip-address web-vm-ip --admin-username azureuser \
  --generate-ssh-keys --nsg ""
```

The `--nsg ""` matters: it stops az from making its own NIC-level NSG, so my subnet NSG is the only one.

- **Installed nginx through the control plane** (no SSH needed, which is useful because SSH is locked down):

```bash
az vm run-command invoke -g azure-sc-se -n web-vm --command-id RunShellScript \
  --scripts "sudo apt-get update && sudo apt-get install -y nginx"
```

- **Proof the NSG works:** from Cloud Shell `curl http://<web-vm-public-ip>` returned the nginx page (port 80 open to the world), but `ssh` from Cloud Shell **timed out** (its IP is not my allowed IP, so `DenyAllInBound` dropped it). Same source, port 80 allowed and port 22 denied, exactly what I configured.
- **SSH from home works** (my home IP is on the allow list): `ssh -i ~/.ssh/azure-id_rsa azureuser@<public-ip>`.
- **Security lesson, key handling:** I first saved the private key *inside this project folder*. That is wrong, a private key is the password to the server and must never sit in a repo or docs folder. Moved it to `~/.ssh` and `chmod 600`. Never commit private keys.

## Part 3 , segmentation (app tier)

- **Deployed `app-vm` into App-subnet with `--public-ip-address ""`**, so NO public IP. Private IP only (10.0.2.4), invisible to the internet.
- **Made `app-nsg`** with `allow-internal` (priority 100, source 10.0.1.0/24 = web-subnet, ports 80/22, Allow) and attached it to App-subnet.
- **Key NSG lesson:** an allow rule does NOT restrict. The default `AllowVnetInBound` (65000) already lets the whole VNet in, so my `allow-internal` alone changed nothing. To actually segment I added `DenyAll` (priority 101, source VirtualNetwork, Deny). Order: web-subnet allowed at 100, everything else denied at 101, before the 65000 default. That is what makes "web-subnet only" real.
- **Proof:** from web-vm, `curl http://10.0.2.4` returned app-vm's nginx page (web to app allowed on 80). `ssh 10.0.2.4` from web-vm reached auth and failed only on the key (web to app allowed on 22 too). The internet cannot reach app-vm at all (no public IP + DenyAll).
- **Jump host (bastion pattern):** to reach the private app-vm from home without copying the key onto the public web-vm, use ProxyJump:

```bash
ssh -J azureuser@<web-vm-ip> -i ~/.ssh/azure-id_rsa azureuser@10.0.2.4
```

Never put the key on the internet-facing box. This is what Azure Bastion automates.

## What I proved

- A segmented two-tier VNet built from scratch on the CLI.
- NSG least-privilege: HTTP open to the world, SSH locked to my home IP only.
- A private backend tier with no public IP, reachable only from the web tier.
- Role-based rules with an ASG (rules point at the group, not at IPs).
- The whole thing verified with Network Watcher IP flow verify, which even names the rule making each decision.
- Full lifecycle: built it, proved it, then tore it down with `az group delete`.

## Diagram

![Architecture diagram](diagram.png)

*(two-tier VNet: internet to web-subnet on 80, SSH to web-subnet from my IP only, web-subnet to app-subnet on 80/22, internet blocked from app-subnet)*
