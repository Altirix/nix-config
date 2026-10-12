{ pkgs, ... }:

{
  # Mellanox ConnectX-4 (15b3:1013): raise PCIe MaxReadReq to 4096.
  # Device Control register bits 14:12, value 5 = 4096 bytes.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x15b3", ATTR{device}=="0x1013", \
      RUN+="${pkgs.pciutils}/bin/setpci -s %k CAP_EXP+8.w=5000:7000"
  '';
}
