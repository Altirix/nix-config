{ lib, ... }:

# REA with dynamic analysis: it runs the samples it's given, so it's alone on its own VM, opens nothing
# outward, and is reset from a snapshot after use (modules/services/mcp/README.md). The router drops what
# it opens too.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  homelab.mcp.servers.rea.enable = true;
  homelab.mcp.rea.dynamic = true;
  homelab.mcp.rea.firmware = true;

  # Reachable only through the edge's tunnel (mcp.peacocks.me/rea-dynamic/mcp, token-gated). Add a LAN agent
  # here to also reach 8101 directly. The router must let the tunnel into labs (it already does).
  homelab.mcp.servers.rea.clients = [ "10.0.0.1" ];

  # Not in .sops.yaml, so drop the placeholders every host declares: nothing to decrypt, nothing to leak.
  sops.secrets = lib.mkForce { };

  # Nothing leaves the VM unless it answers a connection made to it. REA, Ghidra and JADX only talk over
  # loopback, deploys push the closure in over ssh.
  networking.nftables.tables.egress = {
    family = "inet";
    content = ''
      chain output {
        type filter hook output priority filter; policy drop;
        oifname "lo" accept
        ct state established,related accept
        # Untracked, but IPv6 clients can't reach the VM without them.
        icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert } accept
      }
    '';
  };

  system.stateVersion = "26.05";
}
