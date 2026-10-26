self:
{ lib, pkgs, ... }:

# REA as hosts/virtual/rea-dynamic runs it (homelab.mcp.rea), with two projects, driven from `client`
# through its nginx: every session gets its own REA, each project its own URLs and directories, and the
# gateway is only reachable through nginx. Who reaches nginx is the router's call, not tested here.
let
  hello = lib.getExe pkgs.hello;
in
{
  name = "rea";

  nodes = {
    rea = {
      imports = [
        self.inputs.sops-nix.nixosModules.sops
        ../modules/system/secrets.nix
        ../modules/services/mcp
      ];

      homelab.mcp.rea = {
        dynamic = true;
        projects = [ "alpha" "beta" ];
        toolset = "firmware";
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
  };

  testScript = { nodes, ... }: ''
    import json, shlex

    port = ${toString nodes.rea.homelab.mcp.rea.port}
    gateway = ${toString nodes.rea.homelab.mcp.rea.gatewayPort}
    base = f"http://rea:{port}"

    def call(project, calls):
        """One session on a project: [(tool, arguments)] -> the results' text and isError."""
        requests = [["tools/call", {"name": t, "arguments": a}] for t, a in calls]
        out = json.loads(client.succeed(f"mcp-call {base}/{project}/mcp {shlex.quote(json.dumps(requests))}"))
        return [("\n".join(c.get("text", "") for c in r["content"]), r.get("isError", False)) for r in out["results"]]

    start_all()
    rea.wait_for_unit("rea.service", timeout=900)
    rea.wait_for_unit("nginx.service")
    rea.wait_for_open_port(gateway, timeout=900)
    rea.wait_for_open_port(port)

    with subtest("firmware toolset"):
        out = json.loads(client.succeed(f"mcp-call {base}/alpha/mcp \'[[\"tools/list\", {{}}]]\'"))
        names = [t["name"] for t in out["results"][0]["tools"]]
        assert "execute_rizin_command" in names and "compare_web_captures" not in names, names
        assert len(names) == ${toString (lib.length (lib.filter (l: l != "" && !lib.hasPrefix "#" l)
          (lib.splitString "\n" (builtins.readFile ../modules/services/mcp/config/rea-tools-firmware.txt))))}, len(names)
        assert all("outputSchema" not in t for t in out["results"][0]["tools"])

    with subtest("uploads per project"):
        client.succeed(f"curl -fsS -T ${hello} {base}/alpha/samples/hello")
        client.succeed(f"curl -fsS {base}/alpha/samples/ | grep -q hello")
        client.fail(f"curl -fsS {base}/beta/samples/ | grep -q hello")
        # One level only, nothing outside a project's samples, no undeclared projects.
        client.fail(f"curl -fsS -T ${hello} {base}/alpha/samples/sub/hello")
        client.fail(f"curl -fsS -T ${hello} {base}/hello")
        client.fail(f"curl -fsS -T ${hello} {base}/gamma/samples/hello")
        rea.succeed("test \"$(stat -c %a /var/lib/rea/alpha/samples/hello)\" = 644")

    try:
        with subtest("a session per agent"):
            [(text, err)] = call("alpha", [("open_binary", {"path": "/var/lib/rea/alpha/samples/hello"})])
            assert not err and '"format":"elf"' in text, text
            # A new session starts with nothing open, not the first one's target.
            [(text, err)] = call("alpha", [("binary_session", {})])
            assert not err and '"open":false' in text, text
            # A client trying 2026-07-28 first is turned away, so it falls back to a session (packages/rea.nix).
            meta = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
                    "io.modelcontextprotocol/clientInfo": {"name": "t", "version": "0"},
                    "io.modelcontextprotocol/clientCapabilities": {}}
            discover = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "server/discover", "params": {"_meta": meta}})
            out = client.succeed(f"curl -sS -X POST {base}/alpha/mcp -H 'Content-Type: application/json' "
                                 f"-H 'Accept: application/json, text/event-stream' -H 'MCP-Protocol-Version: 2026-07-28' "
                                 f"-H 'Mcp-Method: server/discover' -d {shlex.quote(discover)}")
            assert "Unsupported protocol version" in out, out
            # mcp-call DELETEs its session: its REA is gone.
            rea.wait_until_succeeds("! pgrep -u rea -f 'rea.mjs mcp'", timeout=60)

        with subtest("cli endpoint"):
            # The project's CLI tools in a REA of their own: rizin beside an open Ghidra session.
            out = json.loads(client.succeed(f"mcp-call {base}/alpha/cli/mcp \'[[\"tools/list\", {{}}]]\'"))
            names = sorted(t["name"] for t in out["results"][0]["tools"])
            assert names == sorted(${builtins.toJSON (lib.filter (l: l != "" && !lib.hasPrefix "#" l)
              (lib.splitString "\n" (builtins.readFile ../modules/services/mcp/config/rea-tools-cli.txt)))}), names
            [(text, err)] = call("alpha/cli", [("execute_rizin_command", {"path": "/var/lib/rea/alpha/samples/hello", "command": "iI~bits"})])
            assert not err and "64" in text, text

        with subtest("rizin and objdump"):
            # ESIL emulation, what agents reach for first on rea-dynamic.
            [(text, err)] = call("alpha", [("execute_rizin_command", {"path": "/var/lib/rea/alpha/samples/hello", "command": "aei; aeim; ar"})])
            assert not err and "rip" in text, text
            [(text, err)] = call("alpha", [("inspect_with_objdump", {"path": "/var/lib/rea/alpha/samples/hello", "operation": "file_headers"})])
            assert not err and "elf64" in text, text

        with subtest("sharing"):
            bundle = "/var/lib/rea/alpha/shared/evidence/main__agent-1.json"
            text, err = call("alpha", [
                ("open_binary", {"path": "/var/lib/rea/alpha/samples/hello"}),
                ("export_evidence_bundle", {"path": bundle}),
            ])[1]
            assert not err, text
            rea.succeed(f"test -s {bundle}")
            # nginx serves it, read-only, once rea-shared.path has caught the write.
            client.succeed(f"curl -fsS {base}/alpha/shared/evidence/ | grep -q main__agent-1.json")
            client.wait_until_succeeds(f"curl -fsS {base}/alpha/shared/evidence/main__agent-1.json | grep -q .", timeout=60)
            client.fail(f"curl -fsS -T ${hello} {base}/alpha/shared/hello")
            client.fail(f"curl -fsS {base}/beta/shared/evidence/main__agent-1.json")
            # Another agent picks it up.
            [(text, err)] = call("alpha", [("import_evidence_bundle", {"path": bundle})])
            assert not err, text
            # An undeclared project has no server.
            client.fail(f"mcp-call {base}/gamma/mcp '[]'")
    finally:
        print(rea.succeed("journalctl -u rea -o cat | tail -n 40"))

    with subtest("memory cap"):
        rea.succeed("systemctl show -p MemoryMax rea | grep -v infinity")

    with subtest("gateway only listens for nginx"):
        client.fail(f"curl -sS --connect-timeout 5 http://rea:{gateway}/alpha/mcp")
  '';
}
