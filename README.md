# Java + MySQL on self-managed Kubernetes (Linode), automated with Ansible

Provision a self-managed Kubernetes cluster on Linode with **Terraform**, bootstrap it
with **kubeadm** via **Ansible**, and deploy a **Java (Spring Boot) + MySQL** application
behind an **nginx ingress** — end to end, from bare VMs to a browser-accessible app with
two commands.

The goal was to let a team deploy to Kubernetes *without* needing to know kubectl or K8s
configuration syntax: `terraform apply` provisions the infrastructure, one `ansible-playbook`
run does everything else.

## Architecture

```
                    Internet
                       |
                       |  http://java.<worker-ip>.nip.io:30080
                       v
            +----------------------+         +----------------------+
            |   Control plane VM   |         |      Worker VM       |
            |  (kubeadm init)      |         |  (kubeadm join)      |
            |                      |         |                      |
            |  kube-apiserver      | <-----> |  ingress-nginx (NP)  |
            |  etcd, scheduler     | Flannel |  java-app x2         |
            |  controller-manager  |  VXLAN  |  mysql x1            |
            +----------------------+  8472   +----------------------+
                       Linode firewall (SSH / 30000-32767 / inter-node)

  Request flow:  browser -> NodePort 30080 -> ingress-nginx -> java-service
                 -> java pods -> mysql-service -> mysql pod -> back
```

- **Cluster:** self-managed kubeadm, 1 control plane + 1 worker, Flannel CNI (10.244.0.0/16)
- **Ingress:** ingress-nginx via Helm, exposed as NodePort (no cloud LB on self-managed)
- **Config:** ConfigMap for non-secret DB info, Secret (ansible-vault) for credentials
- **App:** Spring Boot REST app with a visit counter that proves live DB round-trips

## Repository layout

```
terraform/   Linode VMs + firewall; generates the Ansible inventory from node IPs
ansible/
  roles/common         every node: hostname, swap, modules, sysctl, containerd, kube binaries
  roles/control_plane  kubeadm init, Flannel, produces the worker join command
  roles/worker         kubeadm join (reads the join token via hostvars)
  roles/ingress        helm-installs ingress-nginx (NodePort) + waits for readiness
  roles/app            applies manifests in order; renders Secret + ingress from vars
  playbooks/site.yml   chains bootstrap -> ingress -> app
k8s/         hand-written manifests (ConfigMap, Services, Deployments)
app/         Spring Boot source + multi-stage Dockerfile
```

## Prerequisites

- terraform, ansible, kubectl, Docker, an SSH keypair
- A Linode API token and a Docker Hub account
- ansible-galaxy collection install -r ansible/requirements.yml

## Run it

```bash
# 1. Build and push the app image, then set the tag in
#    k8s/java-deployment.yaml and ansible/inventory/group_vars/all/all.yml
cd app
docker build -t YOUR_USER/java-mysql-app:1.0.0 .
docker push YOUR_USER/java-mysql-app:1.0.0

# 2. Provision infrastructure (writes ansible/inventory/hosts.ini automatically)
cd ../terraform
export TF_VAR_linode_token=...
terraform init
terraform apply -var "ssh_pubkey=$(cat ~/.ssh/id_ed25519.pub)"

# 3. Store DB credentials in an encrypted vault
cd ../ansible
ansible-vault create inventory/group_vars/all/vault.yml
#   db_user / db_password / db_root_password

# 4. One command: bootstrap cluster -> ingress -> app
ansible-playbook playbooks/site.yml --ask-vault-pass
```

## Accessing the app

The ingress host is derived automatically from the worker IP (via nip.io), so no DNS or
hosts-file setup is needed. Get the URL with:

```bash
ansible workers -m debug -a "msg=http://java.{{ ansible_host }}.nip.io:30080" --ask-vault-pass
```

Open it in a browser — the visit counter increments on each refresh, confirming the full
chain from ingress through to MySQL.

## Teardown

```bash
cd terraform
terraform destroy
```

This removes both Linode VMs and the firewall — a complete, clean teardown. Nothing else
persists (MySQL storage is ephemeral by design). Re-running terraform apply followed by
ansible-playbook playbooks/site.yml rebuilds everything from scratch; the inventory and
ingress host regenerate from the new IPs with no manual edits.

## Design decisions

- **Self-managed kubeadm over managed LKE** — deliberately, to work with cluster internals
  (kubeadm init/join, CNI, cgroup driver) rather than have them abstracted away.
- **NodePort ingress** — self-managed clusters have no cloud load balancer integration, so the
  ingress controller is exposed via a fixed NodePort rather than a LoadBalancer service.
- **ansible-vault for secrets** — DB credentials are encrypted at rest and rendered into the
  Secret at deploy time; no plaintext credentials in git.
- **Single source of truth** — Terraform owns the IPs and writes them into the inventory;
  the ingress host is derived from the inventory at runtime, so infra rebuilds need no edits.
- **Idempotency** — every task reports change status accurately (apply tasks parse kubectl
  output; waits are observational), so a second site.yml run is fully clean.

## Not production-grade (deliberate scope)

- Single control plane (no HA), single worker
- MySQL uses emptyDir — data is lost on pod restart (would use Block Storage CSI + a PVC)
- Ingress is HTTP only (would add cert-manager + TLS)
- No backups, monitoring, or autoscaling
