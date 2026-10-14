{ lib, ... }:

# Key-only SSH as admin on every host, keys are the .pub files in keys/admin/.
let
  keyDir = ./keys/admin;
  keys = map (f: keyDir + "/${f}")
    (lib.filter (lib.hasSuffix ".pub") (lib.attrNames (builtins.readDir keyDir)));
in
{
  assertions = [
    {
      assertion = keys != [ ];
      message = "ssh: no .pub in modules/system/keys/admin, nobody could log in";
    }
  ];

  users.users.admin.openssh.authorizedKeys.keyFiles = keys;

  services.openssh = {
    enable = true;
    # Host types open 22 where admins reach them (lan admin VLANs, edge, VMs).
    openFirewall = false;
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Deploys copy closures as admin.
  nix.settings.trusted-users = [ "root" "@wheel" ];
}
