# Signed kernel for slot R, plus the root filesystem compressed and its
# uncompressed size, as chromebook-install-recovery expects.
mkdir -p "$out"
cp "$kernelImage" "$out/kernel.bin"
stat -c %s "$rootfsImage" > "$out/rootfs-size"
zstd -T"$NIX_BUILD_CORES" --no-progress "$rootfsImage" -o "$out/rootfs.img.zst"
