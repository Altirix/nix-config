{ ... }:

# Prometheus, Loki and Grafana for every host in the flake, Grafana on :3000.
# secrets.yaml holds grafana-admin-password and grafana-secret-key (`openssl rand -hex 32`).
{
  imports = [
    ../../../modules/virtual.nix
    ../../../modules/services/monitoring/server.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  homelab.monitoring.server.enable = true;

  system.stateVersion = "26.05";
}
