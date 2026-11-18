{ config, lib, pkgs, utils, ... }:

# KiCad projects for agents (README.md, kicad). Each project is a clone of its source (GitHub, with a commit to start
# from) in `dir`/<project> with its own KiCad MCP Pro server, published at /kicad/<project>/mcp and confined to it:
# agents on different projects never share a server or files. Headless: kicad-cli runs ERC/DRC and exports, and the
# project's own headless KiCad (kicad-api-<project>) takes live board edits, one board at a time. Agents do git
# themselves (vcs_fetch, vcs_branch, vcs_pull, vcs_push): the server's git reaches the source through two sockets,
# fetching and pushing, that run git's own service on that one repo as the project's sync user, which alone holds
# its deploy key. The server can't read the key or reach any other repo.
let
  cfg = config.homelab.mcp.kicad;
  inherit (lib) mkOption types;
  # KiCad's development branch, for its headless API server (packages/kicad-master.nix): everything that reads or
  # writes a project's files is this one KiCad, so they're never in two formats.
  kicad = pkgs.callPackage ../packages/kicad-master.nix { };
  # Its symbol and footprint libraries (no 3D models in -small), in store paths of their own.
  symbols = "${kicad.libraries.symbols}/share/kicad";
  footprints = "${kicad.libraries.footprints}/share/kicad";
  # KiCad's config directory for this version (a development build calls itself 10.99), where its global library
  # tables live.
  kicadConfig = p: "/var/lib/mcp-kicad-${p}/.config/kicad/10.99";
  server = pkgs.callPackage ../packages/kicad-mcp-pro.nix { inherit kicad; };
  # The router agents use (packages/kicad-routing-tools.nix).
  routingTools = pkgs.callPackage ../packages/kicad-routing-tools.nix { };
  # Where the libraries are, for the server (and its kicad-cli) and the headless KiCad alike: what the library
  # tables' ${KICAD10_...} and ${KICAD11_...} stand for.
  libraryEnv = {
    KICAD10_SYMBOL_DIR = "${symbols}/symbols";
    KICAD10_FOOTPRINT_DIR = "${footprints}/footprints";
    KICAD10_3DMODEL_DIR = models3d;
    KICAD11_SYMBOL_DIR = "${symbols}/symbols";
    KICAD11_FOOTPRINT_DIR = "${footprints}/footprints";
    KICAD11_3DMODEL_DIR = models3d;
  };
  # The parts' 3D models (pcb_render_3d), about 460 MB in the store.
  models3d = "${kicad.libraries.packages3d}/share/kicad/3dmodels";
  # Each project's headless KiCad, its API socket only the project's server reaches.
  apiSocket = p: "/run/kicad-api-${p}/api.sock";
  git = lib.getExe pkgs.git;
  repo = p: "${cfg.dir}/${p}";
  # git@github.com:you/repo.git or ssh://..., which take a deploy key.
  ssh = url: lib.hasPrefix "ssh://" url || builtins.match "[^/:]+@[^/:]+:.*" url != null;
  keySecret = p: "kicad-deploy-key-${p}";
  # Each project's own user for its source, owning only its deploy key.
  syncUser = p: "kicad-sync-${p}";
  projects = lib.attrNames cfg.projects;
  # The sockets for a project's git, one per direction, `upload-pack` (fetch) and `receive-pack` (push): the path git's
  # ext transport asks for (%S, git-upload-pack or git-receive-pack).
  gitSocket = p: service: "/run/kicad-git-${p}/git-${service}";
  # An ssh url's host (or ssh://host[:port]) and the path git's service takes on it.
  sshTarget = url:
    let
      scp = builtins.match "([^/:]+@[^/:]+):(.*)" url;
      uri = builtins.match "(ssh://[^/]+)(/.*)" url;
    in
    if scp != null then { host = lib.elemAt scp 0; path = lib.elemAt scp 1; }
    else { host = lib.elemAt uri 0; path = lib.elemAt uri 1; };
  # The server's own git config: the source's url goes through the project's sockets (git's ext transport, socat).
  # -t: once git has sent its side, socat waits this long for the answer (0.5 s by default, less than a push takes
  # to reach GitHub through the gate, which answers only after that).
  serverGitConfig = p: src: pkgs.writeText "kicad-${p}.gitconfig" ''
    [url "ext::${lib.getExe pkgs.socat} -t 600 STDIO UNIX-CONNECT:/run/kicad-git-${p}/%S"]
    	insteadOf = ${src.url}
    [protocol "ext"]
    	allow = always
  '';
  # What git must never take from a repo agents write to, whatever its config says: hooks, an fsmonitor, a signing
  # program, transports other than these.
  gitGuard = [
    [ "core.hooksPath" "/dev/null" ]
    [ "core.fsmonitor" "false" ]
    [ "commit.gpgSign" "false" ]
    [ "protocol.allow" "never" ]
    [ "protocol.ssh.allow" "always" ]
    [ "protocol.https.allow" "always" ]
    [ "protocol.file.allow" "always" ]
  ];
  # git config through the environment, entries later in the list winning.
  gitConfigEnv = entries: { GIT_CONFIG_COUNT = toString (lib.length entries); } // lib.mergeAttrsList (lib.imap0
    (i: kv: { "GIT_CONFIG_KEY_${toString i}" = lib.head kv; "GIT_CONFIG_VALUE_${toString i}" = lib.last kv; }) entries);
  # Pushes go through a gate, a bare repo of the sync user's: it refuses force updates and deletions itself, and its
  # hook refuses the protected branches (`protect`, main) and pushes every other branch on to the source, never
  # forced, before taking it, all within the agent's push (GitHub only protects private repos' branches on a paid
  # plan). Agents push branches of their own, never to main, and never rewrite or delete one.
  pushGateHooks = pkgs.writeShellApplication {
    name = "pre-receive";
    runtimeInputs = [ pkgs.git ];
    text = builtins.readFile ../scripts/kicad-push-gate.sh;
  };
  pushGate = p: "/var/lib/${syncUser p}/gate.git";

  # Cloning, and the git services behind the sockets: the project's sync user, with its key, seeing only its own repo (what an agent leaves in
  # .git, alternates or linked refs, can't reach another's).
  sourceUnit = p: src: {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = gitConfigEnv gitGuard // {
      GIT_SSH_COMMAND = "${lib.getExe pkgs.openssh} -o UserKnownHostsFile=/var/lib/${syncUser p}/known_hosts"
        + " -o StrictHostKeyChecking=accept-new"
        + lib.optionalString (ssh src.url) " -i ${config.sops.secrets.${keySecret p}.path} -o IdentitiesOnly=yes";
    };
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
          # The branch the clone starts on; agents switch and push branches themselves after that.
          branch = mkOption {
            type = types.str;
            default = "main";
          };
          # Branches agents can't push to: they change only by your merges on GitHub.
          protect = mkOption {
            type = types.listOf types.str;
            default = [ "main" ];
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
    # experimental: write, plus routing (KiCadRoutingTools, differential pairs, length tuning) and manufacturing
    # exports, which KiCad MCP Pro keeps behind it.
    mode = mkOption {
      type = types.enum [ "readonly" "write" "experimental" ];
      default = "write";
    };
    # The most each project's server may use, with every job it runs (shell_run, KiCadRoutingTools).
    memoryMax = mkOption {
      type = types.str;
      default = "3G";
    };
    # KiCad MCP Pro's tool set. builder has creating projects, schematic, library, board and routing editing,
    # ERC/DRC and its git tools; its own `default` is review only, which hides them even in write mode.
    profile = mkOption {
      type = types.str;
      default = if cfg.mode == "readonly" then "review" else "builder";
    };
  };

  config = lib.mkIf (cfg.projects != { }) {
    assertions = [
      {
        assertion = lib.all (p: builtins.match "[a-z0-9][a-z0-9-]*" p != null) projects;
        message = "kicad: project names are lowercase letters, digits and dashes";
      }
      {
        # The router's `labs: edge to mcp` only lets these through.
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
    } // lib.genAttrs (map repo projects) (_: { d = { user = "root"; group = "kicad"; mode = "2775"; }; })
    # KiCad's default global library tables, which only its first GUI start would copy in: every standard symbol
    # and footprint library for ERC, DRC and the server. Read-only from the store, a server's own config beside
    # them stays its own.
    // lib.listToAttrs (lib.concatMap (p: let u = "mcp-kicad-${p}"; c = kicadConfig p; in [
      (lib.nameValuePair "/var/lib/${u}/.config" { d = { user = u; group = u; mode = "0700"; }; })
      (lib.nameValuePair "/var/lib/${u}/.config/kicad" { d = { user = u; group = u; mode = "0700"; }; })
      (lib.nameValuePair c { d = { user = u; group = u; mode = "0700"; }; })
      (lib.nameValuePair "${c}/sym-lib-table" { "L+".argument = "${symbols}/template/sym-lib-table"; })
      (lib.nameValuePair "${c}/fp-lib-table" { "L+".argument = "${footprints}/template/fp-lib-table"; })
    ]) projects);

    programs.git = {
      enable = true;
      config = {
        safe.directory = map repo projects;
        # Who agents' commits and merges are by, git can't make one up without a mail domain.
        user = { name = "KiCad MCP"; email = "kicad@${config.networking.hostName}.incus"; };
        # Never committed, whatever the project's own .gitignore says: KiCad's lock files and caches, the server's
        # reports.
        core.excludesFile = "${../config/kicad-gitignore}";
      };
    };

    homelab.mcp.servers = lib.mapAttrs' (p: project: lib.nameValuePair "kicad-${p}" {
      enable = true;
      public = true;
      publishAt = "/kicad/${p}/mcp";
      command = lib.getExe server;
      inherit (project) port;
      # What shell_run finds: kicad-cli, git, bash, ngspice (and KiCadRoutingTools' Python as python3,
      # KICAD_MCP_KRT_PYTHON).
      path = [ kicad pkgs.git pkgs.bash pkgs.ngspice ];
      environment = {
        KICAD_MCP_PROJECT_DIR = repo p;
        KICAD_MCP_WORKSPACE_ROOT = repo p;
        KICAD_MCP_KICAD_CLI = "${kicad}/bin/kicad-cli";
        KICAD_MCP_HEADLESS = "true";
        # Live board editing through the project's headless KiCad (kicad-api-<project>), which opens the board
        # selected with kicad_set_project.
        KICAD_API_SOCKET = "ipc://${apiSocket p}";
        KICAD_MCP_OPERATING_MODE = cfg.mode;
        KICAD_MCP_PROFILE = cfg.profile;
        # Routing: KiCadRoutingTools' scripts (route_krt_start), on its own Python.
        KICAD_MCP_KRT_DIR = "${routingTools}/share/kicad-routing-tools";
        KICAD_MCP_KRT_PYTHON = routingTools.python.interpreter;
        # Simulation (sim_*), and ngspice in the shell.
        KICAD_MCP_NGSPICE_CLI = lib.getExe' pkgs.ngspice "ngspice";
        # It looks for the libraries beside kicad-cli, which they aren't on NixOS.
        KICAD_MCP_SYMBOL_LIBRARY_DIR = "${symbols}/symbols";
        KICAD_MCP_FOOTPRINT_LIBRARY_DIR = "${footprints}/footprints";
        # Its git (vcs_fetch, vcs_pull, vcs_push) reaches the source through the project's sockets, never with the key.
        GIT_CONFIG_GLOBAL = "${serverGitConfig p project}";
      } // libraryEnv;
    }) cfg.projects;

    systemd.services = lib.listToAttrs (map (p: lib.nameValuePair "mcp-kicad-${p}" {
      after = [ "kicad-repo-${p}.service" "kicad-api-${p}.service" ];
      requires = [ "kicad-repo-${p}.service" ];
      wants = [ "kicad-api-${p}.service" ];
      serviceConfig = {
        # Only its own project there: the others aren't even readable.
        TemporaryFileSystem = cfg.dir;
        BindPaths = [ (repo p) ];
        # Commits, never the repo's config or hooks, which the sync's git would read.
        BindReadOnlyPaths = [ "${repo p}/.git/config" "${repo p}/.git/hooks" ];
        ReadWritePaths = [ (repo p) ];
        UMask = "0002";
        # The server with all it runs (shell_run, KiCadRoutingTools): a runaway job is stopped here, never the
        # project's headless KiCad (a unit of its own) or the VM. Jobs run niced and go first when memory runs out.
        MemoryMax = cfg.memoryMax;
      };
    }) projects)
    # KiCad itself, headless: the API server the project's MCP server edits boards through, as the same user and in
    # the same sandbox. It opens what the MCP server asks for and saves into the repo.
    // lib.listToAttrs (map (p: lib.nameValuePair "kicad-api-${p}" {
      description = "Headless KiCad for project ${p}";
      after = [ "kicad-repo-${p}.service" ];
      requires = [ "kicad-repo-${p}.service" ];
      environment = { HOME = "/var/lib/mcp-kicad-${p}"; } // libraryEnv;
      serviceConfig = {
        ExecStart = utils.escapeSystemdExecArgs [ "${kicad}/bin/kicad-cli" "api-server" "--socket" (apiSocket p) ];
        User = "mcp-kicad-${p}";
        Group = "mcp-kicad-${p}";
        # Its HOME is the server's state directory, which tmpfiles would otherwise make root's when it adds the
        # library tables below it, before the server first starts: both units claim it.
        StateDirectory = "mcp-kicad-${p}";
        RuntimeDirectory = "kicad-api-${p}";
        RuntimeDirectoryMode = "0700";
        Restart = "on-failure";
        RestartSec = 5;
        UMask = "0002";
        TemporaryFileSystem = cfg.dir;
        BindPaths = [ (repo p) ];
        BindReadOnlyPaths = [ "${repo p}/.git/config" "${repo p}/.git/hooks" ];
        ReadWritePaths = [ (repo p) ];
      } // import ../hardening.nix;
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
        ExecStart = utils.escapeSystemdExecArgs
          [ git "clone" "--quiet" "--branch" src.branch "--config" "core.sharedRepository=group" src.url (repo p) ];
        # The server waited for it: start it, also after a clone that took a few tries (as root, "+").
        ExecStartPost = "+${config.systemd.package}/bin/systemctl start --no-block mcp-kicad-${p}.service";
      };
    })) cfg.projects
    # Behind each socket, per connection, as the sync user: fetches straight from the source (over ssh with the key,
    # or its path for a local one), pushes through the gate, which is first brought in line with the source. Whatever
    # the server asks for, it gets that one repo.
    // lib.listToAttrs (lib.concatMap (p: let src = cfg.projects.${p}; in [
      (lib.nameValuePair "kicad-git-${p}-upload-pack@" (lib.recursiveUpdate (sourceUnit p src) {
        description = "git fetch for KiCad project ${p}";
        serviceConfig = {
          Type = "simple";
          StandardInput = "socket";
          StandardOutput = "socket";
          StandardError = "journal";
          ExecStart = utils.escapeSystemdExecArgs (if ssh src.url then
            let target = sshTarget src.url; in [
              (lib.getExe pkgs.openssh) "-T" "-o" "BatchMode=yes" "-o" "IdentitiesOnly=yes"
              "-i" config.sops.secrets.${keySecret p}.path
              "-o" "UserKnownHostsFile=/var/lib/${syncUser p}/known_hosts" "-o" "StrictHostKeyChecking=accept-new"
              target.host "git-upload-pack '${target.path}'"
            ]
          else [ git "upload-pack" src.url ]);
        };
      }))
      (lib.nameValuePair "kicad-git-${p}-receive-pack@" (lib.recursiveUpdate (sourceUnit p src) {
        description = "git push for KiCad project ${p}";
        environment = gitConfigEnv (gitGuard ++ [
          [ "core.hooksPath" "${pushGateHooks}/bin" ]
          [ "receive.denyNonFastForwards" "true" ]
          [ "receive.denyDeletes" "true" ]
        ]) // { KICAD_SOURCE = src.url; KICAD_PROTECTED = lib.concatStringsSep " " src.protect; };
        serviceConfig = {
          Type = "simple";
          StandardInput = "socket";
          StandardOutput = "socket";
          StandardError = "journal";
          # Quiet: what they print would go into the push's protocol.
          ExecStartPre = map utils.escapeSystemdExecArgs [
            [ git "init" "--quiet" "--bare" (pushGate p) ]
            [ git "-C" (pushGate p) "fetch" "--quiet" "--prune" src.url "+refs/heads/*:refs/heads/*" ]
          ];
          ExecStart = utils.escapeSystemdExecArgs [ git "receive-pack" (pushGate p) ];
        };
      }))
    ]) projects);

    # The project's two git sockets, for its server only.
    systemd.sockets = lib.listToAttrs (lib.concatMap (p: map (service: lib.nameValuePair "kicad-git-${p}-${service}" {
      description = "git ${service} socket for KiCad project ${p}";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = gitSocket p service;
        Accept = true;
        SocketUser = "mcp-kicad-${p}";
        SocketGroup = "mcp-kicad-${p}";
        SocketMode = "0600";
      };
    }) [ "upload-pack" "receive-pack" ]) projects);

    sops.secrets = lib.mapAttrs' (p: _: lib.nameValuePair (keySecret p) { owner = syncUser p; })
      (lib.filterAttrs (_: src: ssh src.url) cfg.projects);
  };
}
