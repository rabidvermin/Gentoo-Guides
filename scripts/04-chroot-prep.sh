#!/usr/bin/env bash
# 04-chroot-prep.sh — copy resolv.conf, bind the kernel pseudo-filesystems,
# then drop into the chroot. Replaces guide Steps 15-18.
set -euo pipefail
cd "$(dirname "$0")"; source ./00-config.sh

[ -d "$MNT/etc" ] || { echo "ERROR: $MNT/etc missing — did you unpack the stage3 (Step 14)?"; exit 1; }

run cp -L /etc/resolv.conf "$MNT/etc/"
run mount -t proc none "$MNT/proc"
run mount --rbind /sys  "$MNT/sys"
run mount --rbind /dev  "$MNT/dev"

echo
echo "Entering chroot. Re-export HOST/DISK/EFI/LUKS/VG inside if you need them."
echo "Type 'exit' to leave, then run 99-teardown.sh before rebooting."
run chroot "$MNT" /bin/bash -l
