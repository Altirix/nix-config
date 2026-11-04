{ ... }:

# The lab's SSO (modules/services/sso), at auth.peacocks.me through the edge.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  homelab.sso.server = {
    enable = true;
    domain = "auth.peacocks.me";
    # The edge's tunnel address.
    proxies = [ "10.0.0.1" ];
    # Copied from this VM once it's installed (modules/services/sso/README.md).
    certificate = if builtins.pathExists ./tls.pem then ./tls.pem else null;
    mcp = true;
    people.altirix = {
      displayName = "Altirix";
      groups = [ "mcp_users" "web_users" ];
    };
  };
}
