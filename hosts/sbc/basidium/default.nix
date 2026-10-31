{ ... }:

{
  imports = [
    ../../../modules/printer.nix
    ./hardware-configuration.nix
    ./storage.nix
  ];

  system.stateVersion = "26.05";

  # 5C Lite: everything this RK3582's OTP doesn't mark bad, instead of the vendor's 2x A76, no GPU.
  # ip-state 00 00 04: all cores, GPU and both decoders good, rkvenc1 bad.
  homelab.hardware.rock5c = {
    enable = true;
    unlocked = true;
    wifi = true;
  };

  # Credentials in secrets/sbc.yaml (wifi-ssid, wifi-psk).
  homelab.wifi.enable = true;

  homelab.klipper.printerConfig = ./printer.cfg;
}
