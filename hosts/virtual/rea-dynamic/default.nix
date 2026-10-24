{ lib, ... }:

# REA with dynamic analysis: it runs the samples it's given, so it's alone on its own VM, opens nothing
# outward, and its root is reset from a snapshot after use (modules/services/mcp/README.md). The router drops
# what it opens too. The only REA: one server per project, one REA process per agent session.
# Samples and project state live on their own volume (storage.nix), so resets keep them.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  homelab.mcp.rea = {
    dynamic = true;
    firmware = true;
    # mcp.peacocks.me/rea-dynamic/<project>/mcp. Add one per line of work that shouldn't share state.
    projects = [ "default" ];
    # Reachable only through the edge's tunnel (token-gated). Add a LAN agent here to also reach 8101
    # directly. The router must let the tunnel into labs (it already does).
    clients = [ "10.0.0.1" ];
  };

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
