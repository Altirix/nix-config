{ config, lib, pkgs, ... }:

# JLCPCB and LCSC parts (packages/jlcpcb-mcp.nix): parametric search of a local catalog of every JLC part, built from
# yaqwsx/jlcparts, with live LCSC stock, price breaks and datasheets from LCSC's own API per query. No account or key,
# and no site to be turned away from. JLC assembly stock is the catalog's, as of its last build: rebuilt daily
# (mcp-jlcpcb-catalog) beside the server, then swapped in.
let
  cfg = config.homelab.mcp.servers.jlcpcb;
  package = pkgs.callPackage ../packages/jlcpcb-mcp.nix { };
  state = "/var/lib/mcp-jlcpcb";
in
{
  homelab.mcp.servers.jlcpcb = {
    command = lib.mkDefault (lib.getExe package);
    port = lib.mkDefault 8116;
    environment.JLCPCB_DATABASE_PATH = "${state}/catalog/components.sqlite";
  };

  systemd.services = lib.mkIf cfg.enable {
    mcp-jlcpcb = {
      wants = [ "mcp-jlcpcb-catalog.service" ];
      after = [ "mcp-jlcpcb-catalog.service" ];
    };

    # Built in build/ and renamed over the server's, then the server restarted onto it. A catalog under 20 hours old
    # is kept, so a reboot doesn't download it again.
    mcp-jlcpcb-catalog = {
      description = "JLCPCB parts catalog for MCP server jlcpcb";
      environment.JLCPCB_DATABASE_PATH = "${state}/build/components.sqlite";
      serviceConfig = import ../hardening.nix // {
        Type = "oneshot";
        User = "mcp-jlcpcb";
        Group = "mcp-jlcpcb";
        StateDirectory = "mcp-jlcpcb";
        ExecStartPost = "+${config.systemd.package}/bin/systemctl try-restart mcp-jlcpcb.service";
      };
      script = ''
        catalog=${state}/catalog
        if [ -s $catalog/components.sqlite ] && [ -z "$(find $catalog/components.sqlite -mmin +1200)" ]; then
          exit 0
        fi
        rm -rf ${state}/build
        ${package}/bin/jlcpcb-mcp-build-catalog
        mkdir -p $catalog
        mv ${state}/build/version.txt $catalog/version.txt
        mv ${state}/build/components.sqlite $catalog/components.sqlite
        rm -rf ${state}/build
      '';
      path = [ pkgs.findutils ];
    };
  };

  systemd.timers.mcp-jlcpcb-catalog = lib.mkIf cfg.enable {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:20";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };
}
