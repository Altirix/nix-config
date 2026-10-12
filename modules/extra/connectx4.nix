{ pkgs, ... }:

{
  # Mellanox ConnectX-4 (15b3:1013): raise PCIe MaxReadReq to 4096.
  # Device Control register bits 14:12, value 5 = 4096 bytes.
  #
  # Larger read requests mean fewer PCIe transactions per packet when the
  # NIC DMAs from host memory. Measured on andromeda (2 runs, A/B):
  #   MRRS  512: 56.83 Gbit/s, sd 0.02, cpu 76.4%
  #   MRRS 4096: 57.56 Gbit/s, sd 0.03, cpu 78.9%
  # ~+0.7 Gbit/s (+1.3%), well outside run-to-run noise.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x15b3", ATTR{device}=="0x1013", \
      RUN+="${pkgs.pciutils}/bin/setpci -s %k CAP_EXP+8.w=5000:7000"
  '';
}
