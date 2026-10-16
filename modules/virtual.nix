{ config, lib, ... }:

# Incus VMs running on the compute hosts.
{
  imports = [ ./services/vgpu/guest.nix ];

  homelab.secrets.groupFile = ../secrets/virtual.yaml;

  virtualisation.incus.agent.enable = lib.mkDefault true;

  # Only on the labs bridge.
  networking.firewall.allowedTCPPorts = [ 22 ];

  # `incus console` attaches to the serial port.
  boot.kernelParams = [ "console=tty1" "console=ttyS0" ];

  sops.secrets = {
    "virtual-hello" = {
      sopsFile = config.homelab.secrets.groupFile;
      key = "hello";
    };
  };
}
