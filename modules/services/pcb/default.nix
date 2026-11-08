{ config, lib, pkgs, ... }:

# KiCad projects for people and agents. Each project is a git working tree in `dir`/<project> that you clone, pull
# and push over ssh (pushes update the checkout), with its own KiCad MCP Pro server (published at
# /kicad/<project>/mcp, headless, kicad-cli for ERC/DRC and exports) confined to it: agents on different projects
# never share a server or files. A timer renders every project that changed (schematic PDF and SVGs, board SVGs,
# 3D renders, an interactive BOM) to pages nginx serves for a front door with sign-in. Setting it up: README.md.
let
  cfg = config.homelab.pcb;
  kicad = pkgs.kicad-small;
  www = "/var/lib/pcb-www";
  server = pkgs.callPackage ../mcp/packages/kicad-mcp-pro.nix { };
  mcpName = p: "kicad-${p}";

  render = pkgs.writeShellApplication {
    name = "pcb-render";
    runtimeInputs = [ kicad pkgs.interactive-html-bom pkgs.xvfb-run pkgs.coreutils pkgs.findutils pkgs.cpio ];
    runtimeEnv = {
      DIR = cfg.dir;
      WWW = www;
      PROJECTS = toString cfg.projects;
    };
    text = builtins.readFile ./render.sh;
  };
in
{
  imports = [ ../web/publish.nix ];

  options.homelab.pcb = {
    enable = lib.mkEnableOption "KiCad projects, their MCP servers and pages";
    # Project names: a repo, an MCP server and a page each. Lowercase, they end up in URLs and unit names.
    projects = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[a-z0-9][a-z0-9-]*");
      default = [ ];
    };
    dir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pcb";
    };
    # What agents may do: readonly (inspect, check, export) or write (edit schematics and boards too).
    mode = lib.mkOption {
      type = lib.types.enum [ "readonly" "write" ];
      default = "write";
    };
    # The MCP servers' ports, one per project in order from here.
    basePort = lib.mkOption {
      type = lib.types.port;
      default = 8200;
    };
    # The front door's addresses, the only ones that get the pages.
    trustedProxies = lib.mkOption { type = lib.types.listOf lib.types.str; };
  };

  config = lib.mkIf cfg.enable {
    users.groups.pcb = { };
    # admin pushes and pulls over ssh, the MCP servers edit, the renderer reads.
    users.users = {
      admin.extraGroups = [ "pcb" ];
      pcb-render = {
        isSystemUser = true;
        group = "pcb";
      };
    } // lib.listToAttrs (map (p: lib.nameValuePair "mcp-${mcpName p}" { extraGroups = [ "pcb" ]; }) cfg.projects);

    # Group-writable for everyone in pcb, new files stay so (setgid, git's sharedRepository).
    systemd.tmpfiles.settings."10-pcb" = {
      ${cfg.dir}.d = { user = "root"; group = "pcb"; mode = "2775"; };
      ${www}.d = { user = "pcb-render"; group = "pcb"; mode = "0755"; };
    } // lib.listToAttrs (map (p: lib.nameValuePair "${cfg.dir}/${p}" { d = { user = "root"; group = "pcb"; mode = "2775"; }; }) cfg.projects);

    programs.git = {
      enable = true;
      config.safe.directory = map (p: "${cfg.dir}/${p}") cfg.projects;
    };

    homelab.mcp.servers = lib.listToAttrs (lib.imap0 (i: p: lib.nameValuePair (mcpName p) {
      enable = true;
      public = true;
      publishAt = "/kicad/${p}/mcp";
      command = lib.getExe server;
      port = cfg.basePort + i;
      path = [ kicad pkgs.git ];
      environment = {
        KICAD_MCP_PROJECT_DIR = "${cfg.dir}/${p}";
        KICAD_MCP_WORKSPACE_ROOT = "${cfg.dir}/${p}";
        KICAD_MCP_KICAD_CLI = "${kicad}/bin/kicad-cli";
        # No running KiCad to drive, its IPC tools stay hidden.
        KICAD_MCP_HEADLESS = "true";
        KICAD_MCP_OPERATING_MODE = cfg.mode;
      };
    }) cfg.projects);

    systemd.services = lib.listToAttrs (map (p: lib.nameValuePair "mcp-${mcpName p}" {
      after = [ "pcb-projects.service" ];
      requires = [ "pcb-projects.service" ];
      serviceConfig = {
        ReadWritePaths = [ "${cfg.dir}/${p}" ];
        UMask = "0002";
      };
    }) cfg.projects) // {
      # Each project a repository a push lands in directly (its checkout follows), shared by the group.
      pcb-projects = {
        description = "KiCad project repositories";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-tmpfiles-setup.service" ];
        path = [ pkgs.git ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; UMask = "0002"; };
        script = lib.concatMapStrings (p: ''
          if [ ! -e ${cfg.dir}/${p}/.git ]; then
            git init -q -b main --shared=group ${cfg.dir}/${p}
          fi
          git -C ${cfg.dir}/${p} config receive.denyCurrentBranch updateInstead
          chgrp -R pcb ${cfg.dir}/${p}/.git
        '') cfg.projects;
      };

      pcb-render = {
        description = "Render the KiCad projects that changed";
        after = [ "pcb-projects.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "pcb-render";
          Group = "pcb";
          ExecStart = lib.getExe render;
          # KiCad and wx want a writable home for their settings.
          StateDirectory = "pcb-render";
          Environment = [ "HOME=/var/lib/pcb-render" ];
          ReadWritePaths = [ www ];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          Nice = 10;
        };
      };
    };

    systemd.timers.pcb-render = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitInactiveSec = "2min";
      };
    };

    services.nginx = {
      enable = true;
      virtualHosts.pcb = {
        listen = [{ addr = "0.0.0.0"; port = 80; }];
        root = www;
        locations."/".extraConfig = "autoindex on;";
        extraConfig = ''
          ${lib.concatMapStrings (a: "allow ${a};\n") cfg.trustedProxies}deny all;
        '';
      };
    };

    homelab.publish.upstream.port = 80;

    # Only on the labs bridge, the router lets the front door in.
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
