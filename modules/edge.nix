{ config, ... }:

# Public-facing hosts outside the lab.
{
  homelab.secrets.groupFile = ../secrets/edge.yaml;

  sops.secrets = {
    "edge-hello" = {
      sopsFile = config.homelab.secrets.groupFile;
      key = "hello";
    };
  };
}
