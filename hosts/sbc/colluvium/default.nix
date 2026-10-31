{ ... }:
{
  imports = [ ../../../modules/sbc.nix ];

  homelab.hardware.tomato = {
    enable = true;
    wifi = true;
  };

  # GPT kernel partition + ext4 root on eMMC; see hosts/sbc/tomato.md.
  # No ESP: stock Depthcharge reads the signed FIT directly from the raw partition.
  fileSystems."/" = {
    device = "/dev/disk/by-label/tomato-root";
    fsType = "ext4";
  };

  # AX200 firmware is selected by the Tomato hardware module. Wi-Fi SSID
  # and PSK are decrypted from secrets/sbc.yaml with the preserved host key.
  system.stateVersion = "26.05";
}
