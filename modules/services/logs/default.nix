{ config, lib, nodes, ... }:

# Every host ships its journal to the collector (collector.nix) with systemd-journal-upload, resuming where it left
# off after an outage. Anything worth keeping logs to the journal (nginx's access log goes there over syslog).
let
  cfg = config.homelab.logs;
in
{
  # The host running the collector, null ships nothing.
  options.homelab.logs.shipTo = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
  };

  config = lib.mkIf (cfg.shipTo != null) {
    services.journald.upload = {
      enable = true;
      settings.Upload.URL = "http://${nodes.${cfg.shipTo}.config.homelab.labs.address}:9428/insert/journald";
    };
  };
}
