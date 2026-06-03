variable "linode_token" {
  description = "Linode API token. Export as TF_VAR_linode_token instead of committing it."
  type        = string
  sensitive   = true
}

variable "ssh_pubkey" {
  description = "Contents of your public SSH key (e.g. file(\"~/.ssh/id_rsa.pub\")). Used for passwordless Ansible access."
  type        = string
}

variable "region" {
  description = "Linode region."
  type        = string
  default     = "us-ord" # London. Pick one close to you: linode-cli regions list
}

variable "instance_type" {
  description = "Linode plan. 2GB is the practical floor for a kubeadm node."
  type        = string
  default     = "g6-standard-2" # 2 vCPU / 4 GB
}

variable "worker_count" {
  description = "Number of worker nodes. 1 keeps cost down while staying multi-host."
  type        = number
  default     = 1
}

variable "label_prefix" {
  description = "Prefix for Linode labels and Ansible inventory host names."
  type        = string
  default     = "k8s"
}

variable "image" {
  description = "OS image. Ubuntu 24.04 LTS is the reference platform for these playbooks."
  type        = string
  default     = "linode/ubuntu24.04"
}

variable "my_ip" {
  description = "Define your IP to allow SSH access."
  type        = string
  default     = "0.0.0.0"
}