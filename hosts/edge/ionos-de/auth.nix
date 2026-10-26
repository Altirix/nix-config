# auth.peacocks.me, Kanidm on the auth VM (hosts/virtual/auth, 10.100.1.13) over the tunnel. Its certificate is
# self-signed and not checked, the hop is inside the tunnel and labs. The router lets this host's tunnel address in
# on 8443 only (hosts/virtual/auth/README.md).
{
  homelab.web.sites.auth = {
    domains = [ "auth.peacocks.me" ];
    https = true;
    upstream = "https://10.100.1.13:8443";
  };

  # Clients look up an issuer with a path (https://auth.peacocks.me/oauth2/openid/<client>) at
  # /.well-known/<document>/oauth2/openid/<client> (RFC 8414), Kanidm only serves it under the issuer.
  services.nginx.virtualHosts.auth.extraConfig = ''
    rewrite ^/\.well-known/(oauth-authorization-server|openid-configuration)(/oauth2/openid/[^/]+)$ $2/.well-known/$1 last;
  '';

  # oauth2-proxy reads the issuer through this host's own nginx, not out and back in.
  networking.hosts."127.0.0.1" = [ "auth.peacocks.me" ];
}
