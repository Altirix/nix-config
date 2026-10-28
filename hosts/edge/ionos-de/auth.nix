{ lib, ... }:

# auth.peacocks.me, Kanidm on the auth VM (hosts/virtual/auth, 10.100.1.13) over the tunnel, accepting only the
# VM's own certificate. The router lets this host's tunnel address in on 8443 only (hosts/virtual/auth/README.md).
let
  # Copied from the VM once it's installed (hosts/virtual/auth/README.md).
  certificate = ../../virtual/auth/tls.pem;
  pinned = builtins.pathExists certificate;
in
{
  homelab.web.sites.auth = {
    domains = [ "auth.peacocks.me" ];
    https = true;
    upstream = "https://10.100.1.13:8443";
    upstreamCertificate = if pinned then certificate else null;
  };

  warnings = lib.optional (!pinned)
    "ionos-de: hosts/virtual/auth/tls.pem is missing, auth.peacocks.me proxies to whatever answers at 10.100.1.13";

  # Clients look up an issuer with a path (https://auth.peacocks.me/oauth2/openid/<client>) at
  # /.well-known/<document>/oauth2/openid/<client> (RFC 8414), Kanidm only serves it under the issuer.
  services.nginx.virtualHosts.auth.extraConfig = ''
    rewrite ^/\.well-known/(oauth-authorization-server|openid-configuration)(/oauth2/openid/[^/]+)$ $2/.well-known/$1 last;
  '';

  # oauth2-proxy reads the issuer through this host's own nginx, not out and back in.
  networking.hosts."127.0.0.1" = [ "auth.peacocks.me" ];
}
