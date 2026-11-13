{ config, lib, pkgs, utils, ... }:

# KiCad projects for agents (README.md, kicad). Each project is a clone of its source (GitHub, with a commit to start
# from) in `dir`/<project> with its own KiCad MCP Pro server, published at /kicad/<project>/mcp and confined to it:
# agents on different projects never share a server or files. Headless: kicad-cli runs ERC/DRC and exports, tools
# that drive a running KiCad stay hidden. git-sync keeps it in step with its source every minute: commits there come
# down, what agents commit (vcs_commit_checkpoint) goes up, rebased onto them. It stops on uncommitted changes or a
# conflict, never overwriting work.
let
  cfg = config.homelab.mcp.kicad;
  inherit (lib) mkOption types;
  kicad = pkgs.kicad-small;
  server = pkgs.callPackage ../packages/kicad-mcp-pro.nix { };
  git = lib.getExe pkgs.git;
  repo = p: "${cfg.dir}/${p}";
  # git@github.com:you/repo.git or ssh://..., which take a deploy key.
  ssh = url: lib.hasPrefix "ssh://" url || builtins.match "[^/:]+@[^/:]+:.*" url != null;
  keySecret = p: "kicad-deploy-key-${p}";
  # Each project's own user for its source, owning only its deploy key.
  syncUser = p: "kicad-sync-${p}";
  projects = lib.attrNames cfg.projects;
  # What git must never take from a repo agents write to, whatever its config says: hooks, an fsmonitor, a signing
  # program, transports other than these.
  gitGuard = lib.imap0 (i: kv: { "GIT_CONFIG_KEY_${toString i}" = lib.head kv; "GIT_CONFIG_VALUE_${toString i}" = lib.last kv; }) [
    [ "core.hooksPath" "/dev/null" ]
    [ "core.fsmonitor" "false" ]
    [ "commit.gpgSign" "false" ]
    [ "protocol.allow" "never" ]
    [ "protocol.ssh.allow" "always" ]
    [ "protocol.https.allow" "always" ]
    [ "protocol.file.allow" "always" ]
  ];

  # Cloning and syncing: the project's sync user, with its key, seeing only its own repo (what an agent leaves in
  # .git, alternates or linked refs, can't reach another's).
  sourceUnit = p: src: {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      GIT_CONFIG_COUNT = toString (lib.length gitGuard);
      GIT_SSH_COMMAND = "${lib.getExe pkgs.openssh} -o UserKnownHostsFile=/var/lib/${syncUser p}/known_hosts"
        + " -o StrictHostKeyChecking=accept-new"
        + lib.optionalString (ssh src.url) " -i ${config.sops.secrets.${keySecret p}.path} -o IdentitiesOnly=yes";
    } // lib.mergeAttrsList gitGuard;
    serviceConfig = {
      Type = "oneshot";
      User = syncUser p;
      Group = "kicad";
      UMask = "0002";
      StateDirectory = syncUser p;
      TemporaryFileSystem = cfg.dir;
      BindPaths = [ (repo p) ];
      ReadWritePaths = [ (repo p) ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
in
{
  options.homelab.mcp.kicad = {
    # Project name -> its server's port (9200-9299, the router's range) and its source, a repo with something
    # committed. Names are lowercase, they end up in URLs and unit names. A port stays with its project, removing one
    # moves no other. An ssh url takes a deploy key with write access, kicad-deploy-key-<project> in the host's
    # secrets.yaml (GitHub allows a key on one repo only).
    projects = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          port = mkOption { type = types.port; };
          url = mkOption { type = types.str; };
          branch = mkOption {
            type = types.str;
            default = "main";
          };
        };
      });
      default = { };
      example = { palmremote = { port = 9200; url = "git@github.com:you/palmremote.git"; }; };
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
        assertion = lib.all (p: builtins.match "[a-z0-9][a-z0-9-]*" p != null) projects;
        message = "kicad: project names are lowercase letters, digits and dashes";
      }
      {
        # The router's `labs: edge to mcp` and `labs: agents to mcp` only let these through.
        assertion = lib.all (p: p.port >= 9200 && p.port <= 9299) (lib.attrValues cfg.projects);
        message = "kicad: project ports are in 9200-9299, the router's range for them";
      }
    ];

    users.groups.kicad = { };
    # The servers edit, the sync users keep sources in step, admin looks around.
    users.users = {
      admin.extraGroups = [ "kicad" ];
    } // lib.listToAttrs (map (p: lib.nameValuePair (syncUser p) {
      isSystemUser = true;
      group = "kicad";
    }) projects)
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

    homelab.mcp.servers = lib.mapAttrs' (p: project: lib.nameValuePair "kicad-${p}" {
      enable = true;
      public = true;
      publishAt = "/kicad/${p}/mcp";
      command = lib.getExe server;
      inherit (project) port;
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
      serviceConfig = {
        # Only its own project there: the others aren't even readable.
        TemporaryFileSystem = cfg.dir;
        BindPaths = [ (repo p) ];
        # Commits, never the repo's config or hooks, which the sync's git would read.
        BindReadOnlyPaths = [ "${repo p}/.git/config" "${repo p}/.git/hooks" ];
        ReadWritePaths = [ (repo p) ];
        UMask = "0002";
      };
    }) projects)
    # The clone, once: a project's repo is its source's. To change the source, move the repo aside.
    // lib.mapAttrs' (p: src: lib.nameValuePair "kicad-repo-${p}" (lib.recursiveUpdate (sourceUnit p src) {
      description = "Clone KiCad project ${p} from ${src.url}";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" "network-online.target" ];
      unitConfig.ConditionPathExists = "!${repo p}/.git";
      # A failed clone (no deploy key yet, GitHub away) tries again until it's there, the server waits for it.
      startLimitIntervalSec = 0;
      serviceConfig = {
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "1min";
        ExecStart = map utils.escapeSystemdExecArgs [
          [ git "clone" "--quiet" "--branch" src.branch "--config" "core.sharedRepository=group" src.url (repo p) ]
          [ git "-C" (repo p) "config" "branch.${src.branch}.sync" "true" ]
          # git-sync refuses rather than committing uncommitted changes itself: an agent's half-done edits never go up.
          [ git "-C" (repo p) "config" "branch.${src.branch}.autocommitscript"
            "echo 'uncommitted changes: commit them (vcs_commit_checkpoint) or discard them' >&2; false" ]
        ];
        # The server waited for it: start it, also after a clone that took a few tries (as root, "+").
        ExecStartPost = "+${config.systemd.package}/bin/systemctl start --no-block mcp-kicad-${p}.service";
      };
    })) cfg.projects
    // lib.mapAttrs' (p: src: lib.nameValuePair "kicad-sync-${p}" (lib.recursiveUpdate (sourceUnit p src) {
      description = "Keep KiCad project ${p} in step with ${src.url}";
      after = [ "kicad-repo-${p}.service" "network-online.target" ];
      requires = [ "kicad-repo-${p}.service" ];
      path = [ pkgs.git pkgs.openssh ];
      serviceConfig = {
        WorkingDirectory = repo p;
        ExecStart = "${pkgs.git-sync}/bin/git-sync";
        # On a conflict git-sync stops mid-rebase, with markers in the files agents edit: undo it, so the project
        # keeps its own commits and the next run tries again (the log says what conflicts).
        ExecStopPost = utils.escapeSystemdExecArgs [ "${pkgs.runtimeShell}" "-c"
          "[ \"$SERVICE_RESULT\" = success ] || exec ${git} rebase --abort" ];
      };
    })) cfg.projects;

    systemd.timers = lib.mapAttrs' (p: _: lib.nameValuePair "kicad-sync-${p}" {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitInactiveSec = "1min";
      };
    }) cfg.projects;

    sops.secrets = lib.mapAttrs' (p: _: lib.nameValuePair (keySecret p) { owner = syncUser p; })
      (lib.filterAttrs (_: src: ssh src.url) cfg.projects);
  };
}
