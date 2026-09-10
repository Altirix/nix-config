{
  imports = [
    ./desktop/home.nix
  ];

  sops.secrets.desktop = {
    sopsFile = ../secrets/desktop.yaml;
  };
}