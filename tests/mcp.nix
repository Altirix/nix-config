self:
{ lib, pkgs, ... }:

# The MCP servers hosts/virtual/mcp and mcp-web enable, run by the real module on one VM, each initialized and its
# tools listed over streamable HTTP from `client`. Who reaches which port is the router's call, not tested here.
# The VMs have no internet, so tools are only called where they stay on the test network.
let
  # paperless needs the host's sops key for its token, which the test VM doesn't have. The host's KiCad projects
  # follow GitHub, the test has one of its own (kicad-t) following a local repo.
  skip = name: name == "paperless" || lib.hasPrefix "kicad-" name;
  servers = host: lib.filterAttrs (name: s: s.enable && !skip name)
    self.nixosConfigurations.${host}.config.homelab.mcp.servers;
  enabled = lib.attrNames (servers "mcp" // servers "mcp-web") ++ [ "kicad-t" ];

  # A tool each server must list.
  tools = {
    nixos = "nix";
    context7 = "resolve-library-id";
    fetch = "fetch";
    time = "get_current_time";
    memory = "read_graph";
    playwright = "browser_navigate";
    markitdown = "convert_to_markdown";
    fdfdb = "search_part_number";
    kicad-t = "kicad_create_new_project";
  };

  page = pkgs.writeTextDir "index.html" "<html><head><title>mcp-test</title></head><body><h1>Hello from client</h1></body></html>";
in
{
  name = "mcp";

  nodes = {
    mcp = {
      # The paperless and KiCad presets declare sops secrets, sops itself stays unused with them off.
      imports = [
        self.inputs.sops-nix.nixosModules.sops
        ../modules/system/secrets.nix
        ../modules/services/mcp
      ];

      homelab.mcp.servers = lib.genAttrs enabled (_: { enable = true; });

      # A project kept in step with a repo on the VM, which its pushes write to. The source has a commit before the
      # clone, as a GitHub repo must.
      homelab.mcp.kicad.projects.t = { port = 9200; url = "/var/lib/kicad-src/t.git"; };
      systemd.services.kicad-sync-t.serviceConfig.ReadWritePaths = [ "/var/lib/kicad-src" ];
      systemd.services.kicad-src-t = {
        requiredBy = [ "kicad-repo-t.service" ];
        before = [ "kicad-repo-t.service" ];
        path = [ pkgs.git ];
        serviceConfig.Type = "oneshot";
        script = ''
          git init -q --bare -b main /var/lib/kicad-src/t.git
          git clone -q /var/lib/kicad-src/t.git /tmp/seed
          cd /tmp/seed && echo a > a && git add a && git commit -qm a && git push -q origin HEAD:main
          chown -R kicad-sync-t:kicad /var/lib/kicad-src
        '';
      };

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
        "fdfdb": [
            ("search_part_number", {"part_number": "MT29F512G08EEHAF"}, "2CA40832A100"),
            ("search_flash_id", {"flash_id": "2C A4 08 32 A1 00"}, "MT29F512G08EEHAF"),
        ],
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

    with subtest("kicad sync"):
        # Someone working in the source (as kicad-sync-t, which owns it) and an agent in the project.
        upstream = lambda cmd: f"runuser -u kicad-sync-t -- sh -c 'cd /tmp/t && {cmd}'"
        agent = lambda cmd: f"runuser -u mcp-kicad-t -- sh -c 'umask 002; cd /var/lib/kicad/t && {cmd}'"
        log = "git -C /var/lib/kicad-src/t.git log --format=%s main"

        # The project is the source's clone.
        mcp.succeed(
            "test -f /var/lib/kicad/t/a",
            "runuser -u kicad-sync-t -- git clone -q /var/lib/kicad-src/t.git /tmp/t",
        )
        # The source's commits come down, an agent's go up.
        mcp.succeed("systemctl start kicad-sync-t")
        mcp.succeed(agent("echo b > b && git add b && git commit -qm b"), "systemctl start kicad-sync-t", f"{log} | grep -qx b")

        # Both sides committed: the agent's is rebased onto the source's, under the VM's git identity.
        mcp.succeed(
            upstream("git pull -q origin main && echo c > c && git add c && git commit -qm c && git push -q origin HEAD:main"),
            agent("echo d > d && git add d && git commit -qm d"),
            "systemctl start kicad-sync-t",
            f"{log} | head -n 2 | tr '\\n' ' ' | grep -qx 'd c '",
            "test -f /var/lib/kicad/t/c",
        )

        # A conflict: nothing goes up, the project keeps its commit and isn't left mid-rebase.
        mcp.succeed(
            upstream("git pull -q origin main && echo x > a && git commit -qam x && git push -q origin HEAD:main"),
            agent("echo y > a && git commit -qam y"),
        )
        mcp.fail("systemctl start kicad-sync-t")
        mcp.succeed(
            f"! {log} | grep -qx y",
            "test ! -e /var/lib/kicad/t/.git/rebase-merge -a ! -e /var/lib/kicad/t/.git/rebase-apply",
            "git -C /var/lib/kicad/t log -1 --format=%s | grep -qx y",
        )

    with subtest("no server opens another over loopback"):
        curl = "${pkgs.curl}/bin/curl -sS --max-time 5 -o /dev/null"
        target = f"http://127.0.0.1:{servers['kicad-t']['port']}/mcp"
        mcp.fail(f"runuser -u mcp-time -- {curl} {target}")
        mcp.fail(f"runuser -u mcp-time -- {curl} http://mcp:{servers['kicad-t']['port']}/mcp")
        # Anyone else on the VM still does (it's the router that keeps others out).
        mcp.succeed(f"{curl} {target}")

    if "memory" in servers:
        with subtest("memory graph in the state dir"):
            mcp.succeed("grep -q nixos-test /var/lib/mcp-memory/memory.jsonl")
  '';
}
