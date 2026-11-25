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

  # The playwrights are public with the tools reaching past the browser refused at the edge (their edgeDeny): Node in
  # the server, files off the VM. Agents on the LAN (labs: agents to mcp-web) still have them.
  homelab.mcp.servers = {
    fetch = { enable = true; public = true; };
    markitdown = { enable = true; public = true; };
    searxng = { enable = true; public = true; };
    playwright-chromium = { enable = true; public = true; };
    playwright-firefox = { enable = true; public = true; };
  };
}
