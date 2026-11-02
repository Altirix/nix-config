# Host-side format and boot-contract checks for the signed kernel and USB image.
vbutil_kernel --verify "$kernelImage" --signpubkey "$devkeys/kernel_subkey.vbpubk"
vbutil_kernel --get-vmlinuz "$kernelImage" --vmlinuz-out kernel.itb
test "$(fdtget -t s kernel.itb /images/kernel-1 type)" = kernel_noload
test "$(fdtget -t s kernel.itb /images/kernel-1 arch)" = arm64
if fdtget kernel.itb /configurations default; then
  echo 'Unexpected fallback DTB' >&2
  exit 1
fi
test "$(fdtget -l kernel.itb /configurations | wc -l)" = 3
# Check the packed initrd and kernel contents, not just the FIT header.
index=0
for node in $(fdtget -l kernel.itb /images); do
  type=$(fdtget -t s kernel.itb "/images/$node" type)
  if [ "$type" = ramdisk ]; then
    dumpimage -T flat_dt -p "$index" -o recovered-initrd kernel.itb
    cmp recovered-initrd "$fixture/initrd"
  fi
  index=$((index + 1))
done
test -s recovered-initrd
dumpimage -T flat_dt -p 0 -o recovered-kernel kernel.itb
cmp recovered-kernel "$fixture/kernel"
dump_kernel_config "$kernelImage" > cmdline
grep -F 'kern_guid=%U' cmdline
grep -F "init=$fixture/init" cmdline
grep -F 'root=LABEL=nixos-root' cmdline

# Incomplete DTB sets must fail instead of producing a misleading image.
cp -r "$fixture" incomplete
chmod -R u+w incomplete
rm incomplete/dtbs/vendor/board-r2.dtb
if chromebook-pack-kernel incomplete broken.bin; then exit 1; fi
# Without the internal layout's kernel slots, the update hook must refuse before any write.
if chromebook-install-kernel "$fixture"; then exit 1; fi

image=$usbImage/installer.img
sgdisk -v "$image" | tee gpt-check
grep -F 'No problems found.' gpt-check
if grep -i corrupt gpt-check; then exit 1; fi
test "$(cgpt show -i 1 -b "$image")" = 2048
test "$(cgpt show -i 1 -s "$image")" = 262144
test "$(cgpt show -i 1 -P "$image")" = 10
test "$(cgpt show -i 1 -S "$image")" = 1
test "$(cgpt show -i 1 -t "$image")" = FE3A2A5D-4F32-41A7-B725-ACCC3285A309
test "$(cgpt show -i 2 -b "$image")" = 264192
dd if="$image" of=recovered-root bs=512 skip=264192 count=$(cgpt show -i 2 -s "$image") status=none
test "$(stat -c %s recovered-root)" = $(( $(stat -c %s "$rootfsImage") + 16 * 1024 * 1024 ))
e2fsck -fn recovered-root
debugfs -R 'cat /marker' recovered-root | grep -Fx chromebook-root-payload

# The recovery bundle holds a kernel naming its system, but no store references.
test "$(sed -n 3p recovery-graph)" = 0
vbutil_kernel --verify "$recovery/kernel.bin" --signpubkey "$devkeys/kernel_subkey.vbpubk"
test "$(cat "$recovery/rootfs-size")" = "$(stat -c %s "$rootfsImage")"

mkdir -p "$out"
cp gpt-check cmdline "$out/"
