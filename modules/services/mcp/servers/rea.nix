{ config, lib, pkgs, ... }:

# REA, reverse engineering over MCP. Ghidra is the native engine (Hopper and IDA are unfree),
# jadx-headless-mcp the Android one. Targets are copied into /var/lib/rea-samples (rsync as admin),
# the server only reads them. All clients share one REA, which has one open target at a time.
#
# Static analysis only: the package leaves out what runs programs for a caller (process capture,
# browser and Electron launch, Frida), and gdb, rizin, adb and the other tool CLIs aren't on PATH.
# Clients can still read anything the server's user can and run Ghidra on it. Each open target is
# a Ghidra JVM with 2G heap (GHIDRA_HEADLESS_MAXMEM), REA_GHIDRA_STARTUP_TIMEOUT_MS bounds imports.
let
  rea = pkgs.callPackage ../packages/rea.nix { staticOnly = true; };
in
lib.mkMerge [
  {
    homelab.mcp.servers.rea = {
      command = lib.mkDefault (lib.getExe rea);
      args = lib.mkDefault [ "mcp" ];
      port = lib.mkDefault 8101;
      # REA checks child process ownership with ps.
      path = [ pkgs.procps rea.jdk ];
      environment = lib.mapAttrs (_: lib.mkDefault) {
        GHIDRA_INSTALL_DIR = "${rea.ghidra}/lib/ghidra";
        JAVA_HOME = rea.jdk.home;
        REA_JADX_MCP_JAR = "${rea.jadxMcp}";
      };
    };
  }

  (lib.mkIf config.homelab.mcp.servers.rea.enable {
    systemd.tmpfiles.rules = [ "d /var/lib/rea-samples 0755 admin users -" ];
  })
]
