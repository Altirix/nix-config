{ config, lib, pkgs, ... }:

# KiCad projects for agents (README.md, kicad). Each project is a git repo in `dir`/<project> with its own KiCad MCP
# Pro server, published at /kicad/<project>/mcp and confined to it: agents on different projects never share a
# server or files. Headless: kicad-cli runs ERC/DRC and exports, tools that drive a running KiCad stay hidden. A
# project with a source keeps in step with it through git-sync, every minute: commits there come down, what agents
# commit (vcs_commit_checkpoint) goes up, rebased onto them. It stops on uncommitted changes or a conflict, never
# overwriting work. A project without one is pushed to over ssh.
let
  cfg = config.homelab.mcp.kicad;
  inherit (lib) mkOption types;
  kicad = pkgs.kicad-small;
  server = pkgs.callPackage ../packages/kicad-mcp-pro.nix { };
  repo = p: "${cfg.dir}/${p}";
  ssh = url: !(lib.hasPrefix "https://" url);
  keySecret = p: "kicad-deploy-key-${p}";
  sshSources = lib.filterAttrs (_: s: ssh s.url) cfg.sources;
in
{
  options.homelab.mcp.kicad = {
    # Project names: a repo and an MCP server each. Lowercase, they end up in URLs and unit names. Add new ones at
    # the end, the servers' ports follow the order.
    projects = mkOption {
      type = types.listOf (types.strMatching "[a-z0-9][a-z0-9-]*");
      default = [ ];
    };
    # Projects that live in a repo elsewhere (GitHub). An ssh url takes a deploy key with write access,
    # kicad-deploy-key-<project> in the host's secrets.yaml (GitHub allows a key on one repo only).
    sources = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          url = mkOption { type = types.str; };
          branch = mkOption {
            type = types.str;
            default = "main";
          };
        };
      });
      default = { };
      example = { palmremote.url = "git@github.com:you/palmremote.git"; };
    };
    dir = mkOption {
      type = types.str;
      default = "/var/lib/kicad";
    };
    # readonly: inspect, check, export. write: create projects, edit schematics and boards, commit too.
    mode = mkOption {
      type = types.enum [ "readonly" "write" ];
      default = "write";
    };
    # KiCad MCP Pro's tool set. builder has creating projects, schematic, library, board and routing editing,
    # ERC/DRC and its git tools; its own `default` is review only, which hides them even in write mode.
    profile = mkOption {
      type = types.str;
      default = if cfg.mode == "write" then "builder" else "review";
    };
    # The servers' ports, one per project in order from here.
    basePort = mkOption {
      type = types.port;
      default = 8200;
    };
  };

  config = lib.mkIf (cfg.projects != [ ]) {
    assertions = [{
      assertion = lib.all (p: lib.elem p cfg.projects) (lib.attrNames cfg.sources);
      message = "kicad: sources names projects that aren't in projects";
    }];

    users.groups.kicad = { };
    # admin pushes and pulls over ssh, the servers edit, git-sync keeps sources in step.
    users.users = {
      admin.extraGroups = [ "kicad" ];
      kicad-sync = {
        isSystemUser = true;
        group = "kicad";
      };
    } // lib.listToAttrs (map (p: lib.nameValuePair "mcp-kicad-${p}" { extraGroups = [ "kicad" ]; }) cfg.projects);

    # Group-writable for everyone in kicad, new files stay so (setgid, git's sharedRepository).
    systemd.tmpfiles.settings."10-kicad" = {
      ${cfg.dir}.d = { user = "root"; group = "kicad"; mode = "2775"; };
    } // lib.genAttrs (map repo cfg.projects) (_: { d = { user = "root"; group = "kicad"; mode = "2775"; }; });

    programs.git = {
      enable = true;
      config.safe.directory = map repo cfg.projects;
    };

    homelab.mcp.servers = lib.listToAttrs (lib.imap0 (i: p: lib.nameValuePair "kicad-${p}" {
      enable = true;
      public = true;
      publishAt = "/kicad/${p}/mcp";
      command = lib.getExe server;
      port = cfg.basePort + i;
      path = [ kicad pkgs.git ];
      environment = {
        KICAD_MCP_PROJECT_DIR = repo p;
        KICAD_MCP_WORKSPACE_ROOT = repo p;
        KICAD_MCP_KICAD_CLI = "${kicad}/bin/kicad-cli";
        KICAD_MCP_HEADLESS = "true";
        KICAD_MCP_OPERATING_MODE = cfg.mode;
        KICAD_MCP_PROFILE = cfg.profile;
      };
    }) cfg.projects);

    systemd.services = lib.listToAttrs (map (p: lib.nameValuePair "mcp-kicad-${p}" {
      after = [ "kicad-projects.service" ];
      requires = [ "kicad-projects.service" ];
      serviceConfig = {
        ReadWritePaths = [ (repo p) ];
        UMask = "0002";
      };
    }) cfg.projects)
    // lib.mapAttrs' (p: src: lib.nameValuePair "kicad-sync-${p}" {
      description = "Keep KiCad project ${p} in step with ${src.url}";
      after = [ "kicad-projects.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git-sync pkgs.git pkgs.openssh ];
      environment.GIT_SSH_COMMAND = "ssh -o UserKnownHostsFile=/var/lib/kicad-sync/known_hosts"
        + " -o StrictHostKeyChecking=accept-new"
        + lib.optionalString (ssh src.url) " -i ${config.sops.secrets.${keySecret p}.path} -o IdentitiesOnly=yes";
      # git-sync needs a branch to sync, an empty repo takes the source's first.
      preStart = ''
        git rev-parse --quiet --verify HEAD >/dev/null || {
          git fetch --quiet origin ${src.branch} && git reset --quiet --hard FETCH_HEAD
        }
      '';
      # On a conflict git-sync stops mid-rebase, with markers in the files agents edit: undo it, so the project keeps
      # its own commits and the next run tries again (its log says what conflicts).
      script = ''
        git-sync || {
          status=$?
          git rebase --abort 2>/dev/null || true
          exit $status
        }
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "kicad-sync";
        Group = "kicad";
        UMask = "0002";
        WorkingDirectory = repo p;
        StateDirectory = "kicad-sync";
        ReadWritePaths = [ (repo p) ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    }) cfg.sources
    // {
      # Each project a repository a push lands in directly (its checkout follows), shared by the group, set up for
      # git-sync where it has a source. git-sync refuses rather than committing uncommitted changes itself, an
      # agent's half-done edits never go up.
      kicad-projects = {
        description = "KiCad project repositories";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-tmpfiles-setup.service" ];
        path = [ pkgs.git ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; UMask = "0002"; };
        script = lib.concatMapStrings (p: ''
          [ -e ${repo p}/.git ] || git init -q -b main --shared=group ${repo p}
          git -C ${repo p} config receive.denyCurrentBranch updateInstead
        '' + lib.optionalString (cfg.sources ? ${p}) (let src = cfg.sources.${p}; b = src.branch; in ''
          git -C ${repo p} remote get-url origin >/dev/null 2>&1 || git -C ${repo p} remote add origin ${src.url}
          git -C ${repo p} remote set-url origin ${src.url}
          git -C ${repo p} config branch.${b}.remote origin
          git -C ${repo p} config branch.${b}.merge refs/heads/${b}
          git -C ${repo p} config branch.${b}.sync true
          git -C ${repo p} config branch.${b}.autocommitscript \
            'echo "uncommitted changes: commit them (vcs_commit_checkpoint) or discard them"; exit 1'
        '') + ''
          chgrp -R kicad ${repo p}/.git
        '') cfg.projects;
      };
    };

    systemd.timers = lib.mapAttrs' (p: _: lib.nameValuePair "kicad-sync-${p}" {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitInactiveSec = "1min";
      };
    }) cfg.sources;

    sops.secrets = lib.mapAttrs' (p: _: lib.nameValuePair (keySecret p) { owner = "kicad-sync"; }) sshSources;
  };
}
