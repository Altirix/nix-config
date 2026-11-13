{ config, lib, pkgs, ... }:

# REA, reverse engineering over MCP. Ghidra is the native engine (Hopper and IDA are unfree),
# jadx-headless-mcp the Android one. Each project in `projects` has a supergateway of its own (rea@<project>,
# config/rea-gateway.json), serving it at /<project>/mcp and starting a REA for each MCP session, so agents never
# share an open target; idle sessions end after `sessionTimeout`. nginx on `port` (config/rea-nginx.conf) is the
# only way in, and also takes uploads at /<project>/samples/ and serves /<project>/shared/ read-only. Each project
# lives in /var/lib/rea/<project>: samples/ (nginx writes, REA reads), shared/ (REA writes, nginx reads), scratch/
# and home/ (REA's own).
#
# Projects are isolated from each other: each runs as its own user (rea-<project>) and sees only its own
# directory, so a sample one project runs can't reach another's files or processes. They share one memory cap
# (rea.slice). The VM is still a disposable sandbox, what matters lives in the projects' repos.
#
# Static analysis only by default: the package leaves out what runs programs for a caller (process
# capture, browser and Electron launch, Frida), and rizin (its debug sessions run the target) only comes with
# `dynamic`. objdump is always there, gdb, adb and the other tool CLIs aren't on PATH.
# Each open target is a Ghidra JVM with a `ghidraHeap` heap (about half as much again in all), every session
# together capped at `memoryMax`. REA_GHIDRA_STARTUP_TIMEOUT_MS bounds imports.
let
  cfg = config.homelab.mcp.rea;
  rea = pkgs.callPackage ../packages/rea.nix { staticOnly = !cfg.dynamic; };
  # Playwright's own build, playwright-core launches it with --no-sandbox (no user namespaces here).
  chromium = "${pkgs.playwright-driver.components.chromium}/chrome-linux64/chrome";
  # REA only takes unblob 26.6, nixpkgs has 26.3. Its test fixtures are in LFS, so fetch without them and skip the tests.
  unblob = pkgs.unblob.overridePythonAttrs (p: rec {
    version = "26.6.4";
    src = p.src.override {
      tag = version;
      fetchLFS = false;
      hash = "sha256-ORS/JRuIP4yvm6S7/hbR7zbL2NXm2UT0au5eMJ1pwEE=";
    };
    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      inherit (p) pname;
      inherit version src;
      hash = "sha256-lEpnpvPwred1KRXxuM1KPxKbIIJUGvR0tmj16QyL5UQ=";
    };
    doCheck = false;
  });
  supergateway = pkgs.callPackage ../packages/supergateway.nix { };
  user = p: "rea-${p}";

  # A config/rea-tools-*.txt as a list of tool names, its comments and blank lines left out.
  toolList = file: lib.filter (l: l != "" && !lib.hasPrefix "#" l) (lib.splitString "\n" (builtins.readFile file));
  # The project's "tools": its toolset's, or nothing (every tool) without one.
  tools = lib.optionalString (cfg.toolset != null)
    ''"tools": ${builtins.toJSON (toolList ../config/rea-tools-${cfg.toolset}.txt)},'';

  projects = lib.attrNames cfg.projects;
  gatewayPort = p: cfg.projects.${p};
  migrate = pkgs.writeShellApplication {
    name = "rea-migrate";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ../scripts/rea-migrate.sh;
  };

  # config/rea-gateway.json with the project's rea-gateway-project.json, checked by supergateway at build.
  gatewayConfig = p: pkgs.runCommand "rea-gateway-${p}.json" {
    config = builtins.replaceStrings
      [ "@port@" "@sessionTimeout@" "@projects@" ]
      [
        (toString (gatewayPort p))
        (toString cfg.sessionTimeout)
        (builtins.replaceStrings [ "@project@" "@rea@" "@tools@" "@cliTools@" ]
          [ p (lib.getExe rea) tools (builtins.toJSON (toolList ../config/rea-tools-cli.txt)) ]
          (builtins.readFile ../config/rea-gateway-project.json))
      ]
      (builtins.readFile ../config/rea-gateway.json);
    passAsFile = [ "config" ];
  } ''
    cp "$configPath" $out
    ${lib.getExe supergateway} --checkConfig --config $out
  '';
