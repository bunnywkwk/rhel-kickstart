# ==============================================================================
# RHEL golden image for test VMs: kickstart install from the boot ISO (Red Hat CDN) -> patch -> generalize -> qcow2
# One template for every RHEL major: versions/rhel<N>.pkrvars.hcl picks the ISO and kickstart/ks-rhel<N>.cfg.
# Generic on purpose: no role, no app, no users. cloud-init adds the login of each test VM.
# With -var-file=admin.pkrvars.hcl: the general-use image instead, with a sudo user (rhel<N>-golden-frqadmin).
# Steps: docs/build.md
# ==============================================================================

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}


# ---- Variables ----------------------------------------------------------------
# Per version: set in versions/rhel<N>.pkrvars.hcl (-var-file=...).

variable "rhel_version" {
  type        = string
  description = "Major version: picks kickstart/ks-rhel<N>.cfg and names the output (rhel<N>-golden.qcow2)."
}

variable "iso_path" {
  type        = string
  description = "RHEL boot ISO of that version. It installs from Red Hat's CDN, so the kickstart registers first (rhsm)."
}

variable "iso_checksum" {
  type        = string
  description = "sha256:<hex> of the ISO, as on the Red Hat download page."
}

# Secrets: from git-ignored files (local.auto.pkrvars.hcl, admin.pkrvars.hcl; see the .example files) or PKR_VAR_* in the shell.

variable "rhsm_org" {
  type        = string
  sensitive   = true
  description = "Red Hat organization ID. In local.auto.pkrvars.hcl (git-ignored) or PKR_VAR_rhsm_org."
}

variable "rhsm_activation_key" {
  type        = string
  sensitive   = true
  description = "Red Hat activation key. In local.auto.pkrvars.hcl (git-ignored) or PKR_VAR_rhsm_activation_key."
}

variable "admin_password_hash" {
  type        = string
  default     = ""
  sensitive   = true
  description = "openssl passwd -6 hash, in admin.pkrvars.hcl (git-ignored, -var-file=...): builds the general-use image with admin_user. Empty: the CI image, no users."
}

# Same for every version.

variable "admin_user" {
  type        = string
  default     = "frqadmin"
  description = "General-use image only: sudo user (wheel) with that password and the SSH key below."
}

variable "ssh_public_key_file" {
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
  description = "Key of the temporary build user 'packer' (removed at the end of the build)."
}

variable "ssh_private_key_file" {
  type    = string
  default = "~/.ssh/id_ed25519"
}

variable "disk_size" {
  type    = string
  default = "20G"
}

variable "headless" {
  type    = bool
  default = true
}


# ---- Locals -------------------------------------------------------------------

locals {
  ssh_pubkey = trimspace(file(pathexpand(var.ssh_public_key_file)))
  general    = var.admin_password_hash != ""

  # General-use image only: the admin user's kickstart lines.
  admin_user = local.general ? join("\n", [
    "user --name=${var.admin_user} --groups=wheel --iscrypted --password=${var.admin_password_hash}",
    "sshkey --username=${var.admin_user} \"${local.ssh_pubkey}\"",
  ]) : ""

  # The version's kickstart with its placeholders filled in; the .cfg file itself never holds a secret.
  kickstart_file  = file(abspath("${path.root}/kickstart/ks-rhel${var.rhel_version}.cfg"))
  kickstart_admin = replace(local.kickstart_file, "#@@ADMIN_USER@@", local.admin_user)
  kickstart_org   = replace(local.kickstart_admin, "@@RHSM_ORG@@", var.rhsm_org)
  kickstart_key   = replace(local.kickstart_org, "@@RHSM_ACTIVATION_KEY@@", var.rhsm_activation_key)
  kickstart       = replace(local.kickstart_key, "@@PACKER_SSH_PUBKEY@@", local.ssh_pubkey)

  root_shell = "{{ .Vars }} sudo -E bash '{{ .Path }}'"

  # rhel9-golden (CI), or rhel9-golden-frqadmin (general use): a different name, so the CI never picks the one with a user.
  image_name = "rhel${var.rhel_version}-golden${local.general ? "-${var.admin_user}" : ""}"
}


# ---- Builder ------------------------------------------------------------------

source "qemu" "rhel" {
  iso_url      = pathexpand(var.iso_path)
  iso_checksum = var.iso_checksum

  output_directory = abspath("${path.root}/output-${local.image_name}")
  vm_name          = "${local.image_name}.qcow2"
  format           = "qcow2"
  disk_size        = var.disk_size
  disk_interface   = "virtio"
  net_device       = "virtio-net"

  # UEFI (q35 + OVMF), host CPU (RHEL 10 needs x86-64-v3); the test VMs boot the same way.
  accelerator       = "kvm"
  machine_type      = "q35"
  cpu_model         = "host"
  cpus              = 2
  memory            = 4096
  efi_boot          = true
  efi_firmware_code = "/usr/share/edk2/ovmf/OVMF_CODE.fd"
  efi_firmware_vars = "/usr/share/edk2/ovmf/OVMF_VARS.fd"
  headless          = var.headless

  # Kickstart on a CD labelled OEMDRV: Anaconda loads ks.cfg from it by itself.
  cd_content = {
    "ks.cfg" = local.kickstart
  }
  cd_label = "OEMDRV"

  # GRUB defaults to "Test this media": <up> selects "Install".
  boot_wait    = "10s"
  boot_command = ["<up><enter>"]

  communicator         = "ssh"
  ssh_username         = "packer"
  ssh_private_key_file = pathexpand(var.ssh_private_key_file)
  ssh_timeout          = "90m"

  # Last step of the build: remove the build user, then power off.
  shutdown_command = "sudo sh -c 'userdel -rf packer; rm -f /etc/sudoers.d/packer; systemctl poweroff'"
}


# ---- Build --------------------------------------------------------------------

build {
  sources = ["source.qemu.rhel"]

  # 1. Patch (the kickstart registered the system, so the CDN repos work).
  provisioner "shell" {
    execute_command = local.root_shell
    inline          = ["dnf -y update"]
  }

  # 2. Generalize: no Red Hat identity, no host identity, no kickstart copy (it holds the activation key).
  provisioner "shell" {
    execute_command = local.root_shell
    inline = [
      "subscription-manager unregister || true",
      "subscription-manager clean",
      "dnf -y clean all",
      "cloud-init clean --logs --seed",
      "rm -f /root/anaconda-ks.cfg /root/original-ks.cfg",
      "rm -rf /var/log/anaconda",
      "rm -f /etc/ssh/ssh_host_*",
      "truncate -s 0 /etc/machine-id",
      "find /var/log -type f -exec truncate -s 0 {} +",
      "sync",
    ]
  }
}
