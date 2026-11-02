# Called by NixOS's external bootloader hook, including from nixos-install.
# Writes the inactive A/B slot and puts it on a single trial boot: if it never
# reaches chromebook-mark-good, Depthcharge falls back to the confirmed slot, then R.
if [[ $# != 1 ]]; then
  echo 'usage: chromebook-install-kernel SYSTEM' >&2
  exit 2
fi
system=$1
require_kernel_partition "$slot_a"
a_dev=$part_dev a_index=$part_index disk=$part_disk a_guid=$(partition_guid)
require_kernel_partition "$slot_b"
b_dev=$part_dev b_index=$part_index b_guid=$(partition_guid)
if [[ $part_disk != "$disk" ]]; then
  echo "Slots A and B must be on the same disk: $a_dev $b_dev" >&2
  exit 1
fi

booted=$(booted_guid)
if [[ -n $booted && $booted == "$a_guid" ]]; then
  current=$a_index target=$b_index target_dev=$b_dev
elif [[ -n $booted && $booted == "$b_guid" ]]; then
  current=$b_index target=$a_index target_dev=$a_dev
else
  # Installer, recovery or USB: write A and leave B as it is.
  current='' target=$a_index target_dev=$a_dev
fi
if [[ -n $current && $(cgpt show -i "$current" -S "$disk") != 1 ]]; then
  echo 'The booted slot is not confirmed yet, refusing to overwrite the only known-good slot.' >&2
  echo 'Check systemctl status chromebook-mark-good, start it once the system is healthy, and retry.' >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
chromebook-pack-kernel "$system" "$work/kernel.bin"
require_fits "$(stat -c %s "$work/kernel.bin")" "$target_dev" 'Signed kernel'
# Invalidate before writing so interrupted writes are not treated as bootable.
cgpt add -i "$target" -P 0 -S 0 -T 0 "$disk"
write_raw "$work/kernel.bin" "$target_dev"
if [[ -n $current ]]; then
  cgpt add -i "$current" -P 2 "$disk"
elif (( $(cgpt show -i "$b_index" -P "$disk") > 2 )); then
  # Not booted from A/B: keep the new trial strictly ahead of B.
  cgpt add -i "$b_index" -P 2 "$disk"
fi
cgpt add -i "$target" -P 3 -S 0 -T 1 "$disk"
sync
