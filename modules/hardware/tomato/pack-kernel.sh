# A NixOS toplevel supplies the matching kernel, initrd, DTBs and command line.
if [[ $# != 2 ]]; then
  echo "usage: tomato-pack-kernel SYSTEM OUTPUT" >&2
  exit 2
fi
system=$(readlink -f "$1")
output=$(realpath -m "$2")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The rev3 DTB also matches rev4. Do not silently omit a supported revision.
dtbs=()
for rev in 1 2 3; do
  dtb="$system/dtbs/mediatek/mt8195-cherry-tomato-r$rev.dtb"
  test -s "$dtb"
  dtbs+=(-b "$dtb")
done

# Depthcharge supports FIT ramdisks on MT8195; no fixed RAM addresses or DTB
# initrd fixups are needed. kernel_noload lets firmware relocate the ARM64 Image.
mkimage -f auto -A arm64 -O linux -T kernel -C none \
  -n 'NixOS Tomato' -d "$system/kernel" -i "$system/initrd" \
  "${dtbs[@]}" "$work/kernel.itb"
fdtput -t s "$work/kernel.itb" /images/kernel-1 type kernel_noload
# Never fall back to an arbitrary DTB when firmware doesn't match this board.
fdtput -d "$work/kernel.itb" /configurations default

printf 'kern_guid=%%U init=%s/init %s\n' "$system" "$(cat "$system/kernel-params")" > "$work/cmdline"
# vboot's kernel command-line area is 4096 bytes including its terminator.
if (( $(stat -c %s "$work/cmdline") >= 4096 )); then
  echo 'Tomato kernel command line exceeds the vboot limit' >&2
  exit 1
fi
# The vboot utility requires a nonempty legacy bootloader stub, ignored by Depthcharge.
dd if=/dev/zero of="$work/bootloader" bs=512 count=1 status=none
vbutil_kernel --pack "$output" --version 1 --arch arm \
  --vmlinuz "$work/kernel.itb" --config "$work/cmdline" \
  --bootloader "$work/bootloader" \
  --keyblock @devkeys@/kernel.keyblock \
  --signprivate @devkeys@/kernel_data_key.vbprivk
vbutil_kernel --verify "$output" --signpubkey @devkeys@/kernel_subkey.vbpubk
