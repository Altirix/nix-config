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
    # The router drops input from labs, so not its resolver.
    dns = [ "1.1.1.1" "1.0.0.1" ];
  };

  # time.cloudflare.com by address, so time needs no DNS: the router lets the shared zone (no other connections)
  # reach exactly these (networking/README.md), tokens and passkeys there depend on the clock.
  networking.timeServers = [ "162.159.200.1" "162.159.200.123" ];

  virtualisation.incus.agent.enable = lib.mkDefault true;

  networking.nftables.enable = true;
  networking.firewall.enable = true;

  # Only on the labs bridge.
  networking.firewall.allowedTCPPorts = [ 22 ];

  # `incus console` attaches to the serial port.
  boot.kernelParams = [ "console=tty1" "console=ttyS0" ];

}
