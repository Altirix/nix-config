{ config, lib, ... }:

# Incus VMs running on the compute hosts.
{
  homelab.secrets.groupFile = ../secrets/virtual.yaml;

  virtualisation.incus.agent.enable = lib.mkDefault true;

  # `incus console` attaches to the serial port.
  boot.kernelParams = [ "console=tty1" "console=ttyS0" ];

  sops.secrets = {
    "virtual-hello" = {
      sopsFile = config.homelab.secrets.groupFile;
      key = "hello";
    };
  };
}
