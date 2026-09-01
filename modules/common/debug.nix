{ config, pkgs, ... }:

# until user setup is done
{
  users.users.root = {
    hashedPassword = "$6$7d8IZnWOR/EN5GMv$qrOdMoX9ZM4MdEt.Ab4qDfj.ea.cmf4..Lidif2aFkD.cc4Q4B4DHQH9J/2L1b.G28cO7JVoPxk2uQDN.ISZN0";
  };

  # allow over SSH too
  services.openssh.settings.PermitRootLogin = pkgs.lib.mkForce "yes";
}