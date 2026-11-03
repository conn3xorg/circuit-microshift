variable "port" {
  type    = number
  default = 2222
}

module "microshift" {
  source = "../.."

  hosts                = { node = { address = "127.0.0.1", port = var.port } }
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"
}

output "kubeconfig_path" {
  value = module.microshift.kubeconfig_path
}
