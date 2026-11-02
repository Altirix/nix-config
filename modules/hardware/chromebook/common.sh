# Shared by the slot scripts. Slots A and B alternate between updates; R holds
# recovery. Priority 3 is a new kernel on trial, 2 the confirmed previous one, 1 R.
kernel_type=FE3A2A5D-4F32-41A7-B725-ACCC3285A309
# Each script uses only some of these paths.
# shellcheck disable=SC2034
{
  slot_a=/dev/disk/by-partlabel/@kernelA@
  slot_b=/dev/disk/by-partlabel/@kernelB@
  slot_r=/dev/disk/by-partlabel/@kernelR@
  recovery_root=/dev/disk/by-partlabel/@recovery@
}
cmdline=${CHROMEBOOK_CMDLINE:-/proc/cmdline}

# Sets part_dev, part_disk and part_index for a partition path. udev briefly
# drops a partition's links while re-probing it after a write, so let it finish
# first. Best effort: inside nixos-enter udev may not be reachable.
resolve_partition() {
  udevadm settle --timeout=60 2> /dev/null || true
  part_dev=$(readlink -f "$1")
  if [[ ! -b "$part_dev" ]]; then
    echo "Not a block device: $1" >&2
    exit 1
  fi
  local name
  name=$(basename "$part_dev")
  part_index=$(cat "/sys/class/block/$name/partition")
  part_disk="/dev/$(basename "$(dirname "$(readlink -f "/sys/class/block/$name")")")"
}

require_kernel_partition() {
  resolve_partition "$1"
  local type
  type=$(cgpt show -i "$part_index" -t "$part_disk")
  if [[ ${type^^} != "$kernel_type" ]]; then
    echo "Refusing to use a non-ChromeOS-kernel partition: $part_dev" >&2
    exit 1
  fi
}

# Unique GUID of the kernel partition Depthcharge booted (kern_guid=%U).
booted_guid() {
  local arg args
  read -ra args < "$cmdline"
  for arg in "${args[@]}"; do
    if [[ $arg == kern_guid=* ]]; then
      echo "${arg#kern_guid=}" | tr '[:lower:]' '[:upper:]'
      return
    fi
  done
}

partition_guid() {
  cgpt show -i "$part_index" -u "$part_disk" | tr '[:lower:]' '[:upper:]'
}

# Run before changing any GPT attributes, so a payload that does not fit
# leaves the existing slot bootable.
require_fits() {
  if (( $1 > $(blockdev --getsize64 "$2") )); then
    echo "$3 does not fit $2" >&2
    exit 1
  fi
}

write_raw() {
  dd if="$1" of="$2" bs=4M conv=fsync,notrunc status=none
}
