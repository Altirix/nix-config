{
  sops.secrets = {
    "edge-hello" = {
      sopsFile = ../secrets/edge.yaml;
      key = "hello";
    };
  };
}