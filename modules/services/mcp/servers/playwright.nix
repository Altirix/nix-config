{ config, lib, pkgs, utils, ... }:

# A browser per server, playwright-chromium and playwright-firefox, an agent picks one by which it calls: a site that
# challenges one often lets the other through. Chromium and Firefox from nixpkgs, nothing downloaded, each driven over
# its own HTTP transport, so no mcp-proxy. --isolated gives every client a fresh in-memory context in its server's one
# browser, closed when the client goes away, so many agents use either at once and never see each other's tabs or
# cookies.
#
# Each browser runs headed on a display of its own (Xvnc, mcp-playwright-<browser>-display): headless browsers are the
# easiest to tell from a person's. config/playwright-<browser>.json drops what marks it as driven, and
# config/playwright-init.js hides navigator.webdriver. A captcha or Turnstile an agent can't pass is for a person: the
# display is served as a web page (noVNC, `viewPort`), http://<mcp-web>:<viewPort>/vnc.html?autoconnect=1&resize=scale,
# the agent hands its link over, they solve it in the agent's own window and it carries on with the clearance.
#
# file:// is blocked and uploads stay in roots the client declares, but browser_run_code runs any Node in the server
# (its vm is no sandbox) and can't be turned off, and the view page drives the browser without a password. So the
# unit is the boundary: what the server's user reads (the store, world-readable /etc) can go wherever the VM reaches.
# Neither the server nor its view is ever published.
let
  browsers = {
    chromium = { port = 8108; display = 1; viewPort = 8114; };
    firefox = { port = 8112; display = 2; viewPort = 8115; };
  };

  # nixpkgs' Playwright browsers come with no fonts: pages render as boxes, and an empty font list is a bot tell.
  fonts = pkgs.makeFontsConf {
    fontDirectories = with pkgs; [ dejavu_fonts liberation_ttf noto-fonts-color-emoji ];
  };

  preset = browser: defaults:
    let
      name = "playwright-${browser}";
      cfg = config.homelab.mcp.servers.${name};
      opts = config.homelab.mcp.playwright.${browser};
      state = "/var/lib/mcp-${name}";
      rfbPort = toString (5900 + opts.display);
      sandbox = import ../hardening.nix // {
        User = "mcp-${name}";
        Group = "mcp-${name}";
        # The browser's /tmp, where X's socket is.
        PrivateTmp = true;
        Restart = "always";
        RestartSec = 5;
      };
    in
    {
      options.homelab.mcp.playwright.${browser} = {
        # X display number, its VNC port (5900 + display) only listens on loopback.
        display = lib.mkOption {
          type = lib.types.ints.between 1 99;
          default = defaults.display;
        };
        # noVNC, the display as a web page for solving challenges. Unauthenticated: the router keeps it to agents.
        viewPort = lib.mkOption {
          type = lib.types.port;
          default = defaults.viewPort;
        };
      };

      config = {
        homelab.mcp.servers.${name} = {
          command = lib.mkDefault (lib.getExe pkgs.playwright-mcp);
          args = lib.mkDefault [
            "--browser" browser
            "--config" "${../config + "/playwright-${browser}.json"}"
            "--init-script" "${../config/playwright-init.js}"
            "--isolated"
            "--host" "0.0.0.0"
            "--port" (toString cfg.port)
            # Only Host: localhost is allowed otherwise, which rejects http://mcp-web:<port>.
            "--allowed-hosts" "*"
            "--output-dir" "${state}/output"
          ];
          transport = lib.mkDefault "http";
          port = lib.mkDefault defaults.port;
          environment = {
            DISPLAY = ":${toString opts.display}";
            FONTCONFIG_FILE = "${fonts}";
          };
        };

        systemd.services = lib.mkIf cfg.enable {
          "mcp-${name}" = {
            requires = [ "mcp-${name}-display.service" ];
            after = [ "mcp-${name}-display.service" ];
          };

          "mcp-${name}-display" = {
            description = "Display of MCP server ${name}";
            # Its /tmp is the browser's, for X's socket.
            unitConfig.JoinsNamespaceOf = "mcp-${name}.service";
            serviceConfig = sandbox // {
              ExecStart = utils.escapeSystemdExecArgs [
                "${pkgs.tigervnc}/bin/Xvnc" ":${toString opts.display}"
                "-geometry" "1920x1080" "-depth" "24"
                "-nolisten" "tcp"
                "-rfbport" rfbPort "-localhost"
                "-SecurityTypes" "None" "-AlwaysShared"
              ];
            };
          };

          "mcp-${name}-view" = {
            description = "Web view of MCP server ${name}'s display";
            wantedBy = [ "multi-user.target" ];
            requires = [ "mcp-${name}-display.service" ];
            after = [ "mcp-${name}-display.service" ];
            serviceConfig = sandbox // {
              ExecStart = utils.escapeSystemdExecArgs [
                (lib.getExe' pkgs.python3Packages.websockify "websockify")
                "--web" "${pkgs.novnc}/share/webapps/novnc"
                "0.0.0.0:${toString opts.viewPort}" "127.0.0.1:${rfbPort}"
              ];
            };
          };
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.enable [ opts.viewPort ];

        # Every navigation leaves a snapshot and console log here, screenshots too.
        systemd.tmpfiles.rules = lib.mkIf cfg.enable [ "e ${state}/output - - - 7d" ];
      };
    };
in
{
  imports = lib.mapAttrsToList preset browsers;
}
