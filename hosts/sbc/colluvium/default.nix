{ ... }:
{
  imports = [ ../../../modules/sbc.nix ];

  homelab.hardware.tomato = {
    enable = true;
    wifi = true;
  };

  # Stock Depthcharge boots signed kernel slots on the eMMC, no ESP; the root
  # filesystem and layout come from modules/hardware/chromebook. See hosts/sbc/tomato.md.

  # AX200 firmware is selected by the Tomato hardware module. Wi-Fi SSID
  # and PSK are decrypted from secrets/sbc.yaml with the preserved host key.
  system.stateVersion = "26.05";
}
