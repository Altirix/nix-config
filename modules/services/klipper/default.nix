{ config, lib, ... }:

# Klipper behind Moonraker and Mainsail. Klipper runs as the moonraker user out of
# Moonraker's config dir, so the UI can edit printer.cfg and SAVE_CONFIG keeps working.
let
  cfg = config.homelab.klipper;
  inherit (lib) mkOption types;

  inherit (config.services.moonraker) stateDir user group;
  configDir = "${stateDir}/config";

  # Mainsail's macros and virtual_sdcard, printer.cfg includes it.
  mainsailCfg = builtins.toFile "mainsail.cfg"
    (builtins.replaceStrings [ "@gcodes@" ] [ "${stateDir}/gcodes" ] (builtins.readFile ./config/mainsail.cfg));
in
{
  options.homelab.klipper = {
    enable = lib.mkEnableOption "Klipper, Moonraker and Mainsail";

    # Only seeds printer.cfg on first start, after that the copy in the config dir is the live one.
    printerConfig = mkOption { type = types.path; };

    # Moonraker lets these in without an API key.
    trustedClients = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    services.klipper = {
      enable = true;
      inherit user group configDir;
      configFile = cfg.printerConfig;
      mutableConfig = true;
      logFile = "${stateDir}/logs/klippy.log";
    };

    services.moonraker = {
      enable = true;
      # Reboot / restart buttons in the UI.
      allowSystemControl = true;
      settings = {
        authorization = {
          trusted_clients = cfg.trustedClients;
          cors_domains = [ "*://${config.networking.hostName}" "*://${config.networking.hostName}.local" ];
        };
        history = { };
        octoprint_compat = { };
      };
    };
    security.polkit.enable = true;

    services.mainsail.enable = true;
    # G-code uploads go through nginx.
    services.nginx.clientMaxBodySize = "1G";

    # mainsail.cfg is linked, so it follows the module.
    systemd.tmpfiles.settings."10-klipper" = {
      ${configDir}.d = { inherit user group; };
      "${stateDir}/logs".d = { inherit user group; };
      "${stateDir}/gcodes".d = { inherit user group; };
      "${configDir}/mainsail.cfg"."L+".argument = "${mainsailCfg}";
    };

    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
