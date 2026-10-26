{ config, lib, pkgs, utils, ... }:

# MCP servers, one systemd unit and port each. stdio servers are put behind mcp-proxy, which
# serves streamable HTTP on /mcp and SSE on /sse and shares one server process between all clients.
# There is no auth and no Host check. Every port is open on the VM, who reaches which is the router's call
# (README.md, Router): a firewall on the VM is gone with root on it.
#
# Presets for packaged servers live in servers/, every file there is imported. A preset sets
# defaults and never `enable`, the host turns it on:
#   homelab.mcp.servers.time = { command = lib.mkDefault (lib.getExe pkgs.mcp-server-time); port = lib.mkDefault 8106; };
# Anything else (LoadCredential, ReadWritePaths) goes straight into systemd.services."mcp-<name>".
# Tokens go in a sops template with restartUnits = [ "mcp-<name>.service" ] as `environmentFile`.
let
  cfg = config.homelab.mcp;
  inherit (lib) mkOption types;

  server = types.submodule {
    options = {
      enable = lib.mkEnableOption "this MCP server";

      # The server's executable and arguments.
      command = mkOption { type = types.str; };
      args = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };

      # Opened in the firewall, mcp-proxy listens here for stdio servers.
      port = mkOption { type = types.port; };

      # "stdio" runs the command behind mcp-proxy. "http" servers listen on `port` themselves,
      # so `args` must point them at it and at 0.0.0.0.
      transport = mkOption {
        type = types.enum [ "stdio" "http" ];
        default = "stdio";
      };

      environment = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };

      # KEY=value lines (usually a sops template) for tokens, kept out of the nix store.
      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
      };

      # Extra packages on the server's PATH (git, node ...).
      path = mkOption {
        type = types.listOf types.package;
        default = [ ];
      };
    };
  };

  enabled = lib.filterAttrs (_: s: s.enable) cfg.servers;
  ports = map (s: s.port);

  presets = lib.attrNames (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name)
    (builtins.readDir ./servers));

  proxy = [ (lib.getExe pkgs.mcp-proxy) "--host" "0.0.0.0" "--port" ];
in
{
  imports = map (name: ./servers/${name}) presets;

  options.homelab.mcp = {
    servers = mkOption {
      type = types.attrsOf server;
      default = { };
    };
  };

  config = lib.mkIf (enabled != { }) {
    assertions = [
      {
        assertion = lib.allUnique (ports (lib.attrValues enabled));
        message = "mcp: every enabled server needs its own port";
      }
    ];

    systemd.services = lib.mapAttrs' (name: s: lib.nameValuePair "mcp-${name}" {
      description = "MCP server ${name}";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      inherit (s) path;
      # mcp-proxy only hands the server the environment with --pass-environment.
      environment = { HOME = "/var/lib/mcp-${name}"; } // s.environment;
      serviceConfig = {
        ExecStart = utils.escapeSystemdExecArgs (if s.transport == "stdio"
          then proxy ++ [ (toString s.port) "--pass-environment" "--" s.command ] ++ s.args
          else [ s.command ] ++ s.args);
        EnvironmentFile = lib.mkIf (s.environmentFile != null) s.environmentFile;
        Restart = "on-failure";
        RestartSec = 5;

        # Each server is its own throwaway user with a private home for caches and state.
        DynamicUser = true;
        StateDirectory = "mcp-${name}";
        WorkingDirectory = "/var/lib/mcp-${name}";
      } // import ./hardening.nix;
    }) enabled;

    networking.firewall.allowedTCPPorts = ports (lib.attrValues enabled);
  };
}
