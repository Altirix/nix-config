{ config, lib, pkgs, utils, ... }:

# MCP servers, one systemd unit and port each. stdio servers are put behind mcp-proxy, which
# serves streamable HTTP on /mcp and SSE on /sse and shares one server process between all clients.
# There is no auth and no Host check. Every port is open on the VM, who reaches which is the router's call
# (README.md): a firewall on the VM is gone with root on it. Where each server connects to is logged
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
      # Ports on this VM the server may connect to, a backend of its own (searxng's SearXNG). Otherwise a server only
      # reaches other hosts (config/egress.nft): never another server, a browser's display or anything else here.
      localPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
      };
      # Published at /<name>/mcp (homelab.publish) for a front door to serve (mcp.peacocks.me), low-risk servers or
      # ones whose risky tools `edgeDeny` takes away. The router also has to let the edge in on its port.
      public = mkOption {
        type = types.bool;
        default = false;
      };
      # The path the server itself answers MCP on, which the front door connects to. /mcp/ for a server that
      # redirects /mcp there (Starlette's mounts do), whose redirect would drop the front door's prefix.
      endpoint = mkOption {
        type = types.str;
        default = "/mcp";
      };
      # Tools the front door refuses, and leaves out of the tool list, when it's published (agentgateway). Clients
      # reaching the server directly (the LAN) still have them.
      edgeDeny = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      # Where it's published, /<name>/mcp unless set (e.g. /kicad/<project>/mcp for a server per project).
      publishAt = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  enabled = lib.filterAttrs (_: s: s.enable) cfg.servers;
  ports = map (s: s.port);

  presets = lib.attrNames (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name)
    (builtins.readDir ./servers));

  proxy = [ (lib.getExe pkgs.mcp-proxy) "--host" "0.0.0.0" "--port" ];

  # The ports the kernel hands out, pinned (net.ipv4.ip_local_port_range): servers may reach their own processes on
  # these over loopback (config/egress.nft), so nothing listening here for good may be among them.
  ephemeral = { from = 32768; to = 60999; };
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
      {
        assertion = lib.all (p: p < ephemeral.from || p > ephemeral.to)
          (ports (lib.attrValues enabled) ++ lib.concatMap (s: s.localPorts) (lib.attrValues enabled));
        message = "mcp: servers' ports and localPorts stay out of ${toString ephemeral.from}-${toString ephemeral.to}, the ones the kernel hands out";
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

    # Where each server connects to (config/egress.nft).
    networking.nftables.tables.mcp-egress = {
      family = "inet";
      content = builtins.replaceStrings [ "@servers@" "@users@" "@backends@" "@ephemeral@" ]
        [
          (lib.concatMapStrings (name: builtins.replaceStrings [ "@name@" ] [ name ] (builtins.readFile ./config/egress-server.nft))
            (lib.attrNames enabled))
          (lib.concatMapStringsSep ", " (name: ''"mcp-${name}"'') (lib.attrNames enabled))
          (let local = lib.concatLists (lib.mapAttrsToList (name: s: map (port: ''"mcp-${name}" . ${toString port}'') s.localPorts) enabled);
          in lib.optionalString (local != [ ]) "elements = { ${lib.concatStringsSep ", " local} }")
          "${toString ephemeral.from}-${toString ephemeral.to}"
        ]
        (builtins.readFile ./config/egress.nft);
    };
    boot.kernel.sysctl."net.ipv4.ip_local_port_range" = "${toString ephemeral.from} ${toString ephemeral.to}";

    # The build's ruleset check has none of these users.
    networking.nftables.preCheckRuleset = ''
      sed 's/"mcp-[a-z0-9-]*"/root/g' -i ruleset.conf
    '';

    homelab.publish.locations = lib.mapAttrs' (name: s: lib.nameValuePair (if s.publishAt != null then s.publishAt else "/${name}/mcp") {
      inherit (s) port;
      path = s.endpoint;
      mcp = true;
      deny = s.edgeDeny;
    }) (lib.filterAttrs (_: s: s.public) enabled);
  };
}
