# Code walkthrough

What each file does and why.

## How a build runs

| Step | What happens |
| --- | --- |
| 1 | Packer reads `versions/rhel<N>.pkrvars.hcl`: version, ISO, checksum |
| 2 | It loads `kickstart/ks-rhel<N>.cfg` and fills in the Red Hat ID, key and build SSH key |
| 3 | It boots the ISO in a KVM VM, with the kickstart on a small CD labelled `OEMDRV` |
| 4 | The installer finds the kickstart by itself, registers with Red Hat and installs from the Red Hat CDN |
| 5 | Packer logs in as `packer`, runs `dnf update`, then cleans the system |
| 6 | It removes the build user, powers off and saves `rhel<N>-golden.qcow2` |

## `rhel.pkr.hcl`

| Key | Does | Why |
| --- | --- | --- |
| `rhel_version`, `iso_path`, `iso_checksum` | Come from the settings file | One template for every version |
| `rhsm_org`, `rhsm_activation_key` | Come from `PKR_VAR_*` in the shell, `sensitive` | Secrets never land in a file or the log |
| `locals.kickstart` | Picks `ks-rhel<N>.cfg` and replaces the `@@...@@` placeholders | The kickstart file in Git holds no secret |
| `cd_content`, `cd_label = "OEMDRV"` | Puts `ks.cfg` on a CD the installer reads by itself | No web server and no typing a boot line |
| `boot_command = ["<up><enter>"]` | Picks "Install" instead of "Test this media" | Skips the slow media check |
| `efi_boot`, `machine_type = "q35"` | UEFI boot | Test VMs boot the same way |
| `cpu_model = "host"` | Passes the host CPU | RHEL 10 needs x86-64-v3 |
| Provisioner 1 | `dnf -y update` | The image starts fully patched |
| Provisioner 2 | Unregister, clean dnf and cloud-init, delete host keys, machine ID, logs, kickstart copies | Every clone gets its own identity; the activation key does not stay in the image |
| `shutdown_command` | Deletes `packer` and its sudo rule, then powers off | No build user is left in the image |

## `versions/rhel<N>.pkrvars.hcl`

| Key | Does | Why |
| --- | --- | --- |
| `rhel_version` | Picks the kickstart and the output name | Adding a version needs no template change |
| `iso_path`, `iso_checksum` | Which ISO, and its sha256 | Packer refuses a wrong or broken ISO |

## `kickstart/ks-rhel<N>.cfg`

The three files are the same today, apart from their header and a note on RHEL 8's Python. They are separate so one version can change without touching the others.

| Key | Does | Why |
| --- | --- | --- |
| `rhsm` | Registers during the install | The boot ISO installs from the Red Hat CDN |
| `network ... --hostname=rhel-golden` | DHCP, generic name | cloud-init sets the real name per VM |
| `selinux --enforcing`, `firewall --service=ssh` | Security on from the start | Tests run on a host like a real one |
| `rootpw --lock`, no users | Nobody can log in to the image itself | cloud-init adds the key for each VM |
| `user --name=packer`, `sshkey`, `%post` sudo rule | Temporary build login | Packer needs it; removed at the end |
| Disk: GPT, `/boot/efi`, `/boot`, LVM `vg_sys` | Separate `/home`, `/tmp`, `/var`, `/var/tmp`, `/var/log`, `/var/log/audit`, swap; about 1.5 GB left free | The layout CIS benchmarks check; a full log cannot fill `/`; room to grow a volume |
| `%packages` | Minimal environment, `cloud-init`, `qemu-guest-agent`, `python3` | Only what a test VM needs |
| `%addon com_redhat_kdump --disable` | No crash-dump memory reserved | Saves memory on small test VMs |

RHEL 8: `python3` is 3.6. ansible-core 2.16 still manages it; 2.17 and later need `python3.11` or newer.

## Checks run on these files (2026-11-10)

| Check | Result |
| --- | --- |
| `packer fmt -check` | Clean |
| `packer validate` for RHEL 8, 9, 10 (dummy secrets) | `The configuration is valid.` |
| pykickstart parser, `RHEL8`, `RHEL9`, `RHEL10` | Each file parsed, no warnings |
| A build | RHEL 9 built 2026-11-09 with the same content before the split; RHEL 8 and 10 not built |
