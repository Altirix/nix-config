{ config, pkgs, ... }:

{
  # Add host-specific services here as separate options/modules grow.
  # e.g. services.prometheus.exporters.node.enable = true;
  # e.g. virtualisation.podman.enable = true;

  # Open firewall ports per-service rather than in base.nix, so each
  # service's port lives next to the service that needs it:
  # networking.firewall.allowedTCPPorts = [ 9100 ];
}