in
{
  # The full build: capture_process_scenario and browser scenarios run whatever the caller names as
  # the server's user. Only on a VM that is isolated and reset after use (hosts/virtual/rea).
  options.homelab.mcp.rea.dynamic = lib.mkEnableOption "REA's dynamic analysis";

  # binwalk/unblob for firmware extraction. They parse untrusted blobs with their own extractors, a
  # parser-exploit surface, so keep it to the isolated VM rather than the shared host.
  options.homelab.mcp.rea.firmware = lib.mkEnableOption "REA's firmware extraction (binwalk, unblob)";

  # Each gets its URLs and /var/lib/rea/<project>, e.g. one per repo agents work from. Listing one turns REA on.
  # Project name -> its gateway's port (loopback only, 9100 up, out of the way of the single servers' 81xx). A port
  # stays with its project, removing one moves no other.
  options.homelab.mcp.rea.projects = lib.mkOption {
    type = lib.types.attrsOf lib.types.port;
    default = { };
    example = { firmware = 9100; };
  };

  # nginx, opened in the firewall (who reaches it is the router's call).
  options.homelab.mcp.rea.port = lib.mkOption {
    type = lib.types.port;
    default = 8101;
  };

  # Milliseconds a session may sit idle before its REA is stopped.
  options.homelab.mcp.rea.sessionTimeout = lib.mkOption {
    type = lib.types.ints.positive;
    default = 30 * 60 * 1000;
  };

  # Only show agents the tools in config/rea-tools-<toolset>.txt, for clients that load every schema up front.
  # Claude Code only loads a tool's schema when it's searched for, and with the compact schemas all 207 names
  # cost ~1.6k tokens, so null (all of them) is the better default: agents can reach any category they need.
  options.homelab.mcp.rea.toolset = lib.mkOption {
    type = lib.types.nullOr (lib.types.enum [ "firmware" ]);
    default = null;
  };

  # Each session's Ghidra heap (GHIDRA_HEADLESS_MAXMEM, REA's default 2G). Firmware of a few MB fits in 1G.
  options.homelab.mcp.rea.ghidraHeap = lib.mkOption {
    type = lib.types.str;
    default = "2G";
  };

  # systemd MemoryMax for every project's gateway and session's REA together (rea.slice), so they can't take the
  # whole VM.
  # Past it the kernel ends a session, not the VM.
  options.homelab.mcp.rea.memoryMax = lib.mkOption {
    type = lib.types.str;
    default = "75%";
  };

  config = lib.mkIf (cfg.projects != { }) (lib.mkMerge [
    {
      assertions = [
        {
          assertion = lib.all (p: builtins.match "[a-z0-9][a-z0-9-]*" p != null) projects;
          message = "mcp: REA project names are lowercase letters, digits and dashes";
        }
        {
          assertion = lib.allUnique (lib.attrValues cfg.projects ++ [ cfg.port ]);
          message = "mcp: every REA project needs a port of its own, not nginx's";
        }
        {
          # nginx's map (config/rea-nginx.conf) would take them for its own parameters.
          assertion = lib.all (p: !lib.elem p [ "default" "hostnames" "include" "volatile" ]) projects;
          message = "mcp: a REA project can't be named default, hostnames, include or volatile";
        }
        {
          assertion = lib.all (s: !s.enable) (lib.attrValues config.homelab.mcp.servers);
          message = "mcp: REA runs what callers name, nothing else may serve from its host";
        }
      ];

      # Every project's /<project>/mcp, samples/ and shared/ under /rea/ for a front door (mcp.peacocks.me), with
      # room for sample uploads.
      homelab.publish = {
        # Each project's MCP endpoints on their own (the edge audits them), the rest of /rea/ as is.
        locations = { "/rea/".port = cfg.port; } // lib.listToAttrs (lib.concatMap (p: map (mcp:
          lib.nameValuePair "/rea/${p}/${mcp}" { port = cfg.port; path = "/${p}/${mcp}"; mcp = true; })
          [ "mcp" "cli/mcp" ]) projects);
        maxBodySize = "1g";
      };

      # A user each, so projects can't reach each other's files or processes.
      users.users = lib.genAttrs (map user projects) (u: {
        isSystemUser = true;
        group = u;
        home = "/var/empty";
      });
      users.groups = lib.genAttrs (map user projects) (_: { });

      systemd.slices.rea = {
        description = "REA, every project";
        sliceConfig.MemoryMax = cfg.memoryMax;
      };

      # A project's gateway and every session's REA, seeing only /var/lib/rea/<project> of all the projects.
      systemd.services = lib.listToAttrs (map (p: lib.nameValuePair "rea@${p}" {
        description = "REA over MCP for ${p}, one per session";
        wantedBy = [ "multi-user.target" ];
        requires = [ "rea-dirs.service" ];
        after = [ "rea-dirs.service" ];
        # A host that mounts it from a volume of its own (rea) never runs REA on the root disk.
        unitConfig.RequiresMountsFor = [ "/var/lib/rea" ];
        # REA checks child process ownership with ps.
        path = [ pkgs.procps rea.jdk ]
          ++ lib.optionals cfg.dynamic [ pkgs.rizin ]
          # prlimit (util-linux) bounds the extractors, unblob bundles its own.
          ++ lib.optionals cfg.firmware [ pkgs.binwalk unblob pkgs.util-linux ];
        # Every session's REA inherits these, the gateway config adds HOME and the directory per project.
        environment = {
          GHIDRA_INSTALL_DIR = "${rea.ghidra}/lib/ghidra";
          GHIDRA_HEADLESS_MAXMEM = cfg.ghidraHeap;
          # Schemas without nested prose and no output schemas: tools/list is 15x smaller (3.3MB to 224KB for
          # all 207), and REA still validates every result against the full contract.
          REA_MCP_INPUT_SCHEMA_PROFILE = "compact";
          REA_MCP_OUTPUT_SCHEMA_PROFILE = "off";
          JAVA_HOME = rea.jdk.home;
          REA_JADX_MCP_JAR = "${rea.jadxMcp}";
          # Every BFD target, not just the host's: samples are ARM firmware as often as x86.
          REA_OBJDUMP_COMMAND = "${pkgs.binutils-unwrapped-all-targets}/bin/objdump";
        } // lib.optionalAttrs cfg.dynamic {
          # execute_rizin_command (ESIL emulation included) and rizin debug sessions.
          REA_RIZIN_COMMAND = lib.getExe pkgs.rizin;
          # Web module resolution. Browser scenarios take it as executable_path, /etc/rea/chromium for callers.
          REA_BROWSER_EXECUTABLE = chromium;
        } // lib.optionalAttrs cfg.firmware {
          REA_BINWALK_COMMAND = lib.getExe pkgs.binwalk;
          REA_UNBLOB_COMMAND = lib.getExe unblob;
          REA_FIRMWARE_PRLIMIT_COMMAND = "${pkgs.util-linux}/bin/prlimit";
        };
        serviceConfig = {
          ExecStart = "${lib.getExe supergateway} --config ${gatewayConfig p}";
          User = user p;
          Group = user p;
          Slice = "rea.slice";
          # Only its own project there, the others aren't even visible.
          TemporaryFileSystem = "/var/lib/rea";
          BindPaths = [ "/var/lib/rea/${p}" ];
          ReadWritePaths = [ "/var/lib/rea/${p}" ];
          Restart = "on-failure";
          RestartSec = 5;
        } // import ../hardening.nix;
      }) projects)
      # REA writes bundles 0600, whatever the umask, so nginx couldn't serve them.
      // lib.listToAttrs (map (p: lib.nameValuePair "rea-shared@${p}" {
        description = "Make what REA project ${p} shares readable to nginx";
        unitConfig.RequiresMountsFor = [ "/var/lib/rea" ];
        serviceConfig = {
          Type = "oneshot";
          User = user p;
          ExecStart = "${pkgs.findutils}/bin/find /var/lib/rea/${p}/shared -user ${user p} ! -perm -g+r -exec ${pkgs.coreutils}/bin/chmod g+rX {} +";
        };
      }) projects)
      // {

      # tmpfiles runs before a host's own mount of /var/lib/rea is up (at boot with nofail, and on switch), and
      # would create the projects' directories underneath it. Again once it's mounted, before anything uses it.
      rea-dirs = {
        description = "Create REA's project directories";
        requiredBy = [ "nginx.service" ];
        before = [ "nginx.service" ];
        unitConfig.RequiresMountsFor = [ "/var/lib/rea" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = [
            "${config.systemd.package}/bin/systemd-tmpfiles --create --prefix=/var/lib/rea"
            "${lib.getExe migrate} ${lib.escapeShellArgs projects}"
          ];
        };
      };

      nginx = {
        unitConfig.RequiresMountsFor = [ "/var/lib/rea" ];
        serviceConfig = {
          ReadWritePaths = map (p: "/var/lib/rea/${p}/samples") projects;
          # The bind mount above makes nginx copy uploads from its temp dir rather than rename them, and the copy
          # takes the umask (NixOS sets 0027), not dav_access: 0640 uploads REA can't read.
          UMask = lib.mkForce "0022";
        };
      };
      };
      systemd.tmpfiles.rules = [ "d /var/lib/rea 0755 root root -" ]
        ++ lib.concatMap (p: let u = user p; in [
          "d /var/lib/rea/${p} 0755 root root -"
          # nginx writes uploads (0644), REA reads them.
          "d /var/lib/rea/${p}/samples 2755 nginx ${u} -"
          # REA writes, nginx (group) reads. REA only writes into directories that exist, so bundles go
          # flat: <branch>__<agent>.json.
          "d /var/lib/rea/${p}/shared 2750 ${u} nginx -"
          "d /var/lib/rea/${p}/shared/evidence 2750 ${u} nginx -"
          "d /var/lib/rea/${p}/scratch 0750 ${u} ${u} -"
          "d /var/lib/rea/${p}/home 0750 ${u} ${u} -"
        ]) projects;

      systemd.paths = lib.listToAttrs (map (p: lib.nameValuePair "rea-shared@${p}" {
        wantedBy = [ "multi-user.target" ];
        pathConfig.PathChanged = "/var/lib/rea/${p}/shared/evidence";
      }) projects);

      # Loopback reaches every project's gateway and nginx, past the sandbox: not for a project's own users.
      networking.nftables.tables.rea-local = {
        family = "inet";
        content = builtins.replaceStrings [ "@users@" "@ports@" ]
          [
            (lib.concatMapStringsSep ", " (p: ''"${user p}"'') projects)
            (lib.concatMapStringsSep ", " toString ([ cfg.port ] ++ lib.attrValues cfg.projects))
          ]
          (builtins.readFile ../config/rea-local.nft);
      };
      # The build's ruleset check has none of these users.
      networking.nftables.preCheckRuleset = ''
        sed 's/"rea-[^"]*"/root/g' -i ruleset.conf
      '';

      services.nginx = {
        enable = true;
        appendHttpConfig = builtins.replaceStrings
          [ "@port@" "@gateways@" "@projects@" ]
          [
            (toString cfg.port)
            (lib.concatMapStrings (p: "    ${p} 127.0.0.1:${toString (gatewayPort p)};\n") projects)
            (lib.concatStringsSep "|" projects)
          ]
          (builtins.readFile ../config/rea-nginx.conf);
      };

      networking.firewall.allowedTCPPorts = [ cfg.port ];
    }

    (lib.mkIf cfg.dynamic {
      environment.etc."rea/chromium".source = chromium;
    })
  ]);
}
