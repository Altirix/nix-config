# logs.peacocks.me, the logs VM's web UI and queries (hosts/virtual/logs, 10.100.0.11:9427) behind Kanidm sign-in
# (members of web_users). The router lets this host's tunnel address in on 9427 only (hosts/virtual/logs/README.md).
{
  homelab.web.sites.logs = {
    domains = [ "logs.peacocks.me" ];
    https = true;
    upstream = "http://10.100.0.11:9427";
    sso = true;
  };
}
