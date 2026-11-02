# First installation from the USB installer: erases DISK, writes recovery and
# installs the carried host system. The host's SSH host key, and so its SOPS
# recipient, is HOST-KEY (generated off the board and already authorised), or
# else this installer's own key.
if [[ $# != 1 && $# != 2 ]]; then
  echo 'usage: chromebook-install DISK [HOST-KEY]' >&2
  exit 2
fi
if (( EUID != 0 )); then
  echo 'Run as root' >&2
  exit 1
fi
disk=$1
key=${2:-/etc/ssh/ssh_host_ed25519_key}
# Fails on anything but an unencrypted private key, before the disk is touched.
public=$(ssh-keygen -y -f "$key")
echo "Host SSH key: $key"
echo "SOPS recipient: $(ssh-to-age <<< "$public")"
lsblk -o PATH,SIZE,TYPE,TRAN,MODEL "$disk"
read -rp "Erase $disk and install NixOS? Type yes: " answer
if [[ $answer != yes ]]; then
  exit 1
fi

chromebook-partition "$disk"
chromebook-install-recovery /etc/chromebook-recovery

udevadm settle --timeout=60
root=$(readlink -f /dev/disk/by-partlabel/@root@)
mkfs.ext4 -F -L @root@ "$root"
mnt=$(mktemp -d)
mount "$root" "$mnt"
trap 'umount "$mnt"' EXIT
mkdir -p "$mnt/etc/nixos" "$mnt/etc/ssh"
cp -r /etc/chromebook-flake/. "$mnt/etc/nixos/"
chmod -R u+w "$mnt/etc/nixos"
install -m 600 "$key" "$mnt/etc/ssh/ssh_host_ed25519_key"
echo "$public" > "$mnt/etc/ssh/ssh_host_ed25519_key.pub"
nixos-install --root "$mnt" --system "$(readlink -f /etc/chromebook-system)" \
  --no-channel-copy --no-root-password
sync
echo "Installed. Power off, remove the USB stick and boot the internal disk."
