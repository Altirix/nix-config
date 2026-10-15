{ config, lib, pkgs, ... }:

# A Minecraft server (vanilla unless `package` says otherwise). The world lives in /var/lib/minecraft,
# ops/bans and the world itself aren't managed by nix, only server.properties and the whitelist.
let
  cfg = config.homelab.minecraft;
  inherit (lib) mkOption types;
in
{
  options.homelab.minecraft = {
    enable = lib.mkEnableOption "a Minecraft server";

    package = mkOption {
      type = types.package;
      default = pkgs.minecraft-server;
    };

    port = mkOption {
      type = types.port;
      default = 25565;
    };

    # JVM heap, e.g. "4G".
    memory = mkOption {
      type = types.str;
      default = "2G";
    };

    # Merged into server.properties, see https://minecraft.wiki/w/Server.properties.
    properties = mkOption {
      type = types.attrsOf (types.oneOf [ types.bool types.int types.str ]);
      default = { };
    };

    # Player name -> UUID, an empty set leaves the whitelist off.
    whitelist = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    # Vanilla is unfree, everything else stays blocked by modules/default.nix.
    nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == lib.getName cfg.package;

    services.minecraft-server = {
      enable = true;
      eula = true;
      declarative = true;
      openFirewall = true;
      inherit (cfg) package whitelist;
      jvmOpts = "-Xms${cfg.memory} -Xmx${cfg.memory} -XX:+UseG1GC";
      serverProperties = {
        server-port = cfg.port;
        white-list = cfg.whitelist != { };
        enforce-whitelist = cfg.whitelist != { };
      } // cfg.properties;
    };
  };
}
