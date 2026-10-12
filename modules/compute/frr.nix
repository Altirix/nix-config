{ config, lib, ... }:

let
  mesh = config.mesh;

  routerIp = "10.255.0.${toString mesh.nodeId}";

  netId =
    lib.fixedWidthString 4 "0" (toString mesh.nodeId);
in
{
  # Unnumbered links: reuse the loopback /32 on every mesh interface so
  # hellos carry an IPv4 address and FRR has a next hop to install.
  systemd.network.networks = lib.listToAttrs (lib.imap0 (i: _: {
    name = "mesh-${toString i}";
    value.address = [ "${routerIp}/32" ];
  }) mesh.interfaces);

  # Needed for traffic to go through a third node when a direct link is down.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv4.conf.default.forwarding" = 1;
  };

  networking.firewall = {
    trustedInterfaces = mesh.interfaces;
    # Fallback paths are asymmetric, strict rpfilter would drop them.
    checkReversePath = "loose";
  };

  services.frr = {
    config = ''
      hostname ${config.networking.hostName}
      log syslog informational

      interface lo
       ip router openfabric 1
       openfabric passive

      ${lib.concatMapStrings (interface: ''
        interface ${interface}
         ip router openfabric 1
         openfabric network point-to-point
         openfabric hello-interval 2
         openfabric hello-multiplier 3
      '') mesh.interfaces}

      router openfabric 1
       net 49.0000.0000.0000.${netId}.00
       lsp-gen-interval 5
       max-lsp-lifetime 65535
       lsp-refresh-interval 65000
    '';

    fabricd.enable = true;
  };
}
