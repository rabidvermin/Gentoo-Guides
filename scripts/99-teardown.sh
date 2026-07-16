#!/usr/bin/env bash
# 99-teardown.sh — cleanly unmount and close everything before rebooting.
# Run from OUTSIDE the chroot (exit it first). Safe to re-run.
# Note: no 'set -e' — we push through steps that may already be done.
set -uo pipefail
cd "$(dirname "$0")"; source ./00-config.sh

sync

# The /dev, /proc, /sys rbinds are usually "busy" on a recursive unmount
# (they mirror the live system's active kernel mounts) — lazy-detach first.
umount -l "$MNT/dev" "$MNT/proc" "$MNT/sys" 2>/dev/null || true
umount -R "$MNT"                            2>/dev/null || true
swapoff "/dev/mapper/${VG}-swap"            2>/dev/null || true
vgchange -an "$VG"                          2>/dev/null || true
cryptsetup close "${HOST}_LUKS"             2>/dev/null || true

echo
if mountpoint -q "$MNT"; then
  echo "WARNING: $MNT is still mounted — something is holding it busy."
  echo "Find it with:  fuser -vm $MNT   /   lsof +D $MNT"
else
  echo "Teardown complete. Safe to reboot."
fi
