#!/bin/bash
set -e

# Kasumi integration script for Android GKI kernels

if [ -z "$1" ]; then
    echo "Usage: $0 <kernel_dir> [defconfig]"
    echo "  [defconfig] is optional, e.g., gki_defconfig, vendor_defconfig"
    exit 1
fi

KDIR=$(readlink -f "$1")
DEFCONFIG=$2

if [ ! -d "$KDIR/drivers" ]; then
    echo "Error: $KDIR does not appear to be a valid kernel source tree (no 'drivers' directory)."
    exit 1
fi

KASUMI_DIR=$(dirname $(readlink -f "$0"))
TARGET_DIR="$KDIR/drivers/kasumi"

echo "[*] Integrating Kasumi into kernel at: $KDIR"

# 1. Copy source files to kernel tree
if [ -d "$TARGET_DIR" ]; then
    echo "[*] Removing existing drivers/kasumi..."
    rm -rf "$TARGET_DIR"
fi

echo "[*] Copying Kasumi source to drivers/kasumi..."
cp -r "$KASUMI_DIR/src" "$TARGET_DIR"

# 2. Generate Kconfig for in-tree compilation
cat << 'EOF' > "$TARGET_DIR/Kconfig"
config KASUMI
	tristate "Kasumi LKM for Android GKI"
	default m
	help
	  Kasumi is an out-of-tree Linux kernel module (kasumi_lkm.ko) 
	  for Android GKI/Linux path control. It provides redirection, 
	  hiding, merge/injection, and spoofing behavior.

	  Say M if you want to compile it as a module.
EOF

# 3. Modify Makefile to support CONFIG_KASUMI
# Replace obj-m with obj-$(CONFIG_KASUMI)
sed -i 's/obj-m += kasumi_lkm.o/obj-$(CONFIG_KASUMI) += kasumi_lkm.o/g' "$TARGET_DIR/Makefile"

# 4. Patch drivers/Makefile
if ! grep -q "obj-\$(CONFIG_KASUMI)" "$KDIR/drivers/Makefile"; then
    echo "[*] Patching drivers/Makefile..."
    echo "obj-\$(CONFIG_KASUMI)		+= kasumi/" >> "$KDIR/drivers/Makefile"
else
    echo "[*] drivers/Makefile already patched."
fi

# 5. Patch drivers/Kconfig
if ! grep -q "source \"drivers/kasumi/Kconfig\"" "$KDIR/drivers/Kconfig"; then
    echo "[*] Patching drivers/Kconfig..."
    # Insert source statement before the last 'endmenu'
    sed -i '/endmenu/i source "drivers/kasumi/Kconfig"' "$KDIR/drivers/Kconfig"
else
    echo "[*] drivers/Kconfig already patched."
fi

# 6. Add CONFIG_KASUMI to defconfig
patch_defconfig() {
    local config_file="$1"
    if [ -f "$config_file" ]; then
        if ! grep -q "CONFIG_KASUMI=" "$config_file"; then
            echo "[*] Adding CONFIG_KASUMI=m to $config_file..."
            echo -e "\n# Kasumi LKM\nCONFIG_KASUMI=m" >> "$config_file"
        else
            echo "[*] CONFIG_KASUMI already exists in $config_file."
        fi
    fi
}

if [ -n "$DEFCONFIG" ]; then
    # User provided a specific defconfig
    patch_defconfig "$KDIR/arch/arm64/configs/$DEFCONFIG"
    patch_defconfig "$KDIR/arch/x86/configs/$DEFCONFIG"
else
    # Default to gki_defconfig if none provided
    echo "[*] No specific defconfig provided. Defaulting to gki_defconfig..."
    patch_defconfig "$KDIR/arch/arm64/configs/gki_defconfig"
    patch_defconfig "$KDIR/arch/x86/configs/gki_defconfig"
fi

echo "[*] Setup complete! Kasumi has been added to the kernel tree."
