# ==============================================================================
# RHEL golden image for test VMs: kickstart install from the boot ISO (Red Hat CDN) -> patch -> generalize -> qcow2
# One template for every RHEL major: versions/rhel<N>.pkrvars.hcl picks the ISO and kickstart/ks-rhel<N>.cfg.
# Generic on purpose: no role, no app, no users. cloud-init adds the login of each test VM.
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

# Secrets: from the environment only.

variable "rhsm_org" {
  type        = string
  sensitive   = true
  description = "Red Hat organization ID. Set as PKR_VAR_rhsm_org, never in a file."
}

variable "rhsm_activation_key" {
  type        = string
  sensitive   = true
  description = "Red Hat activation key. Set as PKR_VAR_rhsm_activation_key, never in a file."
}

# Same for every version.

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
  # The version's kickstart with its placeholders filled in; the .cfg file itself never holds a secret.
  kickstart_file = file(abspath("${path.root}/kickstart/ks-rhel${var.rhel_version}.cfg"))
  kickstart_org  = replace(local.kickstart_file, "@@RHSM_ORG@@", var.rhsm_org)
  kickstart_key  = replace(local.kickstart_org, "@@RHSM_ACTIVATION_KEY@@", var.rhsm_activation_key)
  kickstart      = replace(local.kickstart_key, "@@PACKER_SSH_PUBKEY@@", trimspace(file(pathexpand(var.ssh_public_key_file))))

  root_shell = "{{ .Vars }} sudo -E bash '{{ .Path }}'"

  image_name = "rhel${var.rhel_version}-golden"
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
