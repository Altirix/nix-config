{ config, lib, ... }:

# Incus VMs running on the compute hosts.
{
  imports = [
    ./networking/labs.nix
    ./networking/labs-mesh.nix
    ./services/vgpu/guest.nix
    ./services/mcp
    ./services/inventree
    ./services/logs/collector.nix
    ./services/paperless
    ./services/partdb
    ./services/home-assistant
    ./services/sso/server.nix
  ];

  # Its size, carried by its pin profile (modules/compute.nix): set here, not with `incus config set` on the
  # instance, which would override the profile. null keeps Incus' default (1 vCPU, 1 GiB, the pool's disk size). CPUs
  # change live, memory and disk at the next restart. A disk only grows: the root partition and filesystem follow it at
  # boot (growPartition, autoResize).
  options.homelab.vm = {
    cpus = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
    };
    memory = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "4GiB";
    };
    disk = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "32GiB";
    };
  };

  config = {
    # Address ranges: networking/README.md.
    homelab.labs = {
      gateway = "10.100.0.1";
      # The router drops input from labs, so not its resolver.
      dns = [ "1.1.1.1" "1.0.0.1" ];
    };

    # Time from the router's NTP server, the one thing labs may open on it (Altirix/Mikrotik): every zone keeps
    # its clock without reaching out, the shared zone included (Kanidm's tokens and passkeys depend on it).
    networking.timeServers = [ config.homelab.labs.gateway ];

    virtualisation.incus.agent.enable = lib.mkDefault true;

    networking.nftables.enable = true;
    networking.firewall.enable = true;

    # Only on the labs bridge.
    networking.firewall.allowedTCPPorts = [ 22 ];

    # `incus console` attaches to the serial port.
    boot.kernelParams = [ "console=tty1" "console=ttyS0" ];

    # A bigger disk (homelab.vm.disk) is used at the next boot: the root partition, last on the disk, grows to fill it,
    # then its filesystem.
    boot.growPartition = true;
    fileSystems."/".autoResize = true;
  };
}
