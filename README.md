# golden-images

One Packer template that builds clean RHEL 8, 9 and 10 base images (`qcow2`) for KVM.

## Two images

| | CI image | General-use image |
| --- | --- | --- |
| For | Throwaway test VMs (role CI, CIS role tests) | Any RHEL VM you want to keep or use by hand, such as in Cockpit |
| Output | `rhel<N>-golden.qcow2` | `rhel<N>-golden-frqadmin.qcow2` |
| Users | None: each VM gets its login from cloud-init | `frqadmin` (sudo), with your password and SSH key |
| Built with | `-var-file=versions/rhel<N>.pkrvars.hcl` | The same, plus `-var-file=admin.pkrvars.hcl` |

The names differ, so the CI never picks the image with a user. Both have no Red Hat registration: each VM registers itself.

## What is inside

| Area | In the image |
| --- | --- |
| OS | RHEL minimal install, fully patched at build time |
| Packages | `cloud-init`, `qemu-guest-agent`, `python3` (for Ansible) |
| Security | SELinux enforcing, firewalld on with SSH only, root locked |
| Users | None (CI image), or `frqadmin` in `wheel` (general-use image) |
| Disk | 20 GB, UEFI, LVM `vg_sys` with separate `/home`, `/tmp`, `/var`, `/var/tmp`, `/var/log`, `/var/log/audit` and swap |
| Removed before saving | Red Hat registration, SSH host keys, machine ID, logs, the kickstart copy, the build user |

## Versions

| Version | Settings | Kickstart | Output |
| --- | --- | --- | --- |
| RHEL 8.10 | `versions/rhel8.pkrvars.hcl` | `kickstart/ks-rhel8.cfg` | `output-rhel8-golden/rhel8-golden.qcow2` |
| RHEL 9.8 | `versions/rhel9.pkrvars.hcl` | `kickstart/ks-rhel9.cfg` | `output-rhel9-golden/rhel9-golden.qcow2` |
| RHEL 10.2 | `versions/rhel10.pkrvars.hcl` | `kickstart/ks-rhel10.cfg` | `output-rhel10-golden/rhel10-golden.qcow2` |

The settings file picks the version; the template is the same for all.

## Quick start

```bash
cp local.auto.pkrvars.hcl.example local.auto.pkrvars.hcl && chmod 600 local.auto.pkrvars.hcl   # fill in your Red Hat ID and key
packer init .
packer build -var-file=versions/rhel9.pkrvars.hcl .                                             # CI image
packer build -var-file=versions/rhel9.pkrvars.hcl -var-file=admin.pkrvars.hcl .                 # general-use image
```

For the general-use image, first copy `admin.pkrvars.hcl.example` to `admin.pkrvars.hcl` and put in a hash from `openssl passwd -6`.

Needs a KVM host, the RHEL boot ISO in `~/ISO`, a Red Hat activation key and an SSH key. Full steps: [docs/build.md](docs/build.md).

## Layout

| Path | Holds |
| --- | --- |
| `rhel.pkr.hcl` | The Packer template: install, patch, clean, save |
| `versions/` | One settings file per RHEL version: ISO path and checksum |
| `local.auto.pkrvars.hcl.example` | Example of your own settings: Red Hat ID and key. Your copy is git-ignored |
| `admin.pkrvars.hcl.example` | Example of the general-use image settings: password hash. Your copy is git-ignored |
| `kickstart/` | One install answer file per RHEL version |
| `docs/build.md` | Build, import and test an image, step by step |
| `docs/code-walkthrough.md` | What each file does and why |

Secrets are never committed: the Red Hat ID, activation key and password hash live only in your git-ignored copies.

## Status

| Version | State |
| --- | --- |
| RHEL 9 CI image | Built and in use (2026-11-09) |
| RHEL 8, 10, and every general-use image | Checked with `packer validate` and the kickstart checker; not built yet |
