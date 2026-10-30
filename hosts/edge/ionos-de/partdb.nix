# parts.peacocks.me, Part-DB on its VM (hosts/virtual/partdb, 10.100.2.10) behind Kanidm sign-in (members of
# web_users), then Part-DB's own login. The router lets this host's tunnel address in on 80 only
# (hosts/virtual/partdb/default.nix).
{
  homelab.web.sites.partdb = {
    domains = [ "parts.peacocks.me" ];
    https = true;
    upstream = "http://10.100.2.10";
    sso = true;
  };
}
