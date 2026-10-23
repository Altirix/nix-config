{ config, lib, pkgs, ... }:

# REA, reverse engineering over MCP. Ghidra is the native engine (Hopper and IDA are unfree),
# jadx-headless-mcp the Android one. Targets are copied into /var/lib/rea-samples (rsync as admin),
# the server only reads them. All clients share one REA, which has one open target at a time.
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
  # A GNU-tar-timestamp test fails in the sandbox and isn't cached, so it would compile and fail on deploy.
  unblob = pkgs.unblob.overridePythonAttrs (p: {
    disabledTests = (p.disabledTests or [ ]) ++ [ "test_extractall_ignores_gnu_timestamp_prefix" ];
  });
in
{
  # The full build: capture_process_scenario and browser scenarios run whatever the caller names as
  # the server's user. Only on a VM that is isolated and reset after use (hosts/virtual/rea-dynamic).
  options.homelab.mcp.rea.dynamic = lib.mkEnableOption "REA's dynamic analysis";

  # binwalk/unblob for firmware extraction. They parse untrusted blobs with their own extractors, a
  # parser-exploit surface, so keep it to the isolated VM rather than the shared host.
  options.homelab.mcp.rea.firmware = lib.mkEnableOption "REA's firmware extraction (binwalk, unblob)";

  config = lib.mkMerge [
    {
      homelab.mcp.servers.rea = {
        command = lib.mkDefault (lib.getExe rea);
        args = lib.mkDefault [ "mcp" ];
        port = lib.mkDefault 8101;
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
      systemd.tmpfiles.rules = [ "d /var/lib/rea-samples 0755 admin users -" ];
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
