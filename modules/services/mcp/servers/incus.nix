{ config, lib, pkgs, nodes, ... }:

# Read-only view of the incus cluster: instances, logs, networks, storage, members, resources.
# Read-only is enforced by incus, not here: the client certificate is the cluster's restricted
# mcp-incus one, which modules/compute/incus-restricted.star only lets view the default project
# and the cluster around it. A stolen key reads the same (instance config included) and changes
# nothing. The host sets INCUS_SERVER_CERT to the cluster certificate, the only one trusted.
#
# The mcp VM is on the labs bridge, and the members drop everything coming in from it
# (instance-isolation.nft). Their mesh addresses only route inside the mesh, so the API is reached
# on the mgmt addresses, through the site router, which has to let labs reach mgmt on 8443.
let
  cfg = config.homelab.mcp.servers.incus;
  incus-mcp = pkgs.callPackage ../packages/incus-mcp { };

  members = lib.filter (n: n.config.homelab.incus.enable or false) (lib.attrValues nodes);
  # The API is only open on the admin VLANs.
  adminAddresses = n: map (i: lib.head (lib.splitString "/" n.config.homelab.lan.vlans.${i}.address))
    n.config.homelab.lan.adminInterfaces;
  certificates = lib.optionalAttrs (members != [ ]) (lib.head members).config.homelab.incus.restrictedCertificates;
in
lib.mkMerge [
  {
    homelab.mcp.servers.incus = {
      command = lib.mkDefault (lib.getExe incus-mcp);
      port = lib.mkDefault 8110;
      environment = lib.mapAttrs (_: lib.mkDefault) {
        INCUS_ADDRESSES = toString (lib.concatMap adminAddresses members);
        INCUS_CLIENT_CERT = "${certificates.mcp-incus.certificate or (throw
          "mcp: the incus server needs homelab.incus.restrictedCertificates.mcp-incus on the cluster")}";
      };
    };
  }

  (lib.mkIf cfg.enable {
    sops.secrets."incus-mcp-key" = {
      sopsFile = config.homelab.secrets.groupFile;
      key = "incus-mcp-key";
      restartUnits = [ "mcp-incus.service" ];
    };

    # Read as $CREDENTIALS_DIRECTORY/incus-client.key.
    systemd.services.mcp-incus.serviceConfig.LoadCredential =
      [ "incus-client.key:${config.sops.secrets."incus-mcp-key".path}" ];
  })
]
