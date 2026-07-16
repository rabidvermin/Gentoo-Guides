#!/usr/bin/env bash
# 01-lvm.sh — create the LVM PV/VG/LVs and format the ESP.
# Prereq: the LUKS container is already open as ${HOST}_LUKS (manual Step 3).
# Replaces guide Step 4.
set -euo pipefail
cd "$(dirname "$0")"; source ./00-config.sh

require_disk
require_luks_open
confirm "Create LVM PV/VG '$VG' on /dev/mapper/${HOST}_LUKS and format $EFI as FAT32."

run pvcreate "/dev/mapper/${HOST}_LUKS"
run vgcreate "$VG" "/dev/mapper/${HOST}_LUKS"

for entry in "${LVS[@]}"; do
  name=${entry%%:*}; size=${entry##*:}
  if [ "$name" = "swap" ]; then
    run lvcreate -L"$size" -Cy -n "$name" "$VG"
  else
    run lvcreate -L"$size" -n "$name" "$VG"
  fi
done

run mkswap "/dev/mapper/${VG}-swap"
run mkfs.vfat -F32 "$EFI"
echo "LVM volumes created and ESP formatted."
