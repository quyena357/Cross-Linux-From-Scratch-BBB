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
