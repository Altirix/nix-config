# Internal disk layout shared by the module, its scripts and the tests.
# Partition (GPT) labels; the two root filesystems use the same names as ext4 labels.
{
  kernelA = "nixos-kern-a";
  kernelB = "nixos-kern-b";
  kernelR = "nixos-kern-r";
  recovery = "nixos-recovery";
  root = "nixos-root";
  kernelSizeMiB = 128;
  recoverySizeMiB = 4096;
  # The USB installer's root, distinct so it never stands in for an internal one.
  usbRoot = "NIXOS-CB-USB";
}
