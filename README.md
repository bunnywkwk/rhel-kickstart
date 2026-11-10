# golden-images

One Packer template that builds clean RHEL 8, 9 and 10 base images (`qcow2`) for test VMs on KVM.

## What it is for

- **A clean starting point for every test VM.** Each VM is a throwaway copy of the image; nothing is installed for a role or app.
- **Each VM brings its own login and Red Hat registration** through cloud-init, so the image holds no users and no secrets.
- **Used by** the role CI VM test (`ansible-pipeline`, pool `ci`) and the CIS role tests.

## What is inside

| Area | In the image |
| --- | --- |
| OS | RHEL minimal install, fully patched at build time |
| Packages | `cloud-init`, `qemu-guest-agent`, `python3` (for Ansible) |
| Security | SELinux enforcing, firewalld on with SSH only, root locked, no users |
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
packer init .
read -rp 'Red Hat org ID: ' PKR_VAR_rhsm_org; read -rsp 'Activation key: ' PKR_VAR_rhsm_activation_key; echo
export PKR_VAR_rhsm_org PKR_VAR_rhsm_activation_key
packer build -var-file=versions/rhel9.pkrvars.hcl .
unset PKR_VAR_rhsm_org PKR_VAR_rhsm_activation_key
```

Needs a KVM host, the RHEL boot ISO in `~/ISO`, a Red Hat activation key and an SSH key. Full steps: [docs/build.md](docs/build.md).

## Layout

| Path | Holds |
| --- | --- |
| `rhel.pkr.hcl` | The Packer template: install, patch, clean, save |
| `versions/` | One settings file per RHEL version: ISO path and checksum |
| `kickstart/` | One install answer file per RHEL version |
| `docs/build.md` | Build, import and test an image, step by step |
| `docs/code-walkthrough.md` | What each file does and why |

Secrets are never in these files: the Red Hat org ID and activation key come from the shell only.

## Status

| Version | State |
| --- | --- |
| RHEL 9 | Built and in use (2026-11-09) |
| RHEL 8, 10 | Checked with `packer validate` and the kickstart checker; not built yet |
