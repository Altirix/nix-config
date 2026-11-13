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
  # git@github.com:you/repo.git or ssh://..., not a path, file:// or http(s)://.
  ssh = url: lib.hasPrefix "ssh://" url || builtins.match "[^/:]+@[^/:]+:.*" url != null;
  keySecret = p: "kicad-deploy-key-${p}";
  sshSources = lib.filterAttrs (_: s: ssh s.url) cfg.sources;
  # Each source's own user, owning only its project's deploy key.
  syncUser = p: "kicad-sync-${p}";
  projects = lib.attrNames cfg.projects;
  # Hooks for every project, from the store: a repo's own .git/hooks are never run.
  hooks = pkgs.writeShellApplication {
    name = "post-receive";
    runtimeInputs = [ pkgs.findutils pkgs.coreutils ];
    text = builtins.readFile ../scripts/kicad-post-receive.sh;
  };
  # What git-sync must never take from a repo agents write to, whatever its config says: hooks, an fsmonitor, a
  # signing program, transports other than these.
  gitGuard = lib.imap0 (i: kv: { "GIT_CONFIG_KEY_${toString i}" = lib.head kv; "GIT_CONFIG_VALUE_${toString i}" = lib.last kv; }) [
    [ "core.hooksPath" "/dev/null" ]
    [ "core.fsmonitor" "false" ]
    [ "commit.gpgSign" "false" ]
    [ "protocol.allow" "never" ]
    [ "protocol.ssh.allow" "always" ]
    [ "protocol.https.allow" "always" ]
    [ "protocol.file.allow" "always" ]
  ];
