# Assemble without loop devices, root privileges or executing target binaries.
{ pkgs, kernelImage, rootfsImage, rootExtraSpaceMiB ? 1024 }:
pkgs.runCommand "tomato-installer-image" {
  nativeBuildInputs = [ pkgs.coreutils pkgs.vboot-utils pkgs.e2fsprogs ];
} ''
  mkdir -p $out
  image=$out/tomato-installer.img
  kernelStart=2048
  kernelSectors=262144 # 128 MiB
  rootStart=$((kernelStart + kernelSectors))
  # make-ext4-fs shrinks aggressively, including its inode tables. Unlike the
  # standard SD image this installer does not grow on boot: reserve space and
  # inodes for activation, store registration, logs and interactive use now.
  cp --reflink=auto --sparse=always ${rootfsImage} rootfs.img
  chmod u+w rootfs.img
  truncate -s +${toString rootExtraSpaceMiB}M rootfs.img
  resize2fs rootfs.img
  rootSectors=$((($(stat -c %s rootfs.img) + 511) / 512))
  test $(stat -c %s ${kernelImage}) -le $((kernelSectors * 512))
  # Leave space for the backup GPT as well as the primary GPT.
  truncate -s $(((rootStart + rootSectors + 2048) * 512)) "$image"
  cgpt create "$image"
  cgpt boot -p "$image"
  cgpt add -i 1 -b "$kernelStart" -s "$kernelSectors" -t kernel \
    -l TOMATO-USB-KERN -P 10 -S 1 -T 0 "$image"
  cgpt add -i 2 -b "$rootStart" -s "$rootSectors" -t data -l TOMATO-USB-ROOT "$image"
  dd if=${kernelImage} of="$image" bs=512 seek="$kernelStart" conv=notrunc,sparse status=none
  dd if=rootfs.img of="$image" bs=4M oflag=seek_bytes seek=$((rootStart * 512)) conv=notrunc,sparse status=none
  cgpt show "$image"
''
