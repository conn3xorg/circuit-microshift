#!/usr/bin/env sh
# Starts a throwaway Rocky Linux 10 VM on 127.0.0.1:$PORT (default 2222)
# that Conn3x can configure, with a fresh SSH key and its host key in
# ./known_hosts, and the router's port 80 forwarded to 127.0.0.1:$WEB_PORT
# (default 8080). A container won't do here: MicroShift needs a kernel of
# its own. Needs QEMU with KVM, and cloud-localds from cloud-image-utils.
set -eu
cd "$(dirname "$0")"
port=${PORT:-2222}
web_port=${WEB_PORT:-8080}
# One dated Rocky build, checked against its SHA-256 from Rocky's CHECKSUM
# file, kept here so moving to a newer build is a reviewed change.
release=10.2
image=Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2
sha256=9fc9e9ff16888bb68ac39b0392e25c9c92684d50c85f1cce6ab549363bbc4b48
cache=${XDG_CACHE_HOME:-$HOME/.cache}/circuit-microshift
mkdir -p "$cache"

if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
  echo "No access to /dev/kvm. Add yourself to the kvm group, or run this where KVM is available." >&2
  exit 1
fi

# Rocky moves a minor release's images to its vault once the next one is
# out, so the build is looked for in both places.
if ! (cd "$cache" && echo "$sha256  $image" | sha256sum -c --status - 2>/dev/null); then
  for tree in pub vault; do
    curl -fsSL -o "$cache/$image" "https://dl.rockylinux.org/$tree/rocky/$release/images/x86_64/$image" && break
  done
  (cd "$cache" && echo "$sha256  $image" | sha256sum -c --quiet -) || { rm -f "$cache/$image"; exit 1; }
fi

[ -f id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C circuit-microshift -f id_ed25519
if [ -f vm.pid ]; then kill "$(cat vm.pid)" 2>/dev/null || true; fi
rm -f disk.qcow2 seed.img vm.pid
# A copy-on-write disk over the image, so each run starts fresh.
qemu-img create -q -f qcow2 -b "$cache/$image" -F qcow2 disk.qcow2 20G
# MicroShift puts the node's name in its certificates and won't start if
# it's localhost, which is what the image boots as without one.
cat > user-data <<UD
#cloud-config
hostname: microshift
fqdn: microshift.example.test
disable_root: false
ssh_pwauth: false
users:
  - name: root
    ssh_authorized_keys: ["$(cat id_ed25519.pub)"]
UD
cloud-localds seed.img user-data
# MicroShift asks for 2 CPUs and 2 GB of memory. It was tested with 4 and 8.
qemu-system-x86_64 -enable-kvm -cpu host -m "${MEMORY:-8192}" -smp "${CPUS:-4}" \
  -drive file=disk.qcow2,if=virtio -drive file=seed.img,if=virtio,format=raw \
  -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$port-:22,hostfwd=tcp:127.0.0.1:$web_port-:80" \
  -display none -serial file:serial.log -daemonize -pidfile vm.pid

for _ in $(seq 1 90); do
  if ssh-keyscan -T 2 -p "$port" 127.0.0.1 > known_hosts 2>/dev/null && [ -s known_hosts ] &&
    ssh -q -o BatchMode=yes -o UserKnownHostsFile=known_hosts -i id_ed25519 -p "$port" root@127.0.0.1 'cloud-init status --wait >/dev/null 2>&1; true'; then
    echo "Ready on 127.0.0.1:$port. Now run: conn3x init && conn3x apply -var port=$port"
    exit 0
  fi
  sleep 2
done
echo "The VM started, but SSH didn't answer on 127.0.0.1:$port. Its console is in serial.log." >&2
exit 1
