{
  imports = [
    ./desktop/home.nix
  ];

  sops.secrets = {
    "desktop-hello" = {
      sopsFile = ../secrets/desktop.yaml;
      key = "hello";
    };
  };
}