# Cross-Linux-From-Scratch-BBB

This repository documents a complete Cross Linux From Scratch (CLFS) build for BeagleBone Black (BBB) using an ARM target and Ubuntu 16.04 host.

## Overview

This guide is based on the CLFS Embedded ARM bootable kernel documentation:

- <https://clfs.org/view/clfs-embedded/arm/bootable/kernel.html>

It covers:

- Host environment
- CLFS build variables
- Kernel configuration for BBB
- Kernel build commands
- U-Boot bootloader build
- SD card image creation and export to Windows

## Host Environment

Host machine:

- Ubuntu 16.04.07 (downloaded from <https://www.linuxvmimages.com/images/ubuntu-1604/>)
- Running in VMware

Target hardware:

- BeagleBone Black

## CLFS Build Variables

For the BeagleBone Black build, use the following environment variables:

```bash
export CLFS_FLOAT="hard"
export CLFS_FPU="vfpv3"
export CLFS_HOST=$(echo ${MACHTYPE} | sed "s/-[^-]*/-cross/")
export CLFS_TARGET="arm-linux-musleabihf"
export CLFS_ARCH=arm
export CLFS_ARM_ARCH="armv7-a"
```

These settings ensure the target is ARMv7 hard-float Linux with MUSL and the correct cross-host naming.

## Kernel Configuration for BeagleBone Black

A shell script can be used to set required kernel configuration options before building.

Save this as `fix_bbb_config.sh` and run it from the Linux kernel source root.

```bash
#!/bin/bash
set -e

echo "[INFO] Fixing kernel config for BeagleBone Black..."

# Ensure scripts/config exists
if [ ! -f "./scripts/config" ]; then
    echo "[INFO] Building kernel scripts..."
    make scripts
fi

CFG=./scripts/config

# =========================
# 1. PLATFORM (AM335x)
# =========================
$CFG --enable CONFIG_ARCH_OMAP
$CFG --enable CONFIG_ARCH_OMAP2PLUS
$CFG --enable CONFIG_SOC_AM33XX

# =========================
# 2. DEVICE TREE
# =========================
$CFG --enable CONFIG_OF
$CFG --enable CONFIG_OF_EARLY_FLATTREE

# =========================
# 3. SERIAL (CRITICAL)
# =========================
$CFG --enable CONFIG_SERIAL_8250
$CFG --enable CONFIG_SERIAL_8250_CONSOLE
$CFG --enable CONFIG_SERIAL_8250_OMAP
$CFG --enable CONFIG_SERIAL_8250_OMAP_TTYO_FIXUP
$CFG --enable CONFIG_SERIAL_OF_PLATFORM

# Optional but safe
$CFG --enable CONFIG_SERIAL_OMAP
$CFG --enable CONFIG_SERIAL_OMAP_CONSOLE

# =========================
# 4. DEBUG (for bring-up)
# =========================
$CFG --enable CONFIG_DEBUG_LL
$CFG --enable CONFIG_EARLY_PRINTK
$CFG --enable CONFIG_SERIAL_EARLYCON
$CFG --enable CONFIG_DEBUG_UART
$CFG --enable CONFIG_DEBUG_UART_8250

# =========================
# 5. MMC / SD (CRITICAL)
# =========================
$CFG --enable CONFIG_MMC
$CFG --enable CONFIG_MMC_OMAP_HS

# =========================
# 6. FILESYSTEMS
# =========================
$CFG --enable CONFIG_EXT4_FS
$CFG --enable CONFIG_MSDOS_FS
$CFG --enable CONFIG_VFAT_FS

# =========================
# 7. BLOCK DEVICES
# =========================
$CFG --enable CONFIG_BLK_DEV
$CFG --enable CONFIG_BLK_DEV_SD

# =========================
# 8. BASIC SYSTEM
# =========================
$CFG --enable CONFIG_BINFMT_ELF
$CFG --enable CONFIG_UNIX
$CFG --enable CONFIG_SYSVIPC
$CFG --enable CONFIG_PROC_FS
$CFG --enable CONFIG_SYSFS

# =========================
# 9. DEVTMPFS (VERY USEFUL)
# =========================
$CFG --enable CONFIG_DEVTMPFS
$CFG --enable CONFIG_DEVTMPFS_MOUNT

# =========================
# 10. ENSURE BUILT-IN (NOT MODULE)
# =========================
$CFG --disable CONFIG_MMC_OMAP
$CFG --disable CONFIG_MMC_OMAP_HS_MODULE

echo "[INFO] Applying dependencies..."
make ARCH=arm olddefconfig

echo "[INFO] Config fix complete."
```

Usage:

```bash
chmod +x fix_bbb_config.sh
./fix_bbb_config.sh
```

## Kernel Build

After configuring the kernel, build the ARM kernel image and device tree blobs:

```bash
make ARCH=${CLFS_ARCH} CROSS_COMPILE=${CLFS_TARGET}-
```

This should produce `zImage` and `dtbs/am335x-boneblack.dtb` in the kernel build tree.

## U-Boot Bootloader

To build U-Boot for BeagleBone Black, follow these steps:

1. Clone the repository:

```bash
cd $CLFS/sources
git clone https://github.com/beagleboard/u-boot.git
cd u-boot
```

1. Checkout a stable version:

```bash
git checkout v2021.10
```

1. Configure for BBB:

```bash
make distclean
make ARCH=arm CROSS_COMPILE=${CLFS_TARGET}- am335x_evm_defconfig
```

1. Build U-Boot:

```bash
make ARCH=arm CROSS_COMPILE=${CLFS_TARGET}- -j$(nproc)
```

After a successful build, confirm the files exist:

```bash
ls MLO u-boot.img
```

If both files exist, U-Boot is ready for the boot partition.

## SD Card Image Build and Windows Sharing

Use an image builder script to create a bootable SD card image, copy kernel and bootloader files, install the CLFS root filesystem, and export the finished image to a VMware shared folder.

Example script:

```bash
#!/bin/bash
set -e

# =============================================================
# BBB SD Card Image Builder Script
# Builds a bootable SD card image for BeagleBone Black
# =============================================================

# --- Configuration (edit these paths as needed) ---
IMG_NAME="bbb-sd.img"
IMG_SIZE_MB=2048
BOOT_SIZE="+128M"
UBOOT_DIR="/mnt/clfs/sources/u-boot"
KERNEL_DIR="/mnt/clfs/sources/linux-4.9.22/arch/arm/boot"
ROOTFS_DIR="/mnt/clfs/targetfs"
# Set to a tarball path instead if using a tarball (leave empty to use directory)
ROOTFS_TAR=""
SHARED_FOLDER="/mnt/hgfs/shared_folder"

BOOT_MNT="/mnt/boot"
ROOTFS_MNT="/mnt/rootfs"

# =============================================================
# STEP 1 — Create empty image file
# =============================================================
echo ">>> STEP 1: Creating empty image file..."
cd ~
dd if=/dev/zero of="$IMG_NAME" bs=1M count="$IMG_SIZE_MB" status=progress

# =============================================================
# STEP 2 — Create partition table inside image
# =============================================================
echo ">>> STEP 2: Creating partition table..."

# Use sfdisk for scriptable partitioning
/sbin/sfdisk "$IMG_NAME" <<EOF
label: dos

# Partition 1: 128M FAT32 LBA, bootable
start=2048, size=262144, type=c, bootable

# Partition 2: rest of disk, Linux
start=264192, type=83
EOF

# =============================================================
# STEP 3 — Attach image as loop device
# =============================================================
echo ">>> STEP 3: Attaching image as loop device..."
LOOP_DEV=$(sudo losetup -f --show "$IMG_NAME")
echo "    Loop device: $LOOP_DEV"

sudo kpartx -av "$LOOP_DEV"
LOOP_BASE=$(basename "$LOOP_DEV")
PART1="/dev/mapper/${LOOP_BASE}p1"
PART2="/dev/mapper/${LOOP_BASE}p2"

# Wait for partition mappings to appear
sleep 1

# =============================================================
# STEP 4 — Format partitions
# =============================================================
echo ">>> STEP 4: Formatting partitions..."
sudo mkfs.vfat "$PART1"
sudo mkfs.ext4 -F "$PART2"

# =============================================================
# STEP 5 — Mount partitions
# =============================================================
echo ">>> STEP 5: Mounting partitions..."
sudo mkdir -p "$BOOT_MNT" "$ROOTFS_MNT"
sudo mount "$PART1" "$BOOT_MNT"
sudo mount "$PART2" "$ROOTFS_MNT"

# =============================================================
# STEP 6 — Copy bootloader files (order matters!)
# =============================================================
echo ">>> STEP 6: Copying bootloader files..."
sudo cp "$UBOOT_DIR/MLO" "$BOOT_MNT/"
sync
sudo cp "$UBOOT_DIR/u-boot.img" "$BOOT_MNT/"

echo "    Copying kernel and device tree..."
sudo cp "$KERNEL_DIR/zImage" "$BOOT_MNT/"
sudo cp "$KERNEL_DIR/dts/am335x-boneblack.dtb" "$BOOT_MNT/"

# STEP 6.1 — Create uEnv.txt
echo "    Creating uEnv.txt..."
sudo tee "$BOOT_MNT/uEnv.txt" > /dev/null <<'UENV'
console=ttyS0,115200n8
bootargs=console=ttyS0,115200 root=/dev/mmcblk0p2 rw rootwait

uenvcmd=load mmc 0:1 ${loadaddr} zImage; load mmc 0:1 ${fdtaddr} am335x-boneblack.dtb; bootz ${loadaddr} - ${fdtaddr}
UENV

echo "    Boot partition contents:"
ls -la "$BOOT_MNT/"

# =============================================================
# STEP 7 — Copy CLFS root filesystem
# =============================================================
echo ">>> STEP 7: Copying root filesystem..."
if [ -n "$ROOTFS_TAR" ] && [ -f "$ROOTFS_TAR" ]; then
    sudo tar -xpf "$ROOTFS_TAR" -C "$ROOTFS_MNT"
else
    sudo cp -a "$ROOTFS_DIR"/* "$ROOTFS_MNT/"
fi

# =============================================================
# STEP 8 — Cleanly detach image
# =============================================================
echo ">>> STEP 8: Unmounting and detaching..."
sync
sudo umount "$BOOT_MNT"
sudo umount "$ROOTFS_MNT"
sudo kpartx -d "$LOOP_DEV"
sudo losetup -d "$LOOP_DEV"

echo ">>> Image '$IMG_NAME' is complete!"

# =============================================================
# STEP 9 — Copy image to Windows (via VMware shared folder)
# =============================================================
echo ">>> STEP 9: Copying image to shared folder..."
sudo mkdir -p /mnt/hgfs
sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other 2>/dev/null || true

if [ -d "$SHARED_FOLDER" ]; then
    cp ~/$IMG_NAME "$SHARED_FOLDER/"
    echo "    Copied to $SHARED_FOLDER/$IMG_NAME"
else
    echo "    WARNING: Shared folder '$SHARED_FOLDER' not found. Copy manually."
fi

# =============================================================
# STEP 10 — Flash with Balena Etcher
# =============================================================
echo ">>> STEP 10: Done! Now on Windows:"
echo "    1. Open Balena Etcher"
echo "    2. Select '$IMG_NAME'"
echo "    3. Select your SD card"
echo "    4. Flash"
echo "    5. Wait for verification"
echo ""
echo "=== Build complete! ==="
```

## Notes

- The script assumes the CLFS source tree is at `/mnt/clfs/sources` and the target filesystem is at `/mnt/clfs/targetfs`.
- Ensure VMware shared folders are mounted properly before copying the image to Windows.
- Use `Balena Etcher` on Windows to flash `bbb-sd.img` to the SD card.
- Verify serial console settings and kernel command line if the board does not boot.

## Useful Commands

- Verify the cross compiler target:

  ```bash
  echo $CLFS_TARGET
  ```

- Check kernel build output:

  ```bash
  file arch/arm/boot/zImage
  ```

- Confirm U-Boot files:

  ```bash
  ls -l $UBOOT_DIR/MLO $UBOOT_DIR/u-boot.img
  ```

## Summary

This README captures the steps needed to build a bootable CLFS system for BeagleBone Black from Ubuntu 16.04 host, including kernel configuration, U-Boot build, and image packaging for Windows sharing.
