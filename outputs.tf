output "kubeconfig_path" {
  description = "Path on each host of the admin kubeconfig, which talks to the API on localhost."
  value       = local.kubeconfig
}

output "remote_kubeconfig_dir" {
  description = "Directory on each host holding one admin kubeconfig per name in config.apiServer.subjectAltNames, for use from other machines."
  value       = "/var/lib/microshift/resources/kubeadmin"
}
