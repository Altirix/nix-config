{ config, lib, pkgs, utils, ... }:

# A browser per server, playwright-chromium and playwright-firefox, an agent picks one by which it calls: a site that
# challenges one often lets the other through. Chromium and Firefox from nixpkgs, nothing downloaded, each driven over
# its own HTTP transport, so no mcp-proxy. --isolated gives every client a fresh in-memory context in its server's one
# browser, closed when the client goes away, so many agents use either at once and never see each other's tabs or
# cookies.
#
# Each browser runs headed on a display of its own (Xvnc, mcp-playwright-<browser>-display): headless browsers are the
# easiest to tell from a person's. config/playwright-<browser>.json drops what marks it as driven, and Firefox, which
# reports navigator.webdriver whatever its prefs say, gets config/playwright-firefox-init.js. A captcha or Turnstile an
# agent can't pass is for a person: the display is served as a web page (noVNC, `viewPort`),
# http://<mcp-web>:<viewPort>/, the agent hands its link over, they find the agent's window by its page title on the
# taskbar (IceWM, mcp-playwright-<browser>-wm), solve it there and it carries on with the clearance.
#
# file:// is blocked and uploads stay in roots the client declares, but browser_run_code runs any Node in the server
# (its vm is no sandbox) and can't be turned off, and the view page drives the browser without a password. So the
# unit is the boundary: what the server's user reads (the store, world-readable /etc) can go wherever the VM reaches.
# Neither the server nor its view is ever published. The display and its view run as a user of their own
# (mcp-playwright-<browser>-display), out of the browser's reach: X only on a socket in the browser's private /tmp
# (no TCP, no abstract socket another browser could open), and the egress rules (config/egress.nft) keep the servers
# off the VNC and view ports.
let
  browsers = {
    chromium = { port = 8108; display = 1; viewPort = 8114; };
    firefox = { port = 8112; display = 2; viewPort = 8115; initScript = ../config/playwright-firefox-init.js; };
  };

  # nixpkgs' Playwright browsers come with no fonts: pages render as boxes, and an empty font list is a bot tell.
  fonts = pkgs.makeFontsConf {
    fontDirectories = with pkgs; [ dejavu_fonts liberation_ttf noto-fonts-color-emoji ];
  };

  # noVNC with an index.html that opens it connected (config/novnc-index.html), instead of a directory listing.
  viewRoot = pkgs.symlinkJoin {
    name = "playwright-view";
    paths = [
      "${pkgs.novnc}/share/webapps/novnc"
      (pkgs.runCommand "novnc-index" { } "mkdir $out && cp ${../config/novnc-index.html} $out/index.html")
    ];
  };

  enabled = lib.filterAttrs (browser: _: config.homelab.mcp.servers."playwright-${browser}".enable) browsers;
  opts = browser: config.homelab.mcp.playwright.${browser};

  preset = browser: defaults:
    let
      name = "playwright-${browser}";
      cfg = config.homelab.mcp.servers.${name};
      inherit (opts browser) display viewPort;
      state = "/var/lib/mcp-${name}";
      displayUser = "mcp-${name}-display";
      rfbPort = toString (5900 + display);
      # The display's and the view's.
      sandbox = import ../hardening.nix // {
        User = displayUser;
        Group = displayUser;
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
          args = lib.mkDefault ([
            "--browser" browser
            "--config" "${../config + "/playwright-${browser}.json"}"
          ] ++ lib.optionals (defaults ? initScript) [ "--init-script" "${defaults.initScript}" ] ++ [
            "--isolated"
            "--host" "0.0.0.0"
            "--port" (toString cfg.port)
            # Only Host: localhost is allowed otherwise, which rejects http://mcp-web:<port>.
            "--allowed-hosts" "*"
            "--output-dir" "${state}/output"
          ]);
          transport = lib.mkDefault "http";
          port = lib.mkDefault defaults.port;
          # Published (mcp.peacocks.me), the edge refuses what reaches past the browser: Node in the server
          # (browser_run_code), files off the VM (browser_file_upload) and downloads into it (browser_install).
          edgeDeny = lib.mkDefault [ "browser_run_code" "browser_file_upload" "browser_install" ];
          environment = {
            DISPLAY = ":${toString display}";
            FONTCONFIG_FILE = "${fonts}";
          };
        };

        systemd.services = lib.mkIf cfg.enable {
          "mcp-${name}" = {
            requires = [ "mcp-${name}-display.service" ];
            after = [ "mcp-${name}-display.service" ];
            # One /tmp with the display, where X's socket is.
            unitConfig.JoinsNamespaceOf = "mcp-${name}-display.service";
            # What it downloads (a datasheet a site only hands a browser) and saves lands in output/, which markitdown
            # reads (below) and no other server.
            serviceConfig.StateDirectoryMode = "0750";
          };

          # markitdown converts the browser's downloads, file:///var/lib/mcp-<name>/output/<file>.
          mcp-markitdown = lib.mkIf config.homelab.mcp.servers.markitdown.enable {
            serviceConfig.SupplementaryGroups = [ "mcp-${name}" ];
          };

          # Title bars and a taskbar button per window (config/icewm), so whoever opens the view finds the agent's
          # window among every agent's and brings it to the front. Nothing to start from it.
          "mcp-${name}-wm" = {
            description = "Window manager on MCP server ${name}'s display";
            wantedBy = [ "multi-user.target" ];
            requires = [ "mcp-${name}-display.service" ];
            after = [ "mcp-${name}-display.service" ];
            unitConfig.JoinsNamespaceOf = "mcp-${name}-display.service";
            environment = {
              DISPLAY = ":${toString display}";
              ICEWM_PRIVCFG = "${../config/icewm}";
              FONTCONFIG_FILE = "${fonts}";
            };
            serviceConfig = sandbox // {
              ExecStart = "${pkgs.icewm}/bin/icewm";
            };
          };

          "mcp-${name}-display" = {
            description = "Display of MCP server ${name}";
            unitConfig.JoinsNamespaceOf = "mcp-${name}.service";
            serviceConfig = sandbox // {
              ExecStart = utils.escapeSystemdExecArgs [
                "${pkgs.tigervnc}/bin/Xvnc" ":${toString display}"
                "-geometry" "1920x1080" "-depth" "24"
                # X on its socket in /tmp alone, the abstract one is open to every user on the VM.
                "-nolisten" "tcp" "-nolisten" "local"
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
                "--web" "${viewRoot}"
                "0.0.0.0:${toString viewPort}" "127.0.0.1:${rfbPort}"
              ];
            };
          };
        };

        users.users.${displayUser} = lib.mkIf cfg.enable {
          isSystemUser = true;
          group = displayUser;
        };
        users.groups.${displayUser} = lib.mkIf cfg.enable { };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.enable [ viewPort ];

        # Every navigation leaves a snapshot and console log here, screenshots too.
        systemd.tmpfiles.rules = lib.mkIf cfg.enable [ "e ${state}/output - - - 7d" ];
      };
    };

  viewPorts = lib.mapAttrsToList (browser: _: (opts browser).viewPort) enabled;
  displays = lib.mapAttrsToList (browser: _: (opts browser).display) enabled;
  serverPorts = lib.mapAttrsToList (_: s: s.port) (lib.filterAttrs (_: s: s.enable) config.homelab.mcp.servers);
in
{
  imports = lib.mapAttrsToList preset browsers;

  config = lib.mkIf (enabled != { }) {
    assertions = [
      {
        assertion = lib.allUnique displays && lib.allUnique viewPorts && lib.all (p: !lib.elem p serverPorts) viewPorts;
        message = "mcp: every playwright needs its own display and view port, apart from the servers' ports";
      }
    ];

    # The single playwright server's, before it was one per browser: its snapshots would never expire otherwise.
    systemd.tmpfiles.rules = [ "R /var/lib/mcp-playwright" ];
  };
}
