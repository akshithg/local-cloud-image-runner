# local-cloud-image-runner

## Cloud Image

[./images/base](./images/base)

- [ubuntu-jammy](https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img) - 0b88d22f32e3f076b0884d60dfa4753f
- [amazonlinux2](https://cdn.amazonlinux.com/al2023/os-images/2023.4.20240513.0/kvm/al2023-kvm-2023.4.20240513.0-kernel-6.1-x86_64.xfs.gpt.qcow2) - ba335f9d4d9c1638a78301f90ef514a3"

## Cloud-init Configuration

[./cloud-init](./cloud-init)

- [user-data](./cloud-init/user-data)
- [metadata](./cloud-init/meta-data)
- [vendor-data](./cloud-init/vendor-data)

> server this with `python3 -m http.server 8000 --directory ./cloud-init`

## Setup (on host)

```bash
sudo apt install qemu-system-x86 cloud-init
```

## ./run.sh

- setup: downloads to [/images/base](/images/base/), checksum, copy image to [/images/workdir](/images/workdir/), resize image

```bash
./run.sh [ubuntu-jammy | amazonlinux2] [all | apache | nginx | mysql | postgres | redis | memcached] [setup | first | test | trace | all]
```

## disk image

- install kernel build tools [auto]
- install apps [auto]
- disable CONFIG_MODULE_SIG & related stuff [manual]
- install cr3reader [manual]
- disable kaslr [manual]

## References

- <https://powersj.io/posts/ubuntu-qemu-cli/>
- <https://cloudinit.readthedocs.io/en/latest/tutorial/qemu.html>
- <https://cloudinit.readthedocs.io/en/latest/howto/debug_user_data.html>
- <https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/hibernation-disable-kaslr.html>

## systemd stuff

boot time: `systemd-analyze`
all services: `systemctl list-units --type=service`
all services: `systemctl list-units --type=service --all`
