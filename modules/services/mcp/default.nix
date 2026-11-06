{ config, lib, pkgs, utils, ... }:

# MCP servers, one systemd unit and port each. stdio servers are put behind mcp-proxy, which
# serves streamable HTTP on /mcp and SSE on /sse and shares one server process between all clients.
# There is no auth and no Host check. Every port is open on the VM, who reaches which is the router's call
# (README.md, Router): a firewall on the VM is gone with root on it. Where each server connects to is logged
# (kernel, "mcp-egress <name>:") and goes to the logs VM with the journal.
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
      # Published at /<name>/mcp (homelab.publish) for a front door to serve (mcp.peacocks.me), low-risk servers only:
      # never playwright (runs code) or github (holds a token). The router also has to let the edge in on its port.
      public = mkOption {
        type = types.bool;
        default = false;
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
  imports = [ ../web/publish.nix ] ++ map (name: ./servers/${name}) presets;

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

        # Each server is its own user (named in the egress log) with a private home for caches and state.
        User = "mcp-${name}";
        Group = "mcp-${name}";
        StateDirectory = "mcp-${name}";
        WorkingDirectory = "/var/lib/mcp-${name}";
      } // import ./hardening.nix;
    }) enabled;

    users.users = lib.mapAttrs' (name: _: lib.nameValuePair "mcp-${name}" {
      isSystemUser = true;
      group = "mcp-${name}";
    }) enabled;
    users.groups = lib.mapAttrs' (name: _: lib.nameValuePair "mcp-${name}" { }) enabled;

    networking.firewall.allowedTCPPorts = ports (lib.attrValues enabled);

    # A server's first TCP or UDP connection to each address and port, then nothing more to it for an hour (what it
    # called there is in the audit log): every destination shows, a loop to one doesn't flood the journal.
    networking.nftables.tables.mcp-egress = {
      family = "inet";
      content = lib.concatLines ([
        "set seen4 { typeof meta skuid . ip daddr . th dport; flags timeout; timeout 1h; }"
        "set seen6 { typeof meta skuid . ip6 daddr . th dport; flags timeout; timeout 1h; }"
        "chain output {"
        "  type filter hook output priority filter; policy accept;"
        "  oifname \"lo\" accept"
        "  ct state != new accept"
        "  meta skuid . ip daddr . th dport @seen4 accept"
        "  meta skuid . ip6 daddr . th dport @seen6 accept"
      ] ++ lib.concatMap (name: [
        "  meta nfproto ipv4 meta skuid \"mcp-${name}\" add @seen4 { meta skuid . ip daddr . th dport } log prefix \"mcp-egress ${name}: \""
        "  meta nfproto ipv6 meta skuid \"mcp-${name}\" add @seen6 { meta skuid . ip6 daddr . th dport } log prefix \"mcp-egress ${name}: \""
      ]) (lib.attrNames enabled) ++ [ "}" ]);
    };
    # The build's ruleset check has none of these users.
    networking.nftables.preCheckRuleset = ''
      sed 's/skuid "mcp-[^"]*"/skuid root/g' -i ruleset.conf
    '';

    homelab.publish.locations = lib.mapAttrs' (name: s: lib.nameValuePair "/${name}/mcp" {
      inherit (s) port;
      path = "/mcp";
    }) (lib.filterAttrs (_: s: s.public) enabled);
  };
}
