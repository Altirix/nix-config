{ config, lib, ... }:

# Incus VMs running on the compute hosts.
{
  imports = [
    ./networking/labs.nix
    ./networking/labs-mesh.nix
    ./services/vgpu/guest.nix
  ];

  homelab.secrets.groupFile = ../secrets/virtual.yaml;

  # Static services take 10.100.1.0/24 - 10.100.254.0/24 (10.100.0.0/24 is infra), the router's DHCP pool
  # stays in 10.100.255.0/24 and only serves setup.
  homelab.labs = {
    gateway = "10.100.0.1";
    dns = [ "10.100.0.1" ];
  };

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
