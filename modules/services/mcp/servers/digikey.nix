{ config, lib, pkgs, ... }:

# DigiKey's Product Information v4 API (packages/digikey-mcp.nix): search, details, quantity pricing, substitutes and
# media, in `site`'s currency. Only reads: the app's client credentials (2-legged OAuth) reach no orders or account.
# Make an app at developer.digikey.com (Production, Product Information v4) and put its Client ID and Secret in the
# host's sops file as digikey-client-id and digikey-client-secret; the host doesn't build without them.
let
  cfg = config.homelab.mcp.digikey;
  enable = config.homelab.mcp.servers.digikey.enable;
in
{
  options.homelab.mcp.digikey = {
    # The DigiKey site and currency prices and stock come from.
    site = lib.mkOption {
      type = lib.types.str;
      default = "UK";
    };
    currency = lib.mkOption {
      type = lib.types.str;
      default = "GBP";
    };
  };

  config = {
    homelab.mcp.servers.digikey = {
      command = lib.mkDefault (lib.getExe (pkgs.callPackage ../packages/digikey-mcp.nix { }));
      port = lib.mkDefault 8117;
      environment = {
        DIGIKEY_LOCALE_SITE = cfg.site;
        DIGIKEY_LOCALE_CURRENCY = cfg.currency;
      };
      environmentFile = lib.mkIf enable (lib.mkDefault config.sops.templates."mcp-digikey.env".path);
    };

    sops = lib.mkIf enable {
      secrets."digikey-client-id" = { };
      secrets."digikey-client-secret" = { };

      templates."mcp-digikey.env" = {
        content = ''
          DIGIKEY_CLIENT_ID=${config.sops.placeholder."digikey-client-id"}
          DIGIKEY_CLIENT_SECRET=${config.sops.placeholder."digikey-client-secret"}
        '';
        restartUnits = [ "mcp-digikey.service" ];
      };
    };
  };
}
