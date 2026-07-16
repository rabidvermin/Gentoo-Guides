# Gentoo Installation Guide

Full-disk encryption (LUKS1 + LVM) on UEFI/NVMe, using OpenRC and a binary kernel.

> **Last updated:** 2026-07-16

---

## Table of Contents

- [Conventions & Variables](#conventions--variables)
1. [Partitioning](#step-1-partitioning)
2. [LUKS Encryption](#step-2-luks-encryption)
3. [Open the LUKS Container](#step-3-open-the-luks-container)
4. [LVM Setup](#step-4-lvm-setup)
5. [Format Volumes](#step-5-format-volumes)
6. [Mount Point Setup](#steps-6-10-mount-point-setup)
7. [Sync Time](#step-11-sync-time)
8. [Download Stage3](#step-12-download-stage3)
9. [Verify Hashes](#step-13-verify-hashes)
10. [Unpack Stage3](#step-14-unpack-stage3)
11. [Chroot Prep](#steps-15-18-chroot-prep)
12. [Portage Setup](#steps-19-22-portage-setup)
13. [Base Configuration](#steps-23-25-base-configuration)
14. [Install Packages](#step-26-install-packages)
15. [fstab](#step-27-fstab)
16. [Dracut](#step-28-configure-dracut)
17. [Kernel Command Line](#step-29-kernel-command-line-handled-by-dracut)
18. [Install Kernel](#step-30-install-kernel)
19. [GRUB](#steps-31-34-grub)
20. [Finalise](#step-35-set-root-password)
21. [fstab Example](#fstab-example)
22. [References](#references)

---

## Step 0. Preparation

Use nearly any Linux Live ISO to boot the system. The one to select is dependant up on your system. For instance, the Gentoo Live ISO had challenges with an Nvidia RTX 5080. CachyOS was used in that instance as an alternative. There will be a trail and error process once you boot the system to see if it will work.

TIPS: 

1. Once booted, you can turn on SSH and the work on your built remotely from another system.
2. You can use an AI harness (Claude Code and others), give it an SSH key and have it log into the system to assist you. I have not used AI for a full install yet, but it may likely work.

> **⚠️ CachyOS / Arch-based live ISO warning:** Do **not** run `pacman -Syu` (or install a package with `pacman -Syu <pkg>`, which triggers a full upgrade) on the live session. It can upgrade the running kernel and delete the running kernel's modules, after which `modprobe` (dm-crypt, etc.) fails until you reboot the live USB. If it happens, just reboot the live ISO — the tmpfs overlay resets to the pristine kernel + matching modules.

---

## Conventions & Variables

Every command below uses these variables so you can copy-paste without editing device names or hostnames. **Set them once at the start of each shell** (re-export them if you open a new terminal or after you enter the chroot):

```bash
HOST=Mindpalace          # your hostname / LVM naming (change this)
DISK=/dev/nvme2n1        # target install disk — VERIFY with lsblk first!
EFI=${DISK}p1            # EFI System Partition
LUKS=${DISK}p2           # LUKS partition
VG=vg_${HOST}            # LVM volume group name
```

> **NVMe naming:** partitions use a `p` separator (`/dev/nvme2n1p1`), unlike SATA/USB disks (`/dev/sda1`). The `${DISK}p1` form handles this. For a SATA/USB target, use `EFI=${DISK}1` / `LUKS=${DISK}2` instead.

---

## Step 1. Partitioning

Use the lsblk and blkid commands to get a list of disks, make sure you only select the disk you want to install on:
<img width="1034" height="408" alt="image" src="https://github.com/user-attachments/assets/a9d49e32-cf51-40cd-bcec-baacea102077" />    
<br>
  

Use cfdisk to start your parition process. Make sure to replace the device with the disk you intenad to install Gentoo on, be cautious when working on a multidisk system where other devices have data you wish to retain. 

```bash
cfdisk "$DISK"
```  
<br>


If prompted, select gpt for the label type:

<img width="881" height="523" alt="image" src="https://github.com/user-attachments/assets/f6fdf84b-f069-49f5-ac4a-5c14241b2f13" />
<br>
  


Set partition 1 type to **EFI System**.

<img width="426" height="187" alt="image" src="https://github.com/user-attachments/assets/6ab0cc8c-e400-4728-aa93-d95c6bc0ebf2" />
<br>

You should see this now:
<img width="1031" height="200" alt="image" src="https://github.com/user-attachments/assets/3749b93a-bc24-4662-8ad7-187563fc2251" />
<br>

Partition the rest of the disk with type Linux File System (it will be selected automatically and safe to leave it that way), then select write:

<img width="1034" height="294" alt="image" src="https://github.com/user-attachments/assets/f6c84745-c502-47c7-b743-f9bf597decd4" />
<br>


lsblk after cfdisk write:

<img width="388" height="74" alt="image" src="https://github.com/user-attachments/assets/df1963b2-db5d-4b59-a6db-e72a771f0dd9" />
<br>


blkid after the cfdisk write:

<img width="599" height="93" alt="image" src="https://github.com/user-attachments/assets/a369d6d2-1353-40a0-b9f3-a15db677384d" />
<br>


---

## Step 2. LUKS Encryption

> **Critical:** You must use `--type luks1`. LUKS2 with the argon2id PBKDF is not supported by GRUB and will fail to boot. With LUKS1 the PBKDF is always `pbkdf2` (argon2id is a LUKS2-only feature), so `--pbkdf pbkdf2` below is the correct, non-contradictory choice.
>
> After formatting, verify with `cryptsetup luksDump "$LUKS"` — the header should read `Version: 1` (a LUKS1 dump has no `PBKDF:` line; a `Version: 2` header with `PBKDF: argon2id` would **not** boot).

```bash
 cryptsetup -v \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --iter-time 5000 \
    --pbkdf pbkdf2 \
    --type luks1 \
    --use-random \
    --verify-passphrase \
    luksFormat "$LUKS"
```

Here is a sample result:
<img width="1017" height="178" alt="image" src="https://github.com/user-attachments/assets/d54dd29a-ba7f-491b-aa0b-27b1029b0415" />



Verify the header:

```bash
cryptsetup luksDump "$LUKS"
```

<img width="644" height="421" alt="image" src="https://github.com/user-attachments/assets/bb912167-2b2a-47c7-8b7b-d8537430ad48" />



See also:
- https://forums.gentoo.org/viewtopic-t-1171423-start-0.html
- https://forums.gentoo.org/viewtopic-p-8819261.html

---

## Step 3. Open the LUKS Container

> Note: use `_` instead of `-` in the mapper name to avoid confusion with the LVM `vg_<name>-<lv>` naming.

```bash
cryptsetup luksOpen --allow-discards "$LUKS" ${HOST}_LUKS
```

![Step 3 — LUKS container opened](../images/image003.png)

confirm the container is up with the command 
```bash
ls -l /dev/mapper/${HOST}_LUKS
```

<img width="766" height="65" alt="image" src="https://github.com/user-attachments/assets/50b51a75-c1bc-4f58-ba37-69e0308d33f9" />


---

## Step 4. LVM Setup

```bash
pvcreate /dev/mapper/${HOST}_LUKS
vgcreate "$VG" /dev/mapper/${HOST}_LUKS

lvcreate -L64G   -Cy -n swap     "$VG"
lvcreate -L10G       -n rootfs   "$VG"
lvcreate -L40G       -n usr      "$VG"
lvcreate -L20G       -n var      "$VG"
lvcreate -L20G       -n opt      "$VG"
lvcreate -L30G       -n portage  "$VG"
lvcreate -L10G       -n src      "$VG"
lvcreate -L200G      -n home     "$VG"
lvcreate -L600G      -n data     "$VG"

mkswap /dev/mapper/${VG}-swap
mkfs.vfat -F32 "$EFI"
```

<img width="551" height="407" alt="image" src="https://github.com/user-attachments/assets/122bf9c6-3a6a-4096-aa75-134b9ce195e0" />


---

## Step 5. Format Volumes

Disks can be resized later, that is why we are using LVM. Something to remember: ext4 cannot be sized down without shutting the system off and performing the resize unmounted. 
An alternative file system, btrfs, can resize (shrink) while mounted — but adds CoW/complexity. This guide uses ext4.

ext4:

```bash
mkfs.ext4 /dev/mapper/${VG}-home
mkfs.ext4 /dev/mapper/${VG}-opt
mkfs.ext4 /dev/mapper/${VG}-portage
mkfs.ext4 /dev/mapper/${VG}-rootfs
mkfs.ext4 /dev/mapper/${VG}-src
mkfs.ext4 /dev/mapper/${VG}-usr
mkfs.ext4 /dev/mapper/${VG}-var
mkfs.ext4 /dev/mapper/${VG}-data
mkswap    /dev/mapper/${VG}-swap
```

![Step 5 — volumes formatted](../images/image005.png)

---

## Steps 6–10. Mount Point Setup

### Step 6. Create the install root

```bash
mkdir /mnt/install
```

### Step 7. Activate swap

```bash
swapon /dev/mapper/${VG}-swap
```

### Step 8. Mount root filesystem

```bash
mount /dev/mapper/${VG}-rootfs /mnt/install
```

### Step 9. Create and mount top-level directories + tmpfs

```bash
mkdir /mnt/install/{home,var,data,opt,usr,tmp}

mount /dev/mapper/${VG}-home  /mnt/install/home
mount /dev/mapper/${VG}-var   /mnt/install/var
mount /dev/mapper/${VG}-data  /mnt/install/data
mount /dev/mapper/${VG}-opt   /mnt/install/opt
mount /dev/mapper/${VG}-usr   /mnt/install/usr

mkdir /mnt/install/var/tmp
mount -t tmpfs -o size=1G  tmpfs /mnt/install/tmp
mount -t tmpfs -o size=16G tmpfs /mnt/install/var/tmp
```

### Step 10. Mount nested Portage / src volumes

These live **under the now-mounted `/usr`**, so create their mountpoints first (this is the step that fails if `/usr` isn't mounted or the dirs don't exist):

```bash
mkdir /mnt/install/usr/portage
mkdir /mnt/install/usr/src

mount /dev/mapper/${VG}-portage /mnt/install/usr/portage
mount /dev/mapper/${VG}-src     /mnt/install/usr/src
```

> **Note:** on a modern stage3 the ebuild tree defaults to `/var/db/repos/gentoo`, not `/usr/portage`. To actually use the `portage` LV at `/usr/portage`, point Portage there later via `/etc/portage/repos.conf` (`location = /usr/portage`) and set `DISTDIR`. `/usr/src` is the correct modern location for kernel sources.

---

## Step 11. Sync Time

An accurate clock matters for stage3 timestamps and HTTPS/GPG verification.

```bash
# On the Gentoo live CD:
emaint --auto sync
emerge net-misc/ntp
ntpdate -b -u 0.gentoo.pool.ntp.org
```

```bash
# On a CachyOS / systemd-based live ISO instead (already ships timesyncd):
timedatectl set-ntp true
timedatectl status            # want: System clock synchronized: yes
```

```bash
# Then, on either, write the correct time to the hardware clock:
date --utc
hwclock --systohc --utc
```

---

## Step 12. Download Stage3

Use the desktop/OpenRC stage3 tarball. In `links`, press **`d`** to download a file.

```bash
links http://www.gentoo.org/main/en/mirrors.xml
```

> The dated filenames below are examples — always grab the **current** snapshot and substitute its name in the verify/unpack commands.

---

## Step 13. Verify Hashes

```bash
cat stage3-amd64-desktop-openrc-<DATE>.tar.xz.sha256 | grep stage3
sha256sum stage3-amd64-desktop-openrc-<DATE>.tar.xz
```

![Step 13 — hash verification](../images/image006.png)

---

## Step 14. Unpack Stage3

```bash
cp -a stage3-amd64-desktop-openrc-<DATE>.tar.xz /mnt/install/
cd /mnt/install
tar xpvf stage3-amd64-desktop-openrc-<DATE>.tar.xz --xattrs-include='*.*' --numeric-owner
```

> Use `tar xpvf` (or `-J` for xz) — **not** `-j` (that's bzip2 and will error `is not a bzip2 file` on a `.tar.xz`).

---

## Steps 15–18. Chroot Prep

### Step 15. Copy resolv.conf

```bash
cp -L /etc/resolv.conf /mnt/install/etc/
```

### Step 16. Bind-mount kernel pseudo-filesystems

```bash
mount -t proc none       /mnt/install/proc
mount --rbind /sys       /mnt/install/sys
mount --rbind /dev       /mnt/install/dev
```

### Step 17. Mount EFI partition

```bash
mount "$EFI" /mnt/install/efi
```

> Mount the ESP at **`/efi`** (not `/boot`). In this design `/boot` is a directory on the encrypted root — that's what makes `GRUB_ENABLE_CRYPTODISK` meaningful. `grub-install --efi-directory=/efi` and the fstab both expect the ESP at `/efi`.

### Step 18. Enter the chroot

```bash
chroot /mnt/install /bin/bash
source /etc/profile
export PS1="(chroot) $PS1"
```

> Re-export your `HOST`/`DISK`/`EFI`/`LUKS`/`VG` variables inside the chroot if you'll keep using them.

---

## Steps 19–22. Portage Setup

### Step 19. Ebuild snapshot

```bash
emerge-webrsync
```

### Step 20. Update the ebuild repository

```bash
emerge --sync
```

### Step 21. Read news

```bash
eselect news list
eselect news read
```

### Step 22. Select profile

The profile index varies — run `eselect profile list` and pick the one you want (e.g. a `desktop/plasma` OpenRC profile), then set it by its number:

```bash
eselect profile list
eselect profile set 7      # <- replace 7 with the number from the list
```

<img width="692" height="861" alt="image" src="https://github.com/user-attachments/assets/e30a01c7-7297-413d-9567-6c76f8adcf9c" />


---

## Steps 23–25. Base Configuration

### Step 23. Install vim

```bash
emerge app-editors/vim
```



### Step 24a. Tune make.conf

```bash
# Inspect CPU capabilities (note the redirection: - </dev/null 2>&1)
gcc -march=native -E -v - </dev/null 2>&1 | grep cc1 | tr ' ' '\n' | grep -v mno
lscpu
cat /proc/cpuinfo

# Edit make.conf
vim /etc/portage/make.conf
```

Sample make.conf (the values below are for a specific machine — see the note after it):

```
# /etc/portage/make.conf
# Example — Intel i9-9900K (Skylake-class, 8c/16t), 128 GB RAM, RTX 5080

# ---- Compiler flags: dialed in for THIS CPU (skylake == the 9900K) ----
COMMON_FLAGS="-O2 -pipe -march=skylake -mtune=skylake \
-mmmx -msse -msse2 -msse3 -mssse3 -msse4.1 -msse4.2 -mpopcnt \
-mavx -mavx2 -mfma -mf16c -mbmi -mbmi2 -maes -mpclmul \
-madx -mabm -mlzcnt -mmovbe -mprfchw -mrdrnd -mrdseed \
-mfsgsbase -mfxsr -msahf -mcx16 -mclflushopt -msgx \
-mxsave -mxsavec -mxsaveopt -mxsaves \
--param l1-cache-size=32 --param l1-cache-line-size=64 --param l2-cache-size=16384"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
# Shortcut equivalent for a portable guide: COMMON_FLAGS="-march=native -O2 -pipe"

# ---- CPU SIMD feature flags (verify in chroot with: cpuid2cpuflags) ----
CPU_FLAGS_X86="aes avx avx2 f16c fma3 mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3"

# ---- Parallel build tuning (16 threads / 128 GB — core-bound) ----
MAKEOPTS="-j16 -l18"
EMERGE_DEFAULT_OPTS="--jobs=3 --load-average=18 --keep-going --verbose"
FEATURES="candy parallel-fetch"
PORTAGE_NICENESS="5"

# ---- Hardware ----
VIDEO_CARDS="nvidia"        # RTX 5080 (Blackwell) — see NVIDIA notes
INPUT_DEVICES="libinput"
GRUB_PLATFORMS="efi-64"

# ---- Licenses (NVIDIA driver is non-free) ----
ACCEPT_LICENSE="*"

# ---- USE (starter set; the desktop/plasma profile provides most — refine to taste) ----
USE="X wayland elogind dbus networkmanager pipewire -systemd"

# ---- Keep build output in English for bug reports ----
LC_MESSAGES=C.UTF-8

# ---- Optional: binary host for the monster packages (rust/llvm/chromium/etc.) ----
# After configuring /etc/portage/binrepos.conf + `getuto`, uncomment:
# FEATURES="${FEATURES} getbinpkg binpkg-request-signature"
# EMERGE_DEFAULT_OPTS="${EMERGE_DEFAULT_OPTS} --getbinpkg"

GENTOO_MIRRORS="https://mirrors.ocf.berkeley.edu/gentoo-distfiles https://distfiles.gentoo.org https://mirrors.rit.edu/gentoo https://gentoo.osuosl.org"
```

> **Portable tip:** the explicit `-march=skylake` flag list above is correct for *this* CPU only. For a guide others follow, use `COMMON_FLAGS="-march=native -O2 -pipe"` — `native` auto-detects each machine's CPU. Never copy another machine's explicit `-m` flag list; the wrong microarchitecture (e.g. `-march=meteorlake` on a Skylake chip) produces binaries that crash with `SIGILL`. Pick your `GENTOO_MIRRORS` with `mirrorselect -D` or a quick download benchmark.

### Step 24b. Set timezone

```bash
ls -al /usr/share/zoneinfo/US/Pacific
ln -sf ../usr/share/zoneinfo/US/Pacific /etc/localtime
```

### Step 25. Locales

```bash
# Edit /etc/locale.gen and uncomment/add:
#   en_US.UTF-8 UTF-8

locale-gen
locale -a

eselect locale list
eselect locale set en_US.utf8

env-update && source /etc/profile && export PS1="(chroot) $PS1"
```

---

## Step 26. Install Packages

```bash
emerge \
  sys-kernel/linux-firmware \
  sys-firmware/intel-microcode \
  net-misc/networkmanager \
  app-admin/doas \
  net-misc/dhcpcd \
  app-admin/syslog-ng \
  app-admin/logrotate \
  sys-process/cronie \
  sys-fs/e2fsprogs \
  sys-fs/dosfstools \
  media-gfx/flameshot \
  net-wireless/iwd \
  net-wireless/iw \
  net-wireless/wpa_supplicant \
  net-misc/netifrc \
  sys-fs/cryptsetup \
  sys-kernel/dracut \
  sys-boot/grub \
  sys-fs/lvm2 \
  app-portage/gentoolkit \
  sys-block/io-scheduler-udev-rules \
  net-misc/chrony \
  app-misc/fastfetch
```

> `sys-firmware/intel-microcode` is for Intel CPUs — use `sys-kernel/linux-firmware` alone (which includes `amd-ucode`) on AMD. dracut picks up the microcode image automatically for early loading.

> **Important — fixes the dracut "Module 'lvm' cannot be installed" error (Step 28):** `sys-fs/lvm2` defaults to a device-mapper-only build (no `/sbin/lvm`), which makes the forced dracut `lvm` module fail. Enable the `lvm` USE flag and rebuild:
>
> ```bash
> echo "sys-fs/lvm2 lvm" >> /etc/portage/package.use/lvm2
> emerge --newuse -1 sys-fs/lvm2
> ls -l /sbin/lvm        # should now exist
> ```

---

## Step 27. fstab

Generate a draft from `blkid`, then edit manually:

```bash
blkid | while read line; do \
  a=$(echo $line | awk -F ":" '{print $1}'); \
  b=$(echo $line | awk '{print $2}'); \
  echo -e "$b\t$a\text4\tnoatime\t0 1"; \
done
```

![Step 27 — blkid fstab generation](../images/image007.png)

See the [fstab example](#fstab-example) below for the final layout. The `/usr` line is required so dracut's `usrmount` module can mount the separate `/usr` in the initramfs.

---

## Step 28. Configure Dracut

Reference: https://wiki.gentoo.org/wiki/Dracut#LVM_on_LUKS

```bash
emerge -av sys-kernel/dracut

# Review UUIDs
blkid
```

![Step 28 — dracut / blkid UUIDs](../images/image008.png)

Key variables (get the UUIDs from `blkid` — they are unique per machine):

| Variable | Value |
|---|---|
| `root` | UUID of the rootfs LVM volume (`/dev/mapper/${VG}-rootfs`) |
| `rd.luks.uuid` | UUID of the LUKS partition (`$LUKS`, the `crypto_LUKS` UUID) |
| `rd.lvm.vg` | Name of the LVM volume group (`$VG`) |

Create `/etc/dracut.conf.d/luks.conf` (note the `usrmount` module for the separate `/usr`, and the **leading and trailing spaces** inside each `+=" … "` — dracut warns otherwise):

```
add_dracutmodules+=" crypt dm rootfs-block lvm usrmount "
kernel_cmdline+=" root=UUID=<rootfs-uuid> rd.luks.uuid=<luks-uuid> rd.lvm.vg=<vg-name> rootfstype=ext4 rd.luks.allow-discards "
```

Enable dracut and grub USE flags for the kernel installer:

```bash
echo "sys-kernel/installkernel grub dracut" >> /etc/portage/package.use/installkernel
```

> If the kernel install (Step 30) later fails with `Module 'lvm' cannot be installed`, you missed the `sys-fs/lvm2 lvm` USE-flag rebuild in Step 26.

---

## Step 29. Kernel Command Line (handled by dracut)

With the binary kernel (`gentoo-kernel-bin`) there is **no `/usr/src/linux/.config` to edit** — the kernel is prebuilt. The LUKS/LVM boot parameters come from the dracut `kernel_cmdline` you set in **Step 28** (`/etc/dracut.conf.d/luks.conf`), which dracut bakes into the initramfs. No action is needed here.

> Older versions of this guide edited `CONFIG_CMDLINE` in a source kernel tree — that is a no-op for the binary kernel and has been removed. If you keep the cmdline in dracut (as above), do **not** also set a conflicting `root=`/`rd.luks`/`rd.lvm` in `GRUB_CMDLINE_LINUX`.

---

## Step 30. Install Kernel

```bash
emerge -va gentoo-kernel-bin
```

Verify the initramfs picked up LUKS/LVM (and that the kernel landed in the encrypted `/boot`):

```bash
ls -l /boot                                            # vmlinuz-* + initramfs-*.img
lsinitrd /boot/initramfs-*.img | grep -E 'crypt|lvm'
```

---

## Steps 31–34. GRUB

### Step 31. Enable crypto support

Set this **before** generating the config so the auto-generated `grub.cfg` is crypto-aware:

```bash
echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
```

### Step 32. Install GRUB

Make sure the ESP is mounted at `/efi` (Step 17) first:

```bash
grub-install --efi-directory=/efi
```

### Step 33. Verify crypto flag is set

```bash
grep CRYPTODISK /etc/default/grub
```

### Step 34. Generate GRUB config

Write it to the **encrypted `/boot`**, not the ESP — GRUB's core image prefix points at `/boot/grub` inside the LUKS+LVM volume:

```bash
grub-mkconfig -o /boot/grub/grub.cfg
```

---

## Step 35. Set Root Password

```bash
passwd root
```

Before you reboot, also (in the chroot):

```bash
# hostname
echo "hostname=\"$HOST\"" > /etc/conf.d/hostname

# a normal user in wheel (for doas)
useradd -m -G wheel,audio,video,usb,plugdev <username>
passwd <username>
echo "permit persist :wheel" >> /etc/doas.conf

# enable services (OpenRC)
rc-update add elogind boot
rc-update add dbus default
rc-update add NetworkManager default
rc-update add sshd default
```

---

## Teardown & First Boot

Exit the chroot and unmount cleanly. The `/dev`, `/proc`, `/sys` rbinds are often "busy" on a recursive unmount — lazy-detach them first:

```bash
exit
cd /
sync
umount -l /mnt/install/dev /mnt/install/proc /mnt/install/sys
umount -R /mnt/install
swapoff /dev/mapper/${VG}-swap
vgchange -an "$VG"
cryptsetup close ${HOST}_LUKS
reboot
```

On first boot you'll be prompted for the LUKS passphrase **twice** — once by GRUB (to read encrypted `/boot`), once by the initramfs (to unlock root). That's expected; a keyfile embedded in the initramfs can eliminate the second prompt.

---

## fstab Example

> UUIDs are **per-machine** — get yours from `blkid`. Sizes/paths below match this guide's layout (`data` volume, `/efi` ESP); adjust as needed.

```
# /etc/fstab

# EFI System Partition (unencrypted — restrict perms)
UUID=0687-0EF9                                  /efi        vfat    noatime,umask=0077  0 2

# Root
UUID=036b27c2-591c-42a8-aac3-6132a5fca6c2       /           ext4    noatime         0 1

# OS / data volumes
UUID=2c4de4db-3d4a-44ea-81e4-e4ca1528aee7       /usr        ext4    noatime         0 2
UUID=2b8d2055-b139-40af-93cc-5aff96a03863       /var        ext4    noatime         0 2
UUID=e9cf22a0-fbdb-43fb-b432-d271e057ccae       /opt        ext4    noatime         0 2
UUID=8df8072d-ba49-490a-a19f-a455347e7789       /home       ext4    noatime         0 2
UUID=18c82636-ccfa-4bc4-b044-b357dceebaa6       /data       ext4    noatime         0 2

# Nested Portage volumes (under the separate /usr)
UUID=d68b3914-fe34-4d80-b588-c36cb6253b22       /usr/portage ext4   noatime         0 2
UUID=95091910-920a-47b6-ac63-cb3e221ab582       /usr/src     ext4   noatime         0 2

# Swap
UUID=9f2604d3-e68a-460a-aa07-e538a4c6c526       none        swap    sw              0 0

# tmpfs (RAM-backed; keeps builds off the small /var LV)
tmpfs   /tmp      tmpfs   noatime,nosuid,nodev,size=16G   0 0
tmpfs   /var/tmp  tmpfs   noatime,size=32G                0 0
```

> No `/boot` line — `/boot` is a directory on the encrypted root (that's the point of `GRUB_ENABLE_CRYPTODISK`).

---

## References

### Official Gentoo Documentation
- [Gentoo Handbook: Disks](https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Disks)
- [LVM](https://wiki.gentoo.org/wiki/LVM)
- [Full Disk Encryption From Scratch](https://wiki.gentoo.org/wiki/Full_Disk_Encryption_From_Scratch#fstab_configuration)
- [Rootfs Encryption: LUKS target configuration](https://wiki.gentoo.org/wiki/Rootfs_encryption#LUKS_target_configuration)
- [Dracut: LVM on LUKS](https://wiki.gentoo.org/wiki/Dracut#LVM_on_LUKS)
- [GRUB: Install on encrypted partition](https://wiki.gentoo.org/wiki/GRUB#Install_on_encrypted_partition)
- [Kernel command-line parameters](https://wiki.gentoo.org/wiki/Kernel/Command-line_parameters)

### Gentoo Forums
- [LUKS1 requirement for GRUB](https://forums.gentoo.org/viewtopic-t-1171423-start-0.html)
- [argon2id PBKDF issue](https://forums.gentoo.org/viewtopic-p-8819261.html)
- [Additional boot discussion](https://forums.gentoo.org/viewtopic-p-8843694.html#8843694)
- [Forum thread](https://forums.gentoo.org/viewtopic-t-926264-start-0.html)

### Other
- [gentoo_install reference scripts](https://github.com/sergibarroso/gentoo_install)
- [Blog: Gentoo — the truth behind the myth](https://blog.desdelinux.net/en/gentoo-the-truth-behind-the-myth/)

### Video Guides

[![A Base Gentoo Installation](../images/image009.png)](https://youtu.be/2sOfX_Lb1As?si=gfqbk_odoL9V4MxG)

[![Let's Install Gentoo!](../images/image010.png)](https://www.youtube.com/live/TIua0x1YqU8?si=WZZHvER1MJKbpgGo)

[![Gentoo Install Tutorial (Encrypted via LUKS, LVM, UEFI)](../images/image011.png)](https://youtu.be/JjQJwt_z3iY?si=x4VeUdkta513yndB)

[![Installing Gentoo in LUKS is too hard they say...](../images/image012.png)](https://youtu.be/H-57yoB5Rbs?si=56-XRq9F-0k1-yrd)

- https://youtu.be/q9_sXkA4Rv8?si=GVK_StOU41Q_YFrz