in
{
  options.homelab.mcp.kicad = {
    # Project name -> its server's port (9200-9299, the router's range): a repo and an MCP server each. Names are
    # lowercase, they end up in URLs and unit names. A port stays with its project, removing one moves no other.
    projects = mkOption {
      type = types.attrsOf types.port;
      default = { };
      example = { palmremote = 9200; };
    };
    # Projects that live in a repo elsewhere (GitHub). An ssh url takes a deploy key with write access,
    # kicad-deploy-key-<project> in the host's secrets.yaml (GitHub allows a key on one repo only).
    sources = mkOption {
      type = types.attrsOf (types.submodule ({ config, ... }: {
        options = {
          url = mkOption { type = types.str; };
          branch = mkOption {
            type = types.str;
            default = "main";
          };
          # Agents' commits go back up (git-sync). Off, the project only fast-forwards to the source: only ssh (with
          # its deploy key) and local repos have credentials here.
          push = mkOption {
            type = types.bool;
            default = ssh config.url || lib.hasPrefix "/" config.url || lib.hasPrefix "file://" config.url;
          };
        };
      }));
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
  };

  config = lib.mkIf (cfg.projects != { }) {
    assertions = [
      {
        assertion = lib.all (p: lib.elem p projects) (lib.attrNames cfg.sources);
        message = "kicad: sources names projects that aren't in projects";
      }
      {
        assertion = lib.all (p: builtins.match "[a-z0-9][a-z0-9-]*" p != null) projects;
        message = "kicad: project names are lowercase letters, digits and dashes";
      }
      {
        # The router's `labs: edge to mcp` and `labs: agents to mcp` only let these through.
        assertion = lib.all (port: port >= 9200 && port <= 9299) (lib.attrValues cfg.projects);
        message = "kicad: project ports are in 9200-9299, the router's range for them";
      }
    ];

    users.groups.kicad = { };
    # admin pushes and pulls over ssh, the servers edit, git-sync keeps sources in step.
    users.users = {
      admin.extraGroups = [ "kicad" ];
    } // lib.mapAttrs' (p: _: lib.nameValuePair (syncUser p) {
      isSystemUser = true;
      group = "kicad";
    }) cfg.sources
    // lib.listToAttrs (map (p: lib.nameValuePair "mcp-kicad-${p}" { extraGroups = [ "kicad" ]; }) projects);

    # Group-writable for everyone in kicad, new files stay so (setgid, git's sharedRepository).
    systemd.tmpfiles.settings."10-kicad" = {
      ${cfg.dir}.d = { user = "root"; group = "kicad"; mode = "2775"; };
    } // lib.genAttrs (map repo projects) (_: { d = { user = "root"; group = "kicad"; mode = "2775"; }; });

    programs.git = {
      enable = true;
      config = {
        safe.directory = map repo projects;
        # Who git-sync's rebases and agents' commits are by, git can't make one up without a mail domain.
        user = { name = "KiCad MCP"; email = "kicad@${config.networking.hostName}.incus"; };
      };
    };

    homelab.mcp.servers = lib.mapAttrs' (p: port: lib.nameValuePair "kicad-${p}" {
      enable = true;
      public = true;
      publishAt = "/kicad/${p}/mcp";
      command = lib.getExe server;
      inherit port;
      path = [ kicad pkgs.git ];
      environment = {
        KICAD_MCP_PROJECT_DIR = repo p;
        KICAD_MCP_WORKSPACE_ROOT = repo p;
        KICAD_MCP_KICAD_CLI = "${kicad}/bin/kicad-cli";
        KICAD_MCP_HEADLESS = "true";
        KICAD_MCP_OPERATING_MODE = cfg.mode;
        KICAD_MCP_PROFILE = cfg.profile;
      };
    }) cfg.projects;

    systemd.services = lib.listToAttrs (map (p: lib.nameValuePair "mcp-kicad-${p}" {
      after = [ "kicad-repo-${p}.service" ];
      requires = [ "kicad-repo-${p}.service" ];
      # Restarted with it: its read-only .git/config is the file as it was at start, a rewrite replaces it.
      partOf = [ "kicad-repo-${p}.service" ];
      serviceConfig = {
        # Only its own project there: the others aren't even readable.
        TemporaryFileSystem = cfg.dir;
        BindPaths = [ (repo p) ];
        # Commits, never the repo's config or hooks, which others' git (sync, your pushes) would run.
        BindReadOnlyPaths = [ "${repo p}/.git/config" "${repo p}/.git/hooks" ];
        ReadWritePaths = [ (repo p) ];
        UMask = "0002";
      };
    }) projects)
    // lib.mapAttrs' (p: src: lib.nameValuePair "kicad-sync-${p}" {
      description = "Keep KiCad project ${p} in step with ${src.url}";
      after = [ "kicad-repo-${p}.service" "network-online.target" ];
      requires = [ "kicad-repo-${p}.service" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git-sync pkgs.git pkgs.openssh ];
      environment = {
        BRANCH = src.branch;
        PUSH = lib.boolToString src.push;
        GIT_CONFIG_COUNT = toString (lib.length gitGuard);
        GIT_SSH_COMMAND = "ssh -o UserKnownHostsFile=/var/lib/${syncUser p}/known_hosts"
          + " -o StrictHostKeyChecking=accept-new"
          + lib.optionalString (ssh src.url) " -i ${config.sops.secrets.${keySecret p}.path} -o IdentitiesOnly=yes";
      } // lib.mergeAttrsList gitGuard;
      script = builtins.readFile ../scripts/kicad-sync.sh;
      serviceConfig = {
        Type = "oneshot";
        User = syncUser p;
        Group = "kicad";
        UMask = "0002";
        WorkingDirectory = repo p;
        StateDirectory = syncUser p;
        # Only its own project there: what an agent leaves in .git (alternates, linked refs) can't reach another's.
        TemporaryFileSystem = cfg.dir;
        BindPaths = [ (repo p) ];
        ReadWritePaths = [ (repo p) ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    }) cfg.sources
    // lib.listToAttrs (map (p: lib.nameValuePair "kicad-repo-${p}" {
      description = "KiCad project repository ${p}";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      path = [ pkgs.git ];
      environment = {
        REPO = repo p;
        HOOKS = "${hooks}/bin";
      } // lib.optionalAttrs (cfg.sources ? ${p}) {
        URL = cfg.sources.${p}.url;
        BRANCH = cfg.sources.${p}.branch;
      };
      script = builtins.readFile ../scripts/kicad-repo.sh;
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; UMask = "0002"; };
    }) projects);

    systemd.timers = lib.mapAttrs' (p: _: lib.nameValuePair "kicad-sync-${p}" {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitInactiveSec = "1min";
      };
    }) cfg.sources;

    sops.secrets = lib.mapAttrs' (p: _: lib.nameValuePair (keySecret p) { owner = syncUser p; }) sshSources;
  };
}
