{ config, lib, ... }:

let
  mesh = config.mesh;

  netId =
    lib.fixedWidthString 4 "0" (toString mesh.nodeId);
in
{
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