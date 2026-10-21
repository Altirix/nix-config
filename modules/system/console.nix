{ config, lib, options, ... }:

# Password login for admin on the console (tty, serial, incus console, a VPS panel), SSH stays key-only.
# Off by default: admin has no password and the console can't log in at all.
# Each host keeps its own hash as admin-password in its secrets.yaml, so a leak is one host.
let
  cfg = config.homelab.console;
in
{
  options.homelab.console.password = lib.mkEnableOption "an admin password for console login";

  config = lib.mkIf cfg.password {
    assertions = [
      {
        assertion = options.sops.defaultSopsFile.isDefined;
        message = "console: homelab.console.password needs admin-password in the host's secrets.yaml";
      }
    ];

    # Decrypted before users are created, so the hash is there on first boot.
    sops.secrets.admin-password.neededForUsers = true;

    users.users.admin.hashedPasswordFile = config.sops.secrets.admin-password.path;
  };
}
