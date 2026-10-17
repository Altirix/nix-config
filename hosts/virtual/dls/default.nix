{ config, inputs, ... }:

# FastAPI-DLS, licenses the vGPU guests over labs-mesh. A guest sets homelab.vgpu.license.server to listen.ip and
# license.rootCa to a copy of /var/lib/fastapi-dls/cert/my_root_certificate.pem.
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
    listen.ip = config.homelab.labsMesh.ip;
    lease.expire = 90;
  };

  networking.firewall.interfaces.${config.homelab.labsMesh.interface}.allowedTCPPorts = [ 443 ];
}
