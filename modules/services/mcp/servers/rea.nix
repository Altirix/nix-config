{ config, lib, pkgs, ... }:

# REA, reverse engineering over MCP. Ghidra is the native engine (Hopper and IDA are unfree),
# jadx-headless-mcp the Android one. Targets go into /var/lib/rea-samples, PUT over HTTP on uploadPort
# (behind the edge's token, the server's own tools only take local paths) or rsync as admin, and the
# server only reads them. All clients share one REA, which has one open target at a time.
#
# Static analysis only by default: the package leaves out what runs programs for a caller (process
# capture, browser and Electron launch, Frida), and gdb, rizin, adb and the other tool CLIs aren't on PATH.
# Clients can still read anything the server's user can and run Ghidra on it. Each open target is
# a Ghidra JVM with 2G heap (GHIDRA_HEADLESS_MAXMEM), REA_GHIDRA_STARTUP_TIMEOUT_MS bounds imports.
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
in
{
  # The full build: capture_process_scenario and browser scenarios run whatever the caller names as
  # the server's user. Only on a VM that is isolated and reset after use (hosts/virtual/rea-dynamic).
  options.homelab.mcp.rea.dynamic = lib.mkEnableOption "REA's dynamic analysis";

  # binwalk/unblob for firmware extraction. They parse untrusted blobs with their own extractors, a
  # parser-exploit surface, so keep it to the isolated VM rather than the shared host.
  options.homelab.mcp.rea.firmware = lib.mkEnableOption "REA's firmware extraction (binwalk, unblob)";

  # nginx takes samples here, opened to the server's `clients`: PUT /samples/<name> stores it, GET /samples/
  # lists them, DELETE removes one. Files land read-only (0644, no subdirectories), so on rea-dynamic copy
  # one into the state directory with `install -m755` before running it.
  options.homelab.mcp.rea.uploadPort = lib.mkOption {
    type = lib.types.port;
    default = 8111;
  };

  config = lib.mkMerge [
    {
      homelab.mcp.servers.rea = {
        command = lib.mkDefault (lib.getExe rea);
        args = lib.mkDefault [ "mcp" ];
        port = lib.mkDefault 8101;
        extraPorts = [ cfg.uploadPort ];
        # REA checks child process ownership with ps.
        path = [ pkgs.procps rea.jdk ]
          # prlimit (util-linux) bounds the extractors, unblob bundles its own.
          ++ lib.optionals cfg.firmware [ pkgs.binwalk unblob pkgs.util-linux ];
        environment = lib.mapAttrs (_: lib.mkDefault) ({
          GHIDRA_INSTALL_DIR = "${rea.ghidra}/lib/ghidra";
          JAVA_HOME = rea.jdk.home;
          REA_JADX_MCP_JAR = "${rea.jadxMcp}";
        } // lib.optionalAttrs cfg.dynamic {
          # Web module resolution. Browser scenarios take it as executable_path, /etc/rea/chromium for callers.
          REA_BROWSER_EXECUTABLE = chromium;
        } // lib.optionalAttrs cfg.firmware {
          REA_BINWALK_COMMAND = lib.getExe pkgs.binwalk;
          REA_UNBLOB_COMMAND = lib.getExe unblob;
          REA_FIRMWARE_PRLIMIT_COMMAND = "${pkgs.util-linux}/bin/prlimit";
        });
      };
    }

    (lib.mkIf config.homelab.mcp.servers.rea.enable {
      # nginx writes uploads, admin (users) can still rsync in, the server only reads.
      systemd.tmpfiles.rules = [ "d /var/lib/rea-samples 2775 nginx users -" ];

      services.nginx = {
        enable = true;
        virtualHosts.rea-samples = {
          listen = [
            { addr = "0.0.0.0"; port = cfg.uploadPort; }
            { addr = "[::]"; port = cfg.uploadPort; }
          ];
          locations."/".return = "404";
          locations."/samples/" = {
            alias = "/var/lib/rea-samples/";
            extraConfig = ''
              dav_methods PUT DELETE;
              dav_access group:r all:r;
              client_max_body_size 1g;
              autoindex on;
              limit_except GET PUT DELETE { deny all; }
            '';
          };
        };
      };
      systemd.services.nginx.serviceConfig.ReadWritePaths = [ "/var/lib/rea-samples" ];
    })

    (lib.mkIf cfg.dynamic {
      assertions = [
        {
          assertion = lib.attrNames (lib.filterAttrs (_: s: s.enable) config.homelab.mcp.servers) == [ "rea" ];
          message = "mcp: homelab.mcp.rea.dynamic runs what callers name, REA must be the only server on its host";
        }
      ];

      environment.etc."rea/chromium".source = chromium;
    })
  ];
}
