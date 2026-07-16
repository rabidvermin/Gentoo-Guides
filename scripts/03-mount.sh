#!/usr/bin/env bash
# 03-mount.sh — mount the full install tree under $MNT in the correct order.
# Nested /usr/portage and /usr/src mountpoints are created AFTER /usr is mounted
# (this is the step that fails otherwise). Replaces guide Steps 6-10 + 17.
set -euo pipefail
cd "$(dirname "$0")"; source ./00-config.sh

run mkdir -p "$MNT"
run swapon "/dev/mapper/${VG}-swap"
run mount "/dev/mapper/${VG}-rootfs" "$MNT"

run mkdir -p "$MNT"/home "$MNT"/var "$MNT"/data "$MNT"/opt "$MNT"/usr "$MNT"/tmp "$MNT"/efi
run mount "/dev/mapper/${VG}-home" "$MNT/home"
run mount "/dev/mapper/${VG}-var"  "$MNT/var"
run mount "/dev/mapper/${VG}-data" "$MNT/data"
run mount "/dev/mapper/${VG}-opt"  "$MNT/opt"
run mount "/dev/mapper/${VG}-usr"  "$MNT/usr"

# nested volumes live under the now-mounted /usr — create dirs first
run mkdir -p "$MNT/usr/portage" "$MNT/usr/src"
run mount "/dev/mapper/${VG}-portage" "$MNT/usr/portage"
run mount "/dev/mapper/${VG}-src"     "$MNT/usr/src"

run mkdir -p "$MNT/var/tmp"
run mount -t tmpfs -o "size=$TMP_SIZE"    tmpfs "$MNT/tmp"
run mount -t tmpfs -o "size=$VARTMP_SIZE" tmpfs "$MNT/var/tmp"

# ESP at /efi (NOT /boot — /boot stays on the encrypted root)
run mount "$EFI" "$MNT/efi"

echo "Mount tree:"
findmnt -R "$MNT"
