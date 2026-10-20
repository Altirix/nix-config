# Presses Enter on the serial console of Windows VMs starting with install media, so they boot the ISO without
# "Press any key to boot from CD or DVD". The firmware reads keys from serial too, Windows doesn't.
# Only while the root disk is still empty: the prompt is what keeps a VM with the ISO left attached from booting
# setup again, and the answer file wipes the disk. Setup's own reboots fall through to the installed Windows.
# Every member runs this for the VMs it hosts.
# Env: SELF
empty=$((1024 * 1024 * 1024))

press_enter() {
  # incus console wants a terminal, socat gives it one. Connecting takes the text console over from the web UI.
  for _ in $(seq 60); do
    printf '\r'
    sleep 0.5
  done | timeout 35 socat - EXEC:"incus console $1",pty,setsid,ctty > /dev/null 2>&1 || true
}

incus monitor --type=lifecycle --format=json |
  jq --unbuffered -r 'select(.metadata.action == "instance-started") | .metadata.source | ltrimstr("/1.0/instances/") | split("?")[0]' |
  while read -r name; do
    info=$(incus query "/1.0/instances/$name") || continue
    jq -e --arg self "$SELF" '
      .location == $self
      and (.expanded_config["image.os"] // "" | ascii_downcase | contains("windows"))
      and any(.expanded_devices[]; .type == "disk" and .path != "/" and has("boot.priority"))
    ' <<< "$info" > /dev/null || continue

    usage=$(incus query "/1.0/instances/$name/state" | jq '.disk.root.usage // 0') || continue
    ((usage < empty)) || continue

    echo "incus-windows-autoboot: booting $name from its install media"
    press_enter "$name" &
  done
