self:
{ lib, pkgs, ... }:

# REA as hosts/virtual/rea-dynamic runs it (homelab.mcp.rea), with two projects, driven from `client`
# through its nginx: every session gets its own REA, a project only sees its own samples and state,
# and the per-project servers are only reachable through nginx. `other` isn't a client and must be dropped.
let
  hello = lib.getExe pkgs.hello;
in
{
  name = "rea";

  nodes = {
    rea = { nodes, ... }: {
      imports = [
        self.inputs.sops-nix.nixosModules.sops
        ../modules/system/secrets.nix
        ../modules/services/mcp
      ];

      homelab.mcp.rea = {
        dynamic = true;
        projects = [ "alpha" "beta" ];
        clients = with nodes.client.networking; [ primaryIPAddress primaryIPv6Address ];
      };

      # As on the real host: modules/virtual.nix and modules/default.nix.
      networking.nftables.enable = true;
      users.users.admin.isNormalUser = true;

      # Each session's Ghidra takes a 2G heap, the JVMs are slow without KVM.
      virtualisation.memorySize = 6144;
      virtualisation.cores = 4;
      virtualisation.diskSize = 4096;
    };

    client = {
      environment.systemPackages = [
        (pkgs.writers.writePython3Bin "mcp-call" { flakeIgnore = [ "E501" ]; } (builtins.readFile ./mcp-call.py))
      ];
    };

    other = { };
  };

  testScript = { nodes, ... }: ''
    import json, shlex

    port = ${toString nodes.rea.homelab.mcp.rea.port}
    base = f"http://rea:{port}"

    def call(project, calls):
        """One session on a project: [(tool, arguments)] -> the results' text and isError."""
        requests = [["tools/call", {"name": t, "arguments": a}] for t, a in calls]
        out = json.loads(client.succeed(f"mcp-call {base}/{project}/mcp {shlex.quote(json.dumps(requests))}"))
        return [("\n".join(c.get("text", "") for c in r["content"]), r.get("isError", False)) for r in out["results"]]

    start_all()
    rea.wait_for_unit("nginx.service")
    for project in ("alpha", "beta"):
        rea.wait_for_unit(f"mcp-rea-{project}.service", timeout=900)
    rea.wait_for_open_port(port)

    with subtest("uploads per project"):
        client.succeed(f"curl -fsS -T ${hello} {base}/alpha/samples/hello")
        client.succeed(f"curl -fsS {base}/alpha/samples/ | grep -q hello")
        client.fail(f"curl -fsS {base}/beta/samples/ | grep -q hello")
        # One level only, and nothing outside a project's samples.
        client.fail(f"curl -fsS -T ${hello} {base}/alpha/samples/sub/hello")
        client.fail(f"curl -fsS -T ${hello} {base}/hello")
        client.fail(f"curl -fsS -T ${hello} {base}/gamma/samples/hello")
        rea.succeed("test \"$(stat -c %a /var/lib/rea-samples/alpha/hello)\" = 644")

    with subtest("a session per agent"):
        [(text, err)] = call("alpha", [("open_binary", {"path": "/var/lib/rea-samples/alpha/hello"})])
        assert not err and '"format":"elf"' in text, text
        # A new session starts with nothing open, not the first one's target.
        [(text, err)] = call("alpha", [("binary_session", {})])
        assert not err and '"open":false' in text, text

    with subtest("projects only see their own"):
        [(text, err)] = call("beta", [("open_binary", {"path": "/var/lib/rea-samples/alpha/hello"})])
        assert err, text
        text, err = call("alpha", [
            ("open_binary", {"path": "/var/lib/rea-samples/alpha/hello"}),
            ("export_evidence_bundle", {"path": "/var/lib/mcp-rea-alpha/shared/evidence.json"}),
        ])[1]
        assert not err, text
        rea.succeed("test -s /var/lib/mcp-rea-alpha/shared/evidence.json")
        # Another agent on the project picks it up, the other project can't.
        [(text, err)] = call("alpha", [("import_evidence_bundle", {"path": "/var/lib/mcp-rea-alpha/shared/evidence.json"})])
        assert not err, text
        [(text, err)] = call("beta", [("import_evidence_bundle", {"path": "/var/lib/mcp-rea-alpha/shared/evidence.json"})])
        assert err, text

    with subtest("clients allowlist"):
        other.wait_for_unit("multi-user.target")
        other.succeed("ping -c1 -W5 rea")
        for p in (port, ${toString nodes.rea.homelab.mcp.servers.rea-alpha.port}):
            for family in ("-4", "-6"):
                other.fail(f"curl {family} -sS --connect-timeout 5 http://rea:{p}/")
        # The project servers only listen for nginx.
        client.fail("curl -sS --connect-timeout 5 http://rea:${toString nodes.rea.homelab.mcp.servers.rea-alpha.port}/mcp")
  '';
}
