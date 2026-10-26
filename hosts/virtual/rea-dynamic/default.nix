{ lib, ... }:

# REA with dynamic analysis: it runs the samples it's given, so it's alone on its own VM and its root is reset
# from a snapshot after use (modules/services/mcp/README.md). Root in the VM is assumed lost, so nothing in here
# contains it: the router drops every connection it opens and only lets the edge's tunnel in on 8101. The only
# REA: one per agent session, projects under /var/lib/rea, which lives on its own volume (storage.nix), so
# resets keep it.
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
  };

  # In no sops group (.sops.yaml) and no secrets.yaml of its own, so it holds nothing to decrypt. Samples run here.
  sops.secrets = lib.mkForce { };

  system.stateVersion = "26.05";
}
