{ config, lib, pkgs, ... }:

# REA, reverse engineering over MCP. Ghidra is the native engine (Hopper and IDA are unfree),
# jadx-headless-mcp the Android one. One REA server per project in `projects`, mcp-rea-<project> on
# 8120 onwards (loopback only), each MCP session its own REA process with its own open target. nginx on
# `port` is the only way in: /<project>/mcp, /<project>/samples/ takes uploads into
# /var/lib/rea-samples/<project> (behind the edge's token, REA's tools only take local paths) and
# /<project>/shared/ serves /var/lib/rea-shared/<project> read-only. Listing a project turns its server on.
#
# Each project is its own dynamic user and sees only its own samples (read-only), its shared directory
# (evidence bundles and analysis snapshots its sessions pass along, group rea-<project> so nginx can serve
# them) and its state directory /var/lib/mcp-rea-<project> (scratch/ for tool output). Other projects'
# are out of reach. All of them run in rea.slice, capped at `memoryMax` together.
#
# Static analysis only by default: the package leaves out what runs programs for a caller (process
# capture, browser and Electron launch, Frida), and rizin (its debug sessions run the target) only comes with
# `dynamic`. objdump is always there, gdb, adb and the other tool CLIs aren't on PATH.
# Clients can still read anything the server's user can and run Ghidra on it. Each open target is
# a Ghidra JVM with 2G heap (GHIDRA_HEADLESS_MAXMEM), so a project takes up to 2G per session
# (homelab.mcp.servers.rea-<project>.maxSessions). REA_GHIDRA_STARTUP_TIMEOUT_MS bounds imports.
let
  cfg = config.homelab.mcp.rea;
  projects = lib.imap0 (i: name: { inherit name; port = 8120 + i; }) cfg.projects;
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
in
{
  # The full build: capture_process_scenario and browser scenarios run whatever the caller names as
  # the server's user. Only on a VM that is isolated and reset after use (hosts/virtual/rea-dynamic).
  options.homelab.mcp.rea.dynamic = lib.mkEnableOption "REA's dynamic analysis";

  # binwalk/unblob for firmware extraction. They parse untrusted blobs with their own extractors, a
  # parser-exploit surface, so keep it to the isolated VM rather than the shared host.
  options.homelab.mcp.rea.firmware = lib.mkEnableOption "REA's firmware extraction (binwalk, unblob)";

  # Each gets its own server, samples and state, e.g. one per repo agents work from.
  options.homelab.mcp.rea.projects = lib.mkOption {
    type = lib.types.listOf (lib.types.strMatching "[a-z0-9][a-z0-9-]*");
    default = [ ];
  };

  # nginx, opened to `clients`: POST /<project>/mcp is the project's server, PUT /<project>/samples/<name>
  # stores a sample, GET /<project>/samples/ lists them, DELETE removes one. Samples land read-only (0644,
  # no subdirectories), so on rea-dynamic copy one into scratch/ with `install -m755` before running it.
  options.homelab.mcp.rea.port = lib.mkOption {
    type = lib.types.port;
    default = 8101;
  };

  # systemd MemoryMax for every project's sessions together, so busy projects can't take the whole VM.
  options.homelab.mcp.rea.memoryMax = lib.mkOption {
    type = lib.types.str;
    default = "75%";
  };

  # Like homelab.mcp.clients (the default), for `port`.
  options.homelab.mcp.rea.clients = lib.mkOption {
    type = lib.types.nullOr (lib.types.listOf lib.types.str);
    default = config.homelab.mcp.clients;
    defaultText = lib.literalExpression "config.homelab.mcp.clients";
  };

  config = lib.mkIf (projects != [ ]) (lib.mkMerge [
    {
      homelab.mcp.servers = lib.listToAttrs (map (p: lib.nameValuePair "rea-${p.name}" {
        enable = true;
        command = lib.mkDefault (lib.getExe rea);
        args = lib.mkDefault [ "mcp" ];
        inherit (p) port;
        sessions = "isolated";
        # Only nginx, over loopback.
        clients = [ ];
        # REA checks child process ownership with ps.
        path = [ pkgs.procps rea.jdk ]
          ++ lib.optionals cfg.dynamic [ pkgs.rizin ]
          # prlimit (util-linux) bounds the extractors, unblob bundles its own.
          ++ lib.optionals cfg.firmware [ pkgs.binwalk unblob pkgs.util-linux ];
        environment = lib.mapAttrs (_: lib.mkDefault) ({
          GHIDRA_INSTALL_DIR = "${rea.ghidra}/lib/ghidra";
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
        });
      }) projects);

      systemd.slices.rea.sliceConfig.MemoryMax = cfg.memoryMax;

      systemd.paths = lib.listToAttrs (map (p: lib.nameValuePair "rea-shared-${p.name}" {
        wantedBy = [ "multi-user.target" ];
        pathConfig.PathChanged = [ "/var/lib/rea-shared/${p.name}/evidence" "/var/lib/rea-shared/${p.name}/snapshots" ];
      }) projects);

      systemd.services = lib.listToAttrs (map (p: lib.nameValuePair "mcp-rea-${p.name}" {
        # A host that mounts these from a volume of their own (rea-dynamic) never runs REA on the root disk.
        unitConfig.RequiresMountsFor = [ "/var/lib/private" "/var/lib/rea-samples" "/var/lib/rea-shared" ];
        serviceConfig = {
          Slice = "rea.slice";
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p scratch";
          # Its own samples and shared directory at the same paths, nothing else of either.
          TemporaryFileSystem = [ "/var/lib/rea-samples:ro" "/var/lib/rea-shared:ro" ];
          BindReadOnlyPaths = [ "/var/lib/rea-samples/${p.name}" ];
          BindPaths = [ "/var/lib/rea-shared/${p.name}" ];
          # What it writes there is group rea-<project> (setgid directory) and readable by it, for nginx.
          SupplementaryGroups = [ "rea-${p.name}" ];
          UMask = "0027";
        };
      }) projects) // lib.listToAttrs (map (p: lib.nameValuePair "rea-shared-${p.name}" {
        # REA writes bundles and snapshots 0600, whatever the umask, so nginx couldn't serve them. As the
        # project's own user, so it only ever touches that project's files.
        description = "Make what REA project ${p.name} shares readable to nginx";
        unitConfig.RequiresMountsFor = [ "/var/lib/rea-shared" ];
        serviceConfig = {
          Type = "oneshot";
          User = "mcp-rea-${p.name}";
          DynamicUser = true;
          SupplementaryGroups = [ "rea-${p.name}" ];
          ReadWritePaths = [ "/var/lib/rea-shared/${p.name}" ];
          ExecStart = "${pkgs.findutils}/bin/find /var/lib/rea-shared/${p.name} -user mcp-rea-${p.name} -exec ${pkgs.coreutils}/bin/chmod g+rX {} +";
        };
      }) projects) // {
        # tmpfiles runs before a host's own mounts of these are up (at boot with nofail, and on switch), and would
        # create the projects' directories underneath them. Again once they're mounted, before anything uses them,
        # /var/lib/private included: systemd won't put a state directory under it unless it's 0700.
        rea-dirs = {
          description = "Create REA's sample, shared and state directories";
          wantedBy = [ "multi-user.target" ];
          requiredBy = [ "nginx.service" ] ++ map (p: "mcp-rea-${p.name}.service") projects;
          before = [ "nginx.service" ] ++ map (p: "mcp-rea-${p.name}.service") projects;
          unitConfig.RequiresMountsFor = [ "/var/lib/private" "/var/lib/rea-samples" "/var/lib/rea-shared" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${config.systemd.package}/bin/systemd-tmpfiles --create --prefix=/var/lib/private --prefix=/var/lib/rea-samples --prefix=/var/lib/rea-shared";
          };
        };
        nginx = {
          unitConfig.RequiresMountsFor = [ "/var/lib/rea-samples" "/var/lib/rea-shared" ];
          serviceConfig = {
            ReadWritePaths = [ "/var/lib/rea-samples" ];
            # The bind mount above makes nginx copy uploads from its temp dir rather than rename them, and the copy
            # takes the umask (NixOS sets 0027), not dav_access: 0640 uploads the server can't read.
            UMask = lib.mkForce "0022";
          };
        };
      };

      # nginx writes uploads, admin (users) can still rsync in, the servers only read. The other way round for
      # shared: the project writes, nginx (in every project's group) only reads.
      systemd.tmpfiles.rules = [
        "d /var/lib/private 0700 root root -"
        "d /var/lib/rea-samples 0755 root root -"
        "d /var/lib/rea-shared 0755 root root -"
      ]
        ++ lib.concatMap (p: [
          "d /var/lib/rea-samples/${p.name} 2775 nginx users -"
          "d /var/lib/rea-shared/${p.name} 2770 root rea-${p.name} -"
          "d /var/lib/rea-shared/${p.name}/snapshots 2770 root rea-${p.name} -"
          # REA only writes into directories that exist, so bundles go flat: <branch>__<agent>.json.
          "d /var/lib/rea-shared/${p.name}/evidence 2770 root rea-${p.name} -"
        ]) projects;

      users.groups = lib.listToAttrs (map (p: lib.nameValuePair "rea-${p.name}" { }) projects);
      users.users.nginx.extraGroups = map (p: "rea-${p.name}") projects;

      services.nginx = {
        enable = true;
        virtualHosts.rea = {
          listen = [
            { addr = "0.0.0.0"; inherit (cfg) port; }
            { addr = "[::]"; inherit (cfg) port; }
          ];
          locations = { "/".return = "404"; } // lib.listToAttrs (lib.concatMap (p: [
            (lib.nameValuePair "= /${p.name}/mcp" {
              proxyPass = "http://127.0.0.1:${toString p.port}/mcp";
              # Streams pass straight through, sessions stay open while an agent works.
              extraConfig = ''
                proxy_http_version 1.1;
                proxy_set_header Connection "";
                proxy_buffering off;
                proxy_request_buffering off;
                proxy_read_timeout 1h;
                proxy_send_timeout 1h;
              '';
            })
            (lib.nameValuePair "/${p.name}/samples/" {
              alias = "/var/lib/rea-samples/${p.name}/";
              extraConfig = ''
                dav_methods PUT DELETE;
                dav_access group:r all:r;
                client_max_body_size 1g;
                autoindex on;
                limit_except GET PUT DELETE { deny all; }
              '';
            })
            (lib.nameValuePair "/${p.name}/shared/" {
              alias = "/var/lib/rea-shared/${p.name}/";
              extraConfig = ''
                autoindex on;
                limit_except GET { deny all; }
              '';
            })
          ]) projects);
        };
      };

      networking.firewall.allowedTCPPorts = lib.mkIf (cfg.clients == null) [ cfg.port ];
      # As homelab.mcp does for its servers' clients, one rule per address family that has any.
      networking.firewall.extraInputRules = lib.concatMapStrings (family:
        let addrs = lib.filter (a: lib.hasInfix ":" a == (family == "ip6")) (lib.optionals (cfg.clients != null) cfg.clients);
        in lib.optionalString (addrs != [ ])
          "${family} saddr { ${lib.concatStringsSep ", " addrs} } tcp dport ${toString cfg.port} accept\n") [ "ip" "ip6" ];
    }

    (lib.mkIf cfg.dynamic {
      assertions = [
        {
          assertion = lib.all (lib.hasPrefix "rea-") (lib.attrNames (lib.filterAttrs (_: s: s.enable) config.homelab.mcp.servers));
          message = "mcp: homelab.mcp.rea.dynamic runs what callers name, REA must be the only server on its host";
        }
      ];

      environment.etc."rea/chromium".source = chromium;
    })
  ]);
}
