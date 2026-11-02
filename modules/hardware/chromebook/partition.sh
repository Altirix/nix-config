# Erases DISK and creates the internal layout: kernel slots A, B and R, the
# recovery root and the NixOS root. Refuses USB/SD media, eMMC boot areas,
# partitions and the disk holding the running root.
if [[ $# != 1 ]]; then
  echo 'usage: chromebook-partition DISK' >&2
  exit 2
fi
disk=$(readlink -f "$1")
name=$(basename "$disk")
if [[ ! -b $disk || ! -e /sys/block/$name ]]; then
  echo "Not a whole disk: $1" >&2
  exit 1
fi
if [[ $name == *boot[0-9] || $name == *rpmb ]]; then
  echo "Refusing an eMMC boot or RPMB area: $disk" >&2
  exit 1
fi
if [[ $(lsblk -dno TRAN "$disk") == usb || $(cat "/sys/block/$name/device/type" 2> /dev/null) == SD ]]; then
  echo "Refusing removable media: $disk" >&2
  exit 1
fi
root_disk=$(lsblk -nro PKNAME "$(findmnt -nro SOURCE /)" || true)
if [[ $root_disk == "$name" ]]; then
  echo "Refusing the disk holding the running root: $disk" >&2
  exit 1
fi

kernel=+@kernelSizeMiB@M
sgdisk --zap-all \
  --new=1:2048:$kernel --typecode=1:7F00 --change-name=1:@kernelA@ \
  --new=2:0:$kernel --typecode=2:7F00 --change-name=2:@kernelB@ \
  --new=3:0:$kernel --typecode=3:7F00 --change-name=3:@kernelR@ \
  --new=4:0:+@recoverySizeMiB@M --typecode=4:8300 --change-name=4:@recovery@ \
  --new=5:0:0 --typecode=5:8300 --change-name=5:@root@ "$disk"
# sgdisk has the kernel re-read the table. udev then re-creates the partitions'
# by-partlabel links, briefly removing them, so wait for it to finish.
udevadm settle --timeout=120
for label in @kernelA@ @kernelB@ @kernelR@ @recovery@ @root@; do
  if [[ ! -e /dev/disk/by-partlabel/$label ]]; then
    echo "Partitions were created, but /dev/disk/by-partlabel/$label did not appear" >&2
    exit 1
  fi
done
