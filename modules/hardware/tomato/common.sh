# Shared by the Tomato slot scripts. A/B kernel slots plus a recovery slot (R):
# priority 3 is a new kernel on trial, 2 the confirmed previous one, 1 recovery.
kernel_type=FE3A2A5D-4F32-41A7-B725-ACCC3285A309
cmdline=${TOMATO_CMDLINE:-/proc/cmdline}

# Sets part_dev, part_disk and part_index for a partition path.
resolve_partition() {
  part_dev=$(readlink -f "$1")
  if [[ ! -b "$part_dev" ]]; then
    echo "Not a block device: $part_dev" >&2
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

# Write a file to a raw partition, refusing anything larger than it.
write_raw() {
  if (( $(stat -c %s "$1") > $(blockdev --getsize64 "$2") )); then
    echo "$1 does not fit $2" >&2
    exit 1
  fi
  dd if="$1" of="$2" bs=4M conv=fsync,notrunc status=none
}
