variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}


variable "release" {
  type = object({
    tag    = string
    sha256 = string
  })
  default = {
    tag    = "4.20.0_g153ff0ca9_4.20.0_okd_scos.16"
    sha256 = "536d308167124ab38c93f0c5a2cf3f57c63bb759dcb3412578a6e860388d32d2"
  }
  description = "MicroShift release from github.com/microshift-io/microshift: the release tag and the SHA-256 of its microshift-rpms-x86_64.tgz."

  validation {
    condition     = can(regex("^[A-Za-z0-9._+~-]+$", var.release.tag)) && can(regex("^[0-9a-f]{64}$", var.release.sha256))
    error_message = "release.tag must be a release tag such as \"4.20.0_g153ff0ca9_4.20.0_okd_scos.16\", and release.sha256 64 lowercase hex characters."
  }
}

variable "dependency_rpms" {
  type = map(object({
    url    = string
    sha256 = string
  }))
  default = {
    cri-o = {
      url    = "https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rpms/4.20-el9-beta/cri-o-1.33.13-9.rhaos4.20.gitd6a41c4.el9.x86_64.rpm"
      sha256 = "c048088d6e9c8c6f7a5672a891600e7e9732c5c0d427ab9c531288c470bd6e77"
    }
    cri-tools = {
      url    = "https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rpms/4.20-el9-beta/cri-tools-1.33.0-7.el9.x86_64.rpm"
      sha256 = "c75d5181ba107874f3748451d9648b3922eeab4911a47ee921edac125909e967"
    }
    openshift-clients = {
      url    = "https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rpms/4.20-el9-beta/openshift-clients-4.20.0-202610221619.p2.gef515cf.assembly.stream.el9.x86_64.rpm"
      sha256 = "f45a43a0b62a31ff5d7594637b562ed4f98404379e2df523f0d933c34573d8f8"
    }
    runc = {
      url    = "https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rpms/4.20-el9-beta/runc-1.2.9-4.rhaos4.20.el9.x86_64.rpm"
      sha256 = "96ebd3978e208696d089fd22ab64c4ee047dbfdc150e2ec5d103141117f07c3e"
    }
    containernetworking-plugins = {
      url    = "https://kojihub.stream.centos.org/kojifiles/packages/containernetworking-plugins/1.9.1/2.el9/x86_64/containernetworking-plugins-1.9.1-2.el9.x86_64.rpm"
      sha256 = "0262866f7c1556dfa5be4a752e041df9758f87001e6ceb16477a6408c9d606df"
    }
  }
  description = "RPMs MicroShift needs that Rocky Linux 10 doesn't ship, by name: each one's URL and SHA-256. The defaults match the default release."

  validation {
    condition     = alltrue([for k, r in var.dependency_rpms : can(regex("^[a-z0-9][a-z0-9._+-]*$", k)) && can(regex("^https://.+\\.rpm$", r.url)) && can(regex("^[0-9a-f]{64}$", r.sha256))])
    error_message = "Each of dependency_rpms needs a package name of lowercase letters, digits, ., _, + and -, an https:// url ending in .rpm and a sha256 of 64 lowercase hex characters."
  }
}

variable "config" {
  type        = any
  default     = {}
  description = "Settings for /etc/microshift/config.yaml, such as { apiServer = { subjectAltNames = [\"203.0.113.10\"] } }. MicroShift restarts when they change."
}
