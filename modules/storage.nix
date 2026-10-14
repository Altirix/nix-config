{ config, ... }:

# Storage nodes, HDD pools are described per host in storage.nix.
{
  homelab.secrets.groupFile = ../secrets/storage.yaml;

  sops.secrets = {
    "storage-hello" = {
      sopsFile = config.homelab.secrets.groupFile;
      key = "hello";
    };
  };
}
