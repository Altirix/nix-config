# Writes U-Boot to the raw sectors of the boot disk (SD or eMMC), the ESP starts at 16M.
# Usage: rock5c-install-uboot /dev/mmcblkN
device="${1:?usage: rock5c-install-uboot /dev/mmcblkN}"

dd if=@uboot@ of="$device" seek=64 conv=fsync,notrunc
sync
