#!/usr/bin/env bash
# 02-format.sh — mkfs.ext4 on every non-swap logical volume.
# Replaces guide Step 5.
set -euo pipefail
cd "$(dirname "$0")"; source ./00-config.sh

echo "Will create ext4 filesystems on these volumes:"
for entry in "${LVS[@]}"; do
  name=${entry%%:*}; [ "$name" = "swap" ] && continue
  echo "  /dev/mapper/${VG}-${name}"
done
confirm "This DESTROYS any existing data on the volumes listed above."

for entry in "${LVS[@]}"; do
  name=${entry%%:*}
  [ "$name" = "swap" ] && continue
  run mkfs.ext4 "/dev/mapper/${VG}-${name}"
done
echo "Filesystems created."
