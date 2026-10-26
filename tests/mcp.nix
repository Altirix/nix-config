self:
{ lib, pkgs, ... }:

# The MCP servers hosts/virtual/mcp enables, run by the real module, each initialized and its tools
# listed over streamable HTTP from `client`. Who reaches which port is the router's call, not tested here.
# The VMs have no internet, so tools are only called where they stay on the test network.
let
  # github needs the host's sops key for its token, which the test VM doesn't have.
  enabled = lib.attrNames (lib.filterAttrs (name: s: s.enable && name != "github")
    self.nixosConfigurations.mcp.config.homelab.mcp.servers);

  # A tool each server must list.
  tools = {
    nixos = "nix";
    github = "get_me";
    context7 = "resolve-library-id";
    fetch = "fetch";
    time = "get_current_time";
    memory = "read_graph";
    playwright = "browser_navigate";
    markitdown = "convert_to_markdown";
  };

  page = pkgs.writeTextDir "index.html" "<html><head><title>mcp-test</title></head><body><h1>Hello from client</h1></body></html>";
in
{
  name = "mcp";

  nodes = {
    mcp = {
      # The github preset declares its sops secret, sops itself stays unused with github off.
      imports = [
        self.inputs.sops-nix.nixosModules.sops
        ../modules/system/secrets.nix
        ../modules/services/mcp
      ];

      homelab.mcp.servers = lib.genAttrs enabled (_: { enable = true; });

      # As on the real host: modules/virtual.nix and modules/default.nix.
      networking.nftables.enable = true;
      time.timeZone = "Europe/London";
      users.users.admin.isNormalUser = true;

      # Chromium is slow without KVM.
      virtualisation.memorySize = 6144;
      virtualisation.cores = 4;
      virtualisation.diskSize = 4096;
    };

    # The agent, and a web page for the tools that fetch.
    client = {
      environment.systemPackages = [
        (pkgs.writers.writePython3Bin "mcp-call" { flakeIgnore = [ "E501" ]; } (builtins.readFile ./mcp-call.py))
      ];
      services.nginx = {
        enable = true;
        virtualHosts.default.root = page;
      };
      networking.firewall.allowedTCPPorts = [ 80 ];
    };
  };

  testScript = { nodes, ... }: ''
    import json, shlex

    servers = json.loads(${builtins.toJSON (builtins.toJSON (lib.genAttrs enabled (name: {
      port = nodes.mcp.homelab.mcp.servers.${name}.port;
      tool = tools.${name};
    })))})

    # Tool calls that stay on the test network: (tool, arguments, text the result must contain).
    calls = {
        "time": [("get_current_time", {"timezone": "Europe/London"}, "Europe/London")],
        "memory": [
            ("create_entities", {"entities": [{"name": "nixos-test", "entityType": "test",
                                               "observations": ["written by the VM test"]}]}, "nixos-test"),
            ("read_graph", {}, "written by the VM test"),
        ],
        "fetch": [("fetch", {"url": "http://client/"}, "Hello from client")],
        "markitdown": [("convert_to_markdown", {"uri": "http://client/"}, "Hello from client")],
        "playwright": [("browser_navigate", {"url": "http://client/"}, "mcp-test")],
    }

    def session(name, requests, retry=False):
        cmd = f"mcp-call http://mcp:{servers[name]['port']}/mcp {shlex.quote(json.dumps(requests))}"
        return json.loads(client.wait_until_succeeds(cmd, timeout=900) if retry else client.succeed(cmd))

    def check(name):
        mcp.wait_for_unit(f"mcp-{name}.service", timeout=900)
        mcp.wait_for_open_port(servers[name]["port"], timeout=900)

        out = session(name, [["tools/list", {}]], retry=True)
        tools = [t["name"] for t in out["results"][0]["tools"]]
        print(f"{name}: {out['serverInfo']}, {len(tools)} tools")
        assert servers[name]["tool"] in tools, tools

        if name in calls:
            out = session(name, [["tools/call", {"name": t, "arguments": a}] for t, a, _ in calls[name]])
            for (tool, _, expect), result in zip(calls[name], out["results"]):
                text = "\n".join(c.get("text", "") for c in result["content"])
                print(f"{name} {tool}: {text[:300]!r}")
                assert not result.get("isError") and expect in text, f"{name} {tool}: {text}"

    start_all()
    client.wait_for_unit("nginx.service")
    client.wait_for_open_port(80)

    for name in servers:
        with subtest(name):
            try:
                check(name)
            finally:
                print(mcp.succeed(f"journalctl -u mcp-{name} -o cat | tail -n 40"))

    if "memory" in servers:
        with subtest("memory graph in the state dir"):
            mcp.succeed("grep -q nixos-test /var/lib/mcp-memory/memory.jsonl")
  '';
}
