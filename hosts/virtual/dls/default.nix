{ config, inputs, ... }:

# FastAPI-DLS, licenses the vGPU guests over labs (through the router, `labs: dls in`). A guest sets
# homelab.vgpu.license.server to listen.ip and license.rootCa to a copy of /var/lib/fastapi-dls/cert/my_root_certificate.pem.
{
  imports = [
    ../../../modules/virtual.nix
    inputs.fastapi-dls-nixos.nixosModules.default
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  services.fastapi-dls = {
    enable = true;
    # Also written into client tokens as the address guests license against, so never 0.0.0.0.
    listen.ip = config.homelab.labs.address;
    lease.expire = 90;
  };

  # Only on the labs bridge, the router decides who reaches it.
  networking.firewall.allowedTCPPorts = [ 443 ];
}
