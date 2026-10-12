{ config, lib, ... }:

let
  mesh = config.mesh;

  netId =
    lib.fixedWidthString 4 "0" (toString mesh.nodeId);
in
{
  # Needed for traffic to go through a third node when a direct link is down.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv4.conf.default.forwarding" = 1;
  };

  # Fallback paths are asymmetric, strict rpfilter would drop them.
  networking.firewall.checkReversePath = "loose";

  services.frr = {
    # The NixOS module already writes hostname, log syslog and the service lines.
    config = ''
      log syslog informational
      !
      interface lo
       ip router openfabric 1
       openfabric passive
      !
      ${lib.concatMapStrings (interface: ''
        interface ${interface}
         ip router openfabric 1
         openfabric hello-interval 2
         openfabric hello-multiplier 3
        !
      '') mesh.interfaces}
      router openfabric 1
       net 49.0000.0000.0000.${netId}.00
       log-adjacency-changes
       lsp-gen-interval 1
       max-lsp-lifetime 65535
       lsp-refresh-interval 65000
    '';

    fabricd.enable = true;
  };
}
