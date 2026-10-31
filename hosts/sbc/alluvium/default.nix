{ ... }:

{
  imports = [
    ../../../modules/printer.nix
    ./hardware-configuration.nix
    ./storage.nix
  ];

  system.stateVersion = "26.05";

  # 5C Lite: everything this RK3582's OTP doesn't mark bad, instead of the vendor's 2x A76, no GPU.
  homelab.hardware.rock5c = {
    enable = true;
    unlocked = true;
    # ip-state 00 08 00: all cores, both decoders and encoders good, one GPU core bad (bit 3 of 1-4).
    # Single-core probe mask until the bad core is found, then 0x50005 minus its bit.
    gpuShaderMask = "0x1";
    wifi = true;
  };

  homelab.klipper.printerConfig = ./printer.cfg;
}
