# Called by NixOS's external bootloader hook, including from nixos-install.
if [[ $# != 3 ]]; then
  echo 'usage: tomato-install-kernel PACKER KERNEL-PARTITION SYSTEM' >&2
  exit 2
fi
packer=$1
partition=$(readlink -f "$2")
system=$3
if [[ ! -b "$partition" ]]; then
  echo "Not a block device: $partition" >&2
  exit 1
fi
name=$(basename "$partition")
index=$(cat "/sys/class/block/$name/partition")
disk="/dev/$(basename "$(dirname "$(readlink -f "/sys/class/block/$name")")")"
type=$(cgpt show -i "$index" -t "$disk")
if [[ ${type^^} != FE3A2A5D-4F32-41A7-B725-ACCC3285A309 ]]; then
  echo "Refusing to overwrite a non-ChromeOS-kernel partition: $partition" >&2
  exit 1
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
"$packer" "$system" "$work/kernel.bin"
if (( $(stat -c %s "$work/kernel.bin") > $(blockdev --getsize64 "$partition") )); then
  echo 'Signed kernel does not fit the kernel partition' >&2
  exit 1
fi
# Invalidate before writing so interrupted writes are not treated as bootable.
# Keep the USB installer for recovery: this layout has one kernel slot.
cgpt add -i "$index" -P 0 -S 0 -T 0 "$disk"
dd if="$work/kernel.bin" of="$partition" bs=4M conv=fsync,notrunc
cgpt add -i "$index" -P 10 -S 1 -T 0 "$disk"
sync
