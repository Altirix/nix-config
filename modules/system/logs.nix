{ config, lib, ... }:

# Every host ships its journal to VictoriaLogs on the logs VM (hosts/virtual/logs), resuming where it left off
# after an outage. Anything worth keeping logs to the journal (nginx's access log goes there over syslog).
let
  cfg = config.homelab.logs;
  inherit (lib) mkOption types;
in
{
  options.homelab.logs = {
    # VictoriaLogs, null ships nothing (rea-dynamic: it may not open connections).
    server = mkOption {
      type = types.nullOr types.str;
      default = "http://10.100.0.11:9428";
    };
  };

  config = lib.mkIf (cfg.server != null) {
    services.journald.upload = {
      enable = true;
      settings.Upload.URL = "${cfg.server}/insert/journald";
    };
  };
}
