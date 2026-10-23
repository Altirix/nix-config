{ config, lib, ... }:

# Incus VMs running on the compute hosts.
{
  imports = [
    ./networking/labs.nix
    ./networking/labs-mesh.nix
    ./services/vgpu/guest.nix
    ./services/mcp
  ];

  homelab.secrets.groupFile = ../secrets/virtual.yaml;

  # Address ranges: networking/README.md.
  homelab.labs = {
    gateway = "10.100.0.1";
    dns = [ "10.100.0.1" ];
  };

  virtualisation.incus.agent.enable = lib.mkDefault true;

  networking.nftables.enable = true;
  networking.firewall.enable = true;

  # Only on the labs bridge.
  networking.firewall.allowedTCPPorts = [ 22 ];

  # `incus console` attaches to the serial port.
  boot.kernelParams = [ "console=tty1" "console=ttyS0" ];

}
