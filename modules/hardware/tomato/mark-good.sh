# Confirms the booted A/B slot once the system is up. Booted from anything
# else (recovery, USB), there is nothing to confirm.
if [[ $# != 2 ]]; then
  echo 'usage: tomato-mark-good SLOT-A SLOT-B' >&2
  exit 2
fi
booted=$(booted_guid)
for slot in "$1" "$2"; do
  require_kernel_partition "$slot"
  if [[ -n $booted && $(partition_guid) == "$booted" ]]; then
    cgpt add -i "$part_index" -S 1 -T 0 "$part_disk"
    sync
    echo "Confirmed kernel slot $part_dev"
    exit 0
  fi
done
echo 'Not booted from slot A or B, nothing to confirm'
