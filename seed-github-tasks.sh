#!/usr/bin/env bash
#
# seed-github-tasks.sh
# Creates GitHub Milestones + one Issue per build-guide milestone (sub-tasks as
# checkboxes) in your repo, from the self-managed K8s build guide.
#
# Prereqs:
#   - GitHub CLI installed and authenticated:  gh auth login
#   - Run from inside the repo, OR pass owner/repo as the first arg:
#       ./seed-github-tasks.sh                 # uses the current repo
#       ./seed-github-tasks.sh your-user/your-repo
#
# Safe to re-run: it skips milestones/issues that already exist (matched by title).
#
set -euo pipefail

REPO_ARG="${1:-}"
if [[ -n "$REPO_ARG" ]]; then
  OWNER_REPO="$REPO_ARG"
else
  OWNER_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi
echo "Target repo: $OWNER_REPO"

# --- helpers ---------------------------------------------------------------
ensure_label() {
  gh label list --repo "$OWNER_REPO" --json name -q '.[].name' | grep -qxF "build-guide" \
    || gh label create build-guide --repo "$OWNER_REPO" --color 0E8A16 \
         --description "Self-managed K8s build guide" >/dev/null
}

ensure_milestone() {
  local title="$1" desc="$2"
  if gh api "repos/$OWNER_REPO/milestones?state=all" --jq '.[].title' | grep -qxF "$title"; then
    echo "  milestone exists: $title"
  else
    gh api --method POST "repos/$OWNER_REPO/milestones" \
      -f title="$title" -f description="$desc" >/dev/null
    echo "  + milestone: $title"
  fi
}

ensure_issue() {
  local title="$1" milestone="$2" body="$3"
  if gh issue list --repo "$OWNER_REPO" --state all --limit 200 \
       --json title -q '.[].title' | grep -qxF "$title"; then
    echo "  issue exists: $title"
  else
    gh issue create --repo "$OWNER_REPO" --title "$title" \
      --milestone "$milestone" --label build-guide --body "$body" >/dev/null
    echo "  + issue: $title"
  fi
}

# --- one entry per milestone ------------------------------------------------
# add "<milestone title>" "<milestone desc>" "<issue body>"
add() { ensure_milestone "$1" "$2"; ensure_issue "$1" "$1" "$3"; }

ensure_label

add "M0 — Prerequisites & skeleton" \
"Clean repo and working local toolchain." \
"**Goal:** clean repo + working toolchain.

- [ ] Install terraform, ansible, kubectl, git, docker
- [ ] Create Linode API token; export TF_VAR_linode_token
- [ ] Create SSH keypair
- [ ] Create dir skeleton (terraform/ ansible/ k8s/ app/)
- [ ] requirements.yml + ansible-galaxy collection install
- [ ] .gitignore (tfstate, *.tfvars, hosts.ini, vault.yml)

**Done when:** terraform/ansible/kubectl versions all run; token exported.
**Understand:** which tool owns provisioning vs config vs inspection."

add "M1 — Provision infrastructure (Terraform)" \
"Two reachable Linode VMs + generated Ansible inventory." \
"**Goal:** 2 VMs + generated inventory.

- [ ] 1.1 versions.tf — pin linode + local providers
- [ ] 1.2 variables.tf — token, region, type, worker_count, ssh_pubkey
- [ ] 1.3 main.tf — control plane + count-based workers
- [ ] 1.4 firewall — 22, 6443, 30000-32767
- [ ] 1.5 local_file renders inventory/hosts.ini from node IPs
- [ ] 1.6 outputs.tf — CP + worker IPs

