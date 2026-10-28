variable "address" {
  type        = string
  description = "Public address of an x86_64 Rocky Linux 10 host."
}

module "microshift" {
  source = "../.."

  hosts                = { node = var.address }
  ssh_private_key_file = "~/.ssh/id_ed25519"

  config = {
    apiServer = { subjectAltNames = [var.address] }
  }
}

output "fetch_kubeconfig" {
  value = "scp root@${var.address}:${module.microshift.remote_kubeconfig_dir}/${var.address}/kubeconfig ."
}
