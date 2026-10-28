# Facts confirm each host can run this build before anything is installed.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = contains(["rocky", "almalinux", "centos", "rhel"], self.os_id) && split(".", self.os_version)[0] == "10" && self.arch == "x86_64"
      error_message = "MicroShift from this circuit runs on x86_64 Rocky Linux 10, AlmaLinux 10, CentOS Stream 10 or RHEL 10."
    }
  }
}

locals {
  dir = "/var/lib/conn3x-microshift"
  # Keyed by checksum, so a changed release unpacks to a fresh directory.
  rpm_dir    = "${local.dir}/rpms-${substr(var.release.sha256, 0, 12)}"
  kubeconfig = "/var/lib/microshift/resources/kubeadmin/kubeconfig"
  packages   = sha256(jsonencode([var.release, var.dependency_rpms]))

  fw_rules = "--zone=trusted --query-source=10.42.0.0/16 && firewall-cmd %s --zone=trusted --query-source=169.254.169.1 && firewall-cmd %s --zone=public --query-port=6443/tcp"
  fw_check = "firewall-cmd ${format(local.fw_rules, "", "")} && firewall-cmd --permanent ${format(local.fw_rules, "--permanent", "--permanent")}"
}

circuit "microshift" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Cloud images often ship only kernel-modules-core. kube-proxy needs
  # xt_conntrack and xt_comment, which are in kernel-modules-extra.
  step "kernel_modules" {
    command {
      command = "dnf -y install \"kernel-modules-extra-$(uname -r)\""
      unless  = "rpm -q \"kernel-modules-extra-$(uname -r)\""
    }
  }

  step "conntrack_on_boot" {
    file {
      path    = "/etc/modules-load.d/microshift.conf"
      content = "nf_conntrack\n"
    }
  }

  step "conntrack" {
    command {
      command = "modprobe nf_conntrack"
      unless  = "test -e /proc/sys/net/netfilter/nf_conntrack_max"
    }
  }

  step "inotify" {
    for_each = { "fs.inotify.max_user_watches" = "524288", "fs.inotify.max_user_instances" = "16384" }
    sysctl {
      name  = item.key
      value = item.value
    }
  }

  step "dirs" {
    for_each = toset([local.rpm_dir, "${local.dir}/deps"])
    directory {
      path = item.value
    }
  }

  step "release" {
    download {
      url    = "https://github.com/microshift-io/microshift/releases/download/${var.release.tag}/microshift-rpms-x86_64.tgz"
      dest   = "${local.rpm_dir}.tgz"
      sha256 = var.release.sha256
    }
  }

  step "release_rpms" {
    archive {
      src     = "${local.rpm_dir}.tgz"
      dest    = local.rpm_dir
      creates = "${local.rpm_dir}/repodata/repomd.xml"
    }
  }

  step "deps" {
    for_each = var.dependency_rpms
    download {
      url    = item.value.url
      dest   = "${local.dir}/deps/${item.key}.rpm"
      sha256 = item.value.sha256
    }
  }

  # The release tarball and the dependency RPMs are unsigned, so their
  # checksums above are what vouches for them. Runs again when either
  # changes; dnf leaves packages that are already installed alone.
  step "packages" {
    command {
      command  = "dnf -y install --setopt=install_weak_deps=False --repofrompath=microshift-local,file://${local.rpm_dir} --setopt=microshift-local.gpgcheck=0 ${join(" ", [for k in keys(var.dependency_rpms) : "${local.dir}/deps/${k}.rpm"])} microshift-${var.release.tag} microshift-kindnet-${var.release.tag}"
      triggers = { packages = local.packages }
    }
  }

  # MicroShift's pods reach the host from 10.42.0.0/16, and its DNS from
  # 169.254.169.1. Only touches firewalld when it's running.
  step "firewalld" {
    command {
      command = "for p in '' --permanent; do firewall-cmd $p --zone=trusted --add-source=10.42.0.0/16 --add-source=169.254.169.1 && firewall-cmd $p --zone=public --add-port=6443/tcp || exit 1; done"
      unless  = "! systemctl -q is-active firewalld || { ${local.fw_check}; }"
    }
  }

  step "config_dir" {
    directory {
      path = "/etc/microshift"
    }
  }

  step "config" {
    file {
      path    = "/etc/microshift/config.yaml"
      content = yamlencode(var.config)
    }
  }

  step "running" {
    service {
      name    = "microshift"
      state   = "started"
      enabled = true
    }
  }

  # Restarts MicroShift when its config or its packages change.
  step "restart" {
    command {
      command  = "systemctl restart microshift"
      triggers = { config = sha256(yamlencode(var.config)), packages = local.packages }
    }
  }

  # The node turns Ready once the pod network is up, which takes a few
  # minutes on first start while images download.
  step "ready" {
    command {
      command = "for i in $(seq 60); do oc --kubeconfig ${local.kubeconfig} wait --for=condition=Ready node --all --timeout=10s 2>/dev/null && exit 0; sleep 5; done; exit 1"
      unless  = "oc --kubeconfig ${local.kubeconfig} wait --for=condition=Ready node --all --timeout=10s"
    }
  }
}
