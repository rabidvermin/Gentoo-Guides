# Install helper scripts

Optional automation for the repetitive parts of the
[install guide](../guides/gentoo-luks-lvm-openrc.md). They cover the LVM,
format, mount, chroot, and teardown steps — the mechanical loops where
mistakes tend to happen.

**What stays manual (on purpose):** partitioning (`cfdisk`), LUKS
format/open (interactive passphrase), `make.conf` tuning, profile selection,
and the stage3 download. Those are interactive or per-machine decisions and
are more dangerous automated.

## Usage

1. Edit **`00-config.sh`** — set `HOST`, `DISK`, and the `LVS` size table.
   Everything else derives from these. **Double-check `DISK` against `lsblk`.**
2. Do the manual steps first: partition the disk (guide Step 1), then
   `luksFormat` + `luksOpen` the LUKS partition as `${HOST}_LUKS` (Steps 2-3).
3. Run the scripts in order:

   ```bash
   ./01-lvm.sh          # PV/VG/LVs + mkswap + format ESP   (Step 4)
   ./02-format.sh       # mkfs.ext4 on every non-swap LV     (Step 5)
   ./03-mount.sh        # mount the whole tree under /mnt/install (Steps 6-10,17)
   # ... unpack stage3 into /mnt/install (guide Step 14) ...
   ./04-chroot-prep.sh  # binds + drop into the chroot        (Steps 15-18)
   # ... do the in-chroot install (Steps 19-35) ...
   ./99-teardown.sh     # unmount + close everything, then reboot
   ```

## Safety

- Destructive scripts (`01`, `02`) print `lsblk`/the target list and require
  you to type **`yes`** before doing anything.
- **Dry run:** prefix any script with `DRYRUN=1` to print the commands without
  running them, e.g. `DRYRUN=1 ./01-lvm.sh`.
- Run these as **root** on the live environment.
