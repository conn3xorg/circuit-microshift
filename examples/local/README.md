# Local example

Applies circuit-microshift to a throwaway Rocky Linux 10 VM on your machine. MicroShift needs a kernel of its own, which a container can't give it, so this one is a VM. You need Conn3x, QEMU with KVM (`qemu-system-x86` and `qemu-utils` on Debian and Ubuntu), `cloud-localds` from `cloud-image-utils`, and read and write access to `/dev/kvm`, usually through the `kvm` group.

```sh
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` The first apply takes a few minutes. To look at the result:

```sh
ssh -o UserKnownHostsFile=known_hosts -i id_ed25519 -p 2222 root@127.0.0.1 \
  oc --kubeconfig /var/lib/microshift/resources/kubeadmin/kubeconfig get nodes
```

The node is `Ready`. The router's port 80 is forwarded to `127.0.0.1:8080`, so a `Route` for `hello.example.test` answers on `curl -H 'Host: hello.example.test' http://127.0.0.1:8080/`.

`up.sh` downloads Rocky's `GenericCloud-Base` image once, checks it against Rocky's published checksums and keeps it in `~/.cache/circuit-microshift`. Each run boots a fresh copy-on-write disk over it, with 4 CPUs and 8 GB of memory, a cloud-init seed that sets the hostname and installs the SSH key for root, SSH on `127.0.0.1:2222` and the router on `127.0.0.1:8080`. The hostname matters: the image boots as `localhost` without one, and MicroShift won't start with that name in its certificates. Set `PORT` to use another SSH port, and pass the same port to Conn3x with `-var port=PORT`. Set `WEB_PORT` to move the other, and `CPUS` and `MEMORY` (in MB) to size the VM. The VM's console goes to `serial.log`.

`./down.sh` stops the VM and removes its disk, the key and the state. The cached image stays for the next run.
