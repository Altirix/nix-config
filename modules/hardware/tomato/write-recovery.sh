# Writes the recovery kernel (R) and its root filesystem. R is the lowest
# priority bootable slot, used only when A and B both fail.
if [[ $# != 3 ]]; then
  echo 'usage: tomato-write-recovery KERNEL-PARTITION ROOT-PARTITION RECOVERY' >&2
  exit 2
fi
recovery=$3
for f in kernel.bin rootfs.img.zst rootfs-size; do
  if [[ ! -f $recovery/$f ]]; then
    echo "Missing $recovery/$f" >&2
    exit 1
  fi
done
resolve_partition "$2"
root_dev=$part_dev root_disk=$part_disk
if findmnt -S "$root_dev" > /dev/null; then
  echo "Refusing to overwrite a mounted filesystem: $root_dev" >&2
  exit 1
fi
if (( $(cat "$recovery/rootfs-size") > $(blockdev --getsize64 "$root_dev") )); then
  echo "Recovery root filesystem does not fit $root_dev" >&2
  exit 1
fi
require_kernel_partition "$1"
if [[ $part_disk != "$root_disk" ]]; then
  echo "Recovery kernel and root must be on the same disk: $part_dev $root_dev" >&2
  exit 1
fi

cgpt add -i "$part_index" -P 0 -S 0 -T 0 "$part_disk"
write_raw "$recovery/kernel.bin" "$part_dev"
zstd -dc "$recovery/rootfs.img.zst" | dd of="$root_dev" bs=4M conv=fsync status=none
# The image is shrunk to its contents; grow it to the partition.
e2fsck -fy "$root_dev" || (( $? <= 1 ))
resize2fs "$root_dev"
cgpt add -i "$part_index" -P 1 -S 1 -T 0 "$part_disk"
sync
