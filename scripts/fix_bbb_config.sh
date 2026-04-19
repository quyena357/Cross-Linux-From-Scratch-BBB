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
