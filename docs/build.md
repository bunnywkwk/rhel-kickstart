# Build a golden image

Build, import and test one image. Replace `<N>` with `8`, `9` or `10`.

## 1. Host needs

One time, on the KVM host:

```bash
sudo dnf install -y qemu-kvm libvirt virt-install edk2-ovmf xorriso
sudo systemctl enable --now libvirtd        # or the modular virtqemud
```

Also needed: Packer, and an SSH key at `~/.ssh/id_ed25519` (`ssh-keygen -t ed25519`). Packer uses it to log in during the build only.

## 2. Red Hat activation key

console.redhat.com → Inventory → System Configuration → **Activation Keys** → Create. Note the **organization ID** and the key name.

Put both in your own settings file, which Git ignores:

```bash
cp local.auto.pkrvars.hcl.example local.auto.pkrvars.hcl
chmod 600 local.auto.pkrvars.hcl            # only you can read it
vi local.auto.pkrvars.hcl                   # set rhsm_org and rhsm_activation_key
```

Packer loads `*.auto.pkrvars.hcl` by itself. A Red Hat username and password do not work here.

## 3. ISO and checksum

Download the RHEL `<N>` **boot ISO** from the Red Hat download page into `~/ISO`, then:

```bash
sha256sum ~/ISO/rhel-<N>.*-x86_64-boot.iso
```

The checksum must match the one on the Red Hat download page. Put the path and checksum in `versions/rhel<N>.pkrvars.hcl`.

## 4. Build

```bash
cd golden-images
packer init .
packer build -var-file=versions/rhel<N>.pkrvars.hcl .
```

Takes 20–40 minutes. Expect at the end:

```text
--> qemu.rhel: VM files in directory: .../output-rhel<N>-golden
```

To watch the install, add `-var headless=false`.

### 4b. General-use image (with `frqadmin`)

One time, make the admin settings file (Git ignores it):

```bash
cp admin.pkrvars.hcl.example admin.pkrvars.hcl
chmod 600 admin.pkrvars.hcl
openssl passwd -6                           # asks for the password, prints the hash
vi admin.pkrvars.hcl                        # paste the hash into admin_password_hash
```

Then build with both files:

```bash
packer build -var-file=versions/rhel<N>.pkrvars.hcl -var-file=admin.pkrvars.hcl .
```

Without `-var-file=admin.pkrvars.hcl` you get the CI image, even when the file exists.

Output: `output-rhel<N>-golden-frqadmin/rhel<N>-golden-frqadmin.qcow2`. `frqadmin` is in `wheel`: sudo asks for that password. It also gets the key in `~/.ssh/id_ed25519.pub`. Another name: `-var admin_user=<name>`.

Every copy of this image has the same password: change it on a VM you keep (`passwd`).

To use it in Cockpit: make a copy (`qemu-img create -f qcow2 -F qcow2 -b <image> <copy>.qcow2 20G`), Create VM → Import existing disk image → the copy, Customize VM → Firmware **UEFI**, then log in as `frqadmin`.

## 5. Put it in the pool `ci`

```bash
sudo mkdir -p /var/lib/libvirt/images/ci
virsh -c qemu:///system pool-define-as ci dir --target /var/lib/libvirt/images/ci     # first time only
virsh -c qemu:///system pool-start ci && virsh -c qemu:///system pool-autostart ci   # first time only
sudo cp output-rhel<N>-golden/rhel<N>-golden.qcow2 /var/lib/libvirt/images/ci/
virsh -c qemu:///system pool-refresh ci
virsh -c qemu:///system vol-list ci                                                  # shows rhel<N>-golden.qcow2
```

Test VMs only read this file. Never boot it directly.

## 6. Boot test

```bash
virt-install --connect qemu:///system --name golden-test --memory 2048 --vcpus 2 \
  --machine q35 --boot uefi --cpu host-passthrough --osinfo rhel<N>.0 \
  --disk pool=ci,size=20,backing_store=/var/lib/libvirt/images/ci/rhel<N>-golden.qcow2 \
  --cloud-init root-ssh-key=$HOME/.ssh/id_ed25519.pub \
  --network network=default --import --noautoconsole
virsh -c qemu:///system domifaddr golden-test         # wait until an IP shows
ssh -o StrictHostKeyChecking=no root@<IP> 'cat /etc/redhat-release; getenforce; subscription-manager status | grep -i status; ls /root; vgs'
```

Expect: `Red Hat Enterprise Linux release <N>.x`, `Enforcing`, `Overall Status: Unknown` (not registered), nothing in `/root`, and about 1.4 GB `VFree`.

Remove the test VM (its own disk only):

```bash
virsh -c qemu:///system destroy golden-test
virsh -c qemu:///system undefine golden-test --nvram --remove-all-storage
virsh -c qemu:///system vol-list ci                    # only the golden images left
```

## Rebuild

For a new minor release or monthly patches: update the ISO and checksum (step 3) if needed, move the old `output-rhel<N>-golden/` away, then steps 4 and 5. Copy into the pool only while no test VM runs.

## Add a version

1. Copy `kickstart/ks-rhel10.cfg` to `ks-rhel<N>.cfg` and `versions/rhel10.pkrvars.hcl` to `rhel<N>.pkrvars.hcl`.
2. Set `rhel_version`, `iso_path`, `iso_checksum` in the new settings file.
3. Check the kickstart against that version's syntax: `ksvalidator -v RHEL<N> kickstart/ks-rhel<N>.cfg` (package `pykickstart`).
4. Check the template: `PKR_VAR_rhsm_org=x PKR_VAR_rhsm_activation_key=x packer validate -var-file=versions/rhel<N>.pkrvars.hcl .`

## Troubleshooting

| Problem | Cause | Fix |
| --- | --- | --- |
| Install stops at "Installation source" or a registration error | Wrong org ID or activation key | Check both in the Red Hat console, rebuild |
| `Timeout waiting for SSH` | Install still running, or the kickstart failed | Rebuild with `-var headless=false` and watch |
| `Output directory ... already exists` | An earlier build is still in `output-rhel<N>-golden/` | Move or delete it, then rebuild |
| `Unset variable "rhel_version"` | No settings file given | Add `-var-file=versions/rhel<N>.pkrvars.hcl` |
| `Unset variable "rhsm_org"` | No `local.auto.pkrvars.hcl`, or it is named differently | Copy it from the `.example` (step 2) |
| Got `rhel<N>-golden` but wanted the `frqadmin` one | `-var-file=admin.pkrvars.hcl` was left out | Add it (step 4b), rebuild |
| `ISO checksum does not match` | Wrong ISO or checksum in the settings file | Redo step 3 |
| RHEL 10 stops at boot with `CPU does not support x86-64-v3` | The host CPU is too old for RHEL 10 | Build RHEL 10 on a newer host |
