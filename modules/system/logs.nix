{ config, lib, pkgs, ... }:

# Every host ships its journal to VictoriaLogs on the logs VM (hosts/virtual/logs), resuming where it left off
# after an outage. Log files that bypass the journal (nginx's) are fed into it first, one identifier each.
let
  cfg = config.homelab.logs;
  inherit (lib) mkOption types;
in
{
  options.homelab.logs = {
    # VictoriaLogs, null ships nothing (rea-dynamic: it may not open connections).
    server = mkOption {
      type = types.nullOr types.str;
      default = "http://10.100.1.14:9428";
    };

    # Files followed into the journal as SYSLOG_IDENTIFIER=<name>, read with `group`'s permissions.
    files = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          path = mkOption { type = types.str; };
          group = mkOption { type = types.str; };
        };
      });
      default = { };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.server != null) {
      services.journald.upload = {
        enable = true;
        settings.Upload.URL = "${cfg.server}/insert/journald";
      };
    })

    {
      systemd.services = lib.mapAttrs' (name: f: lib.nameValuePair "log-file-${name}" {
        description = "Follow ${f.path} into the journal";
        wantedBy = [ "multi-user.target" ];
        # New lines only, across rotations.
        script = "exec ${pkgs.coreutils}/bin/tail -F -n0 ${lib.escapeShellArg f.path}";
        serviceConfig = {
          DynamicUser = true;
          SupplementaryGroups = [ f.group ];
          SyslogIdentifier = name;
          Restart = "always";
          RestartSec = 5;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateNetwork = true;
          PrivateDevices = true;
          NoNewPrivileges = true;
          CapabilityBoundingSet = "";
        };
      }) cfg.files;
    }
  ];
}
