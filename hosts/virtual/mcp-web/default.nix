{ ... }:

# MCP servers that take untrusted input from the web (modules/services/mcp/README.md, Where servers run): pages
# and their scripts, any URL, any file. Kept apart from the ones holding tokens and keys (hosts/virtual/mcp), with
# nothing worth taking and no way into the lab, only the internet.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  # Two headed browsers, each on its own display, and SearXNG.
  homelab.vm = {
    cpus = 4;
    memory = "6GiB";
  };

  # Never make a playwright public: it runs code.
  homelab.mcp.servers = {
    fetch = { enable = true; public = true; };
    markitdown = { enable = true; public = true; };
    searxng = { enable = true; public = true; };
    playwright-chromium.enable = true;
    playwright-firefox.enable = true;
  };
}
