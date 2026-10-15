# From /etc/nginx/sites-enabled on the old box. Copy /var/www/<site>/public over after install,
# or point the site at the lab once it's hosted there.
{
  homelab.web.sites = {
    blog = {
      root = "/var/www/blog/public";
      # upstream = "http://10.100.0.20";   # once the blog runs in the lab
      # domains = [ "example.com" "www.example.com" ];
      # https = true;
      default = true;
    };
    # Only reachable through the tunnel.
    blog-staging = {
      root = "/var/www/blog-staging/public";
      address = "10.0.0.1";
    };
  };
}
