provider "linode" {
  token = var.linode_token
}

locals {
  # A random-ish root password is required by the API but we never use it:
  # access is via SSH key only. Rotate/ignore it.
  root_pass = "12312323-${var.label_prefix}-9f3a!"

  node_cidrs = [
    for ip in concat(
      [linode_instance.control_plane.ip_address],
      linode_instance.worker[*].ip_address
    ) : "${ip}/32"
  ]
}

resource "linode_instance" "control_plane" {
  label           = "${var.label_prefix}-cp"
  region          = var.region
  type            = var.instance_type
  image           = var.image
  root_pass       = local.root_pass
  authorized_keys = [trimspace(var.ssh_pubkey)]
  tags            = ["${var.label_prefix}", "control-plane"]
}

resource "linode_instance" "worker" {
  count           = var.worker_count
  label           = "${var.label_prefix}-worker-${count.index + 1}"
  region          = var.region
  type            = var.instance_type
  image           = var.image
  root_pass       = local.root_pass
  authorized_keys = [trimspace(var.ssh_pubkey)]
  tags            = ["${var.label_prefix}", "worker"]
}


resource "linode_firewall" "k8s" {
  label = "${var.label_prefix}-fw"

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "allow-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = ["${var.my_ip}/32"] # TODO: restrict to your own IP/32
  }

  inbound {
    label    = "allow-nodeport"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "30000-32767" # ingress-nginx NodePort lives here
    ipv4     = ["0.0.0.0/0"]
  }

  inbound {
    label    = "allow-api"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "6443" # kube-apiserver (handy for kubectl from your laptop)
    ipv4     = ["0.0.0.0/0"]
  }

  inbound { #This allows all TCP between your nodes (using their IPs as the source)
    label    = "allow-cluster-tcp"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "1-65535"
    ipv4     = local.node_cidrs
  }

  inbound { #This allows all UDP between your nodes (using their IPs as the source)
    label    = "allow-cluster-udp"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "1-65535"
    ipv4     = local.node_cidrs
  }

  linodes = concat(
    [linode_instance.control_plane.id],
    linode_instance.worker[*].id,
  )
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.ini"
  content = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    cp_label = linode_instance.control_plane.label
    cp_ip    = linode_instance.control_plane.ip_address
    workers = [
      for w in linode_instance.worker : {
        label = w.label
        ip    = w.ip_address
      }
    ]
  })
}