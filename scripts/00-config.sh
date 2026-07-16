#!/usr/bin/env bash
# 00-config.sh — single source of truth for the install helper scripts.
# Edit the values here, then run the numbered scripts in order from the live
# environment. This file is sourced by the others; it is not run on its own.
#
# Scope: these scripts automate the repetitive LVM/format/mount/chroot/teardown
# steps. Partitioning (cfdisk) and LUKS format/open stay MANUAL by design.

# ── Identity / target ────────────────────────────────────────────────
HOST=Mindpalace          # hostname + LVM naming (CHANGE THIS)
DISK=/dev/nvme2n1        # target install disk — VERIFY with lsblk FIRST!

# Derived. NVMe uses a 'p' partition separator (nvme0n1p1); for a SATA/USB
# target instead use: EFI=${DISK}1  LUKS=${DISK}2
EFI=${DISK}p1
LUKS=${DISK}p2
VG=vg_${HOST}
MNT=/mnt/install

# ── Logical volumes:  name:size  (creation order) ────────────────────
# 'swap' is created contiguous (-Cy). Sizes are examples — adjust freely.
LVS=(
  "swap:64G"
  "rootfs:10G"
  "usr:40G"
  "var:20G"
  "opt:20G"
  "portage:30G"
  "src:10G"
  "home:200G"
  "data:600G"
)

# tmpfs sizes for /tmp and the Portage build dir (/var/tmp)
TMP_SIZE=1G
VARTMP_SIZE=16G

# ── Behaviour ────────────────────────────────────────────────────────
DRYRUN=${DRYRUN:-0}      # DRYRUN=1 ./01-lvm.sh  → echo commands, run nothing

# ── Helpers ──────────────────────────────────────────────────────────
run() {
  if [ "$DRYRUN" = "1" ]; then echo "DRYRUN: $*"; else echo "+ $*"; "$@"; fi
}

confirm() {
  echo; echo ">>> $1"
  read -rp ">>> Type 'yes' to proceed: " _ans
  [ "$_ans" = "yes" ] || { echo "Aborted."; exit 1; }
}

require_disk() {
  [ -b "$DISK" ] || { echo "ERROR: DISK=$DISK is not a block device. Fix 00-config.sh."; exit 1; }
  echo "Target disk: $DISK"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$DISK"
}

require_luks_open() {
  [ -e "/dev/mapper/${HOST}_LUKS" ] || {
    echo "ERROR: /dev/mapper/${HOST}_LUKS not found."
    echo "Open the LUKS container first (manual Step 3):"
    echo "  cryptsetup luksOpen --allow-discards $LUKS ${HOST}_LUKS"
    exit 1; }
}
