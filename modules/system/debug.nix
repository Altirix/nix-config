{ config, lib, ... }:

# Root password login, until user setup is done.
{
  options.homelab.debug.enable = lib.mkEnableOption "root password login over SSH";

  config = lib.mkIf config.homelab.debug.enable {
    users.users.root = {
      hashedPassword = "$6$7d8IZnWOR/EN5GMv$qrOdMoX9ZM4MdEt.Ab4qDfj.ea.cmf4..Lidif2aFkD.cc4Q4B4DHQH9J/2L1b.G28cO7JVoPxk2uQDN.ISZN0";
    };

    networking.firewall.allowedTCPPorts = [ 22 ];

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "yes";
        PasswordAuthentication = true;
      };
    };
  };
}
