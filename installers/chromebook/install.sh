# First installation from the USB installer: erases DISK, writes recovery and
# installs the carried host system, keeping this installer's SSH host key so the
# host's SOPS recipient stays the one derived here.
if [[ $# != 1 ]]; then
  echo 'usage: chromebook-install DISK' >&2
  exit 2
fi
if (( EUID != 0 )); then
  echo 'Run as root' >&2
  exit 1
fi
disk=$1
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
install -m 600 /etc/ssh/ssh_host_ed25519_key "$mnt/etc/ssh/"
install -m 644 /etc/ssh/ssh_host_ed25519_key.pub "$mnt/etc/ssh/"
nixos-install --root "$mnt" --system "$(readlink -f /etc/chromebook-system)" \
  --no-channel-copy --no-root-password
sync
echo "Installed. Power off, remove the USB stick and boot the internal disk."
