# Confirms the booted A/B slot once the system is up. Booted from anything
# else (recovery, USB), there is nothing to confirm.
booted=$(booted_guid)
for slot in "$slot_a" "$slot_b"; do
  require_kernel_partition "$slot"
  if [[ -n $booted && $(partition_guid) == "$booted" ]]; then
    cgpt add -i "$part_index" -S 1 -T 0 "$part_disk"
    sync
    echo "Confirmed kernel slot $part_dev"
    exit 0
  fi
done
echo 'Not booted from slot A or B, nothing to confirm'