**Done when:** terraform apply OK; ssh works; \`ansible all -m ping\` returns pong.
**Understand:** the TF->Ansible seam (TF writes the inventory)."

add "M2 — Node preparation (common role)" \
"Both nodes pass kubeadm preflight." \
"**Goal:** both nodes meet kubeadm requirements.

- [ ] 2.1 role skeleton (tasks/handlers/defaults)
- [ ] 2.2 disable swap (now + fstab)
- [ ] 2.3 load overlay + br_netfilter (now + persist)
- [ ] 2.4 sysctl: bridge-nf-call-iptables/ip6tables, ip_forward
- [ ] 2.5 containerd + SystemdCgroup=true + restart handler
- [ ] 2.6 pkgs.k8s.io repo, install kubelet/kubeadm/kubectl, hold, enable kubelet

**Done when:** swap empty, br_netfilter loaded, containerd active, kubeadm version OK; re-run shows no changes.
**Understand:** the SystemdCgroup gotcha; idempotency (creates/changed_when/stat/handlers)."

add "M3 — Control plane (control_plane role)" \
"Control-plane node reports Ready." \
"**Goal:** control plane Ready.

- [ ] 3.1 stat admin.conf guard
- [ ] 3.2 kubeadm init (advertise-address, pod-network-cidr 10.244.0.0/16)
- [ ] 3.3 install kubeconfig for root
- [ ] 3.4 apply Flannel CNI (guarded)
- [ ] 3.5 token create --print-join-command -> register -> set_fact
- [ ] 3.6 wait for /readyz (retries/until)

**Done when:** \`kubectl get nodes\` shows CP Ready; flannel pods running.
**Understand:** pod CIDR must match CNI; register->set_fact."

add "M4 — Join the workers (worker role)" \
"Multi-node cluster, all Ready. The centrepiece Ansible lesson." \
"**Goal:** multi-node cluster, all Ready.

- [ ] 4.1 stat kubelet.conf guard
- [ ] 4.2 join via hostvars[groups['control_plane'][0]].kubeadm_join_command

**Done when:** \`kubectl get nodes\` shows CP + worker Ready; re-run joins nothing.
**Understand:** hostvars cross-host fact-passing — be able to explain the token's journey out loud."

add "M5 — Ingress controller (ingress role + Helm)" \
"nginx ingress running via NodePort." \
"**Goal:** ingress-nginx running (NodePort).

- [ ] 5.1 detect/install helm
- [ ] 5.2 helm_repository ingress-nginx
- [ ] 5.3 helm install, service type=NodePort (30080/30443)

**Done when:** NodePort svc exists; controller Running; curl :30080 returns nginx 404.
**Understand:** no cloud LB on self-managed -> NodePort; Helm is right here."

add "M6 — Application image (Docker)" \
"A pushed image the cluster can pull." \
"**Goal:** pushed, pullable image.

- [ ] 6.1 Dockerfile (multi-stage, EXPOSE 8080)
- [ ] 6.2 docker build + run locally
- [ ] 6.3 docker push to registry
- [ ] 6.4 set exact tag in java-deployment.yaml + group_vars

**Done when:** \`docker pull <tag>\` works from a clean machine.
**Understand:** pin a real tag, never :latest."

add "M7 — Hand-write the K8s manifests" \
"App runs when applied manually." \
"**Goal:** app runs from manual kubectl apply.

- [ ] 7.1 namespace.yaml
- [ ] 7.2 db-configmap.yaml (DB_HOST/PORT/NAME)
- [ ] 7.3 secret strategy (example file + vault-rendered real one)
- [ ] 7.4 mysql deployment (1 replica, Recreate, emptyDir) + service
- [ ] 7.5 java deployment (env via cm/secret refs, readiness probe) + service
- [ ] 7.6 java ingress (ingressClassName nginx)

**Done when:** kubectl apply -f k8s/ -> pods Ready; java pod reaches mysql-service:3306; app loads in browser.
**Understand:** configMapKeyRef vs secretKeyRef; Service name = in-cluster DNS."

add "M8 — Automate the deploy (app role)" \
"One playbook deploys the app, in order, idempotently." \
"**Goal:** one idempotent deploy playbook.

- [ ] 8.1 copy k8s/ to control plane
- [ ] 8.2 apply ns -> cm -> secret -> mysql -> WAIT -> java -> ingress
- [ ] 8.3 render Secret from vaulted vars (no_log: true)
- [ ] 8.4 gate on kubectl rollout status (mysql + java)

**Done when:** vaulted vars + \`ansible-playbook 02-deploy-app.yml --ask-vault-pass\` deploys from scratch; re-run idempotent.
**Understand:** order via rollout-status gate, not sleep; why only the Secret is templated."

add "M9 — End-to-end on fresh infrastructure" \
"Prove the whole pipeline from zero." \
"**Goal:** zero -> working app, two commands.

- [ ] 9.1 site.yml imports the three playbooks in order
- [ ] 9.2 terraform destroy + apply (clean cluster)
- [ ] 9.3 ansible-playbook site.yml --ask-vault-pass
- [ ] 9.4 map ingress host (/etc/hosts or nip.io) + open in browser

**Done when:** fresh infra -> app reachable with apply + playbook.
**Understand:** the provisioning / config / deploy boundaries."

add "M10 — Polish & portfolio" \
"Safe, repeatable, presentable." \
"**Goal:** safe, repeatable, presentable.

- [ ] 10.1 restrict firewall SSH to your IP /32
- [ ] 10.2 confirm all secrets vaulted (no plaintext in git)
- [ ] 10.3 full idempotency pass (site.yml twice = clean)
- [ ] 10.4 write README (architecture, run, teardown)
- [ ] 10.5 document teardown (terraform destroy)
- [ ] 10.6 STAR-method summary for interviews

Stretch:
- [ ] PVC + Block Storage CSI (persistence)
- [ ] Linode CCM + LoadBalancer ingress
- [ ] TLS via cert-manager
- [ ] scale to 2+ workers

**Done when:** a stranger could clone + run from the README.
**Understand:** exactly what separates this from production."

echo "Done. View: gh browse --repo $OWNER_REPO -- milestones"
