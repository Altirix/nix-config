{ lib, ... }:

# REA with dynamic analysis: it runs the samples it's given, so it's alone on its own VM, opens nothing
# outward, and its root is reset from a snapshot after use (modules/services/mcp/README.md). The router drops
# what it opens too. The only REA: one per agent session, projects under /var/lib/rea, which lives on its own
# volume (storage.nix), so resets keep it.
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
    # mcp.peacocks.me/rea/<project>/mcp. Add one per line of work that shouldn't share state.
    projects = [ "default" "ig5236" ];
    # 24G VM, REA gets 75%: a dozen sessions with Ghidra open at 1G (~1.5G each with the JVM's overhead).
    ghidraHeap = "1G";
    # Firmware RE: 42 of REA's 207 tools, ~12k tokens of schemas instead of ~840k.
    toolset = "firmware";
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
