{ config, lib, ... }:

# Incus VMs running on the compute hosts.
{
  imports = [
    ./networking/labs.nix
    ./networking/labs-mesh.nix
    ./services/vgpu/guest.nix
    ./services/mcp
    ./services/logs/collector.nix
    ./services/partdb
  ];

  homelab.secrets.groupFile = ../secrets/virtual.yaml;

  # Address ranges: networking/README.md.
  homelab.labs = {
    gateway = "10.100.0.1";
    # The router drops input from labs, so not its resolver.
    dns = [ "1.1.1.1" "1.0.0.1" ];
  };

  # Time from the router's NTP server, the one thing labs may open on it (networking/README.md): every zone keeps
  # its clock without reaching out, the shared zone included.
  networking.timeServers = [ config.homelab.labs.gateway ];

  virtualisation.incus.agent.enable = lib.mkDefault true;

  networking.nftables.enable = true;
  networking.firewall.enable = true;

  # Only on the labs bridge.
  networking.firewall.allowedTCPPorts = [ 22 ];

  # `incus console` attaches to the serial port.
  boot.kernelParams = [ "console=tty1" "console=ttyS0" ];

}
