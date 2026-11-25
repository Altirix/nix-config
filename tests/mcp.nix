self:
{ lib, pkgs, ... }:

# The MCP servers hosts/virtual/mcp and mcp-web enable, run by the real module on one VM, each initialized and its
# tools listed over streamable HTTP from `client`. Who reaches which port is the router's call, not tested here.
# The VMs have no internet, so tools are only called where they stay on the test network.
let
  # paperless and digikey need the host's sops key for their tokens, which the test VM doesn't have. The host's KiCad
  # projects follow GitHub, the test has one of its own (kicad-t) following a local repo.
  skip = name: name == "paperless" || name == "digikey" || lib.hasPrefix "kicad-" name;
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
    playwright-chromium = "browser_navigate";
    playwright-firefox = "browser_navigate";
    searxng = "searxng_web_search";
    # Its catalog can't be downloaded here, the server still starts and lists its tools.
    jlcpcb = "jlcpcb_search_components";
    fdfdb = "search_part_number";
    kicad-t = "kicad_create_new_project";
  };

  # An empty two-layer board, for the KiCad project's live editing.
  board = pkgs.writeText "board.kicad_pcb" ''
    (kicad_pcb (version 20241229) (generator "pcbnew") (generator_version "10.0") (general (thickness 1.6))
      (paper "A4") (layers (0 "F.Cu" signal) (2 "B.Cu" signal) (25 "Edge.Cuts" user)) (setup (pad_to_mask_clearance 0)))
  '';

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
      homelab.mcp.kicad.mode = "experimental";
      systemd.services."kicad-git-t-receive-pack@".serviceConfig.ReadWritePaths = [ "/var/lib/kicad-src" ];
      # Without KVM the VM is emulated, and loading KiCad's footprint libraries takes kicad-cli's DRC minutes.
      systemd.services.mcp-kicad-t.environment.KICAD_MCP_CLI_TIMEOUT = "600";
      systemd.services.kicad-src-t = {
        requiredBy = [ "kicad-repo-t.service" ];
        before = [ "kicad-repo-t.service" ];
        path = [ pkgs.git ];
        serviceConfig.Type = "oneshot";
        script = ''
          git init -q --bare -b main /var/lib/kicad-src/t.git
          git clone -q /var/lib/kicad-src/t.git /tmp/seed
          cd /tmp/seed && echo a > a && cp ${board} board_a.kicad_pcb && cp ${board} board_b.kicad_pcb
          git add . && git commit -qm a && git push -q origin HEAD:main
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

  testScript = { nodes, ... }: let
    playwrights = lib.filterAttrs (browser: _: lib.elem "playwright-${browser}" enabled) nodes.mcp.homelab.mcp.playwright;
  in ''
    import json, shlex

    servers = json.loads(${builtins.toJSON (builtins.toJSON (lib.genAttrs enabled (name: {
      port = nodes.mcp.homelab.mcp.servers.${name}.port;
      tool = tools.${name};
    })))})
    views = json.loads(${builtins.toJSON (builtins.toJSON (lib.mapAttrs' (browser: v: lib.nameValuePair "playwright-${browser}" v.viewPort) playwrights))})
    displays = json.loads(${builtins.toJSON (builtins.toJSON (lib.mapAttrsToList (_: v: v.display) playwrights))})

    # Tool calls that stay on the test network: (tool, arguments, text the result must contain).
    calls = {
        "time": [("get_current_time", {"timezone": "Europe/London"}, "Europe/London")],
        "memory": [
            ("create_entities", {"entities": [{"name": "nixos-test", "entityType": "test",
                                               "observations": ["written by the VM test"]}]}, "nixos-test"),
            ("read_graph", {}, "written by the VM test"),
        ],
        "fetch": [("fetch", {"url": "http://client/"}, "Hello from client")],
        "fdfdb": [
            ("search_part_number", {"part_number": "MT29F512G08EEHAF"}, "2CA40832A100"),
            ("search_flash_id", {"flash_id": "2C A4 08 32 A1 00"}, "MT29F512G08EEHAF"),
        ],
        "playwright-chromium": [("browser_navigate", {"url": "http://client/"}, "mcp-test")],
        "playwright-firefox": [("browser_navigate", {"url": "http://client/"}, "mcp-test")],
        # Its own SearXNG on loopback answers, with every engine it can ask.
        "searxng": [("searxng_instance_info", {}, '"available": true')],
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

    # Each browser's display as a web page, for a person to solve what an agent can't.
    for name, port in views.items():
        with subtest(f"{name} view"):
            mcp.wait_for_unit(f"mcp-{name}-view.service", timeout=900)
            mcp.wait_for_open_port(port, timeout=900)
            # Saved first: grep -q stops reading at the match, and curl's failed write (23) fails the pipe.
            client.succeed(f"${pkgs.curl}/bin/curl -sf -o /tmp/view.html http://mcp:{port}/vnc.html")
            client.succeed("grep -q noVNC /tmp/view.html")

    with subtest("kicad git: the agent fetches, branches, pulls and pushes"):
        # Someone working in the source (as kicad-sync-t, which owns it) and an agent in the project, whose git goes
        # through the project's sockets.
        upstream = lambda cmd: f"runuser -u kicad-sync-t -- sh -c 'cd /tmp/t && {cmd}'"
        agent = lambda cmd: f"runuser -u mcp-kicad-t -- sh -c 'umask 002; cd /var/lib/kicad/t && {cmd}'"
        # The source as root, who doesn't own it.
        src_git = "git -c safe.directory=/var/lib/kicad-src/t.git -C /var/lib/kicad-src/t.git"
        src_log = lambda branch: f"{src_git} log --format=%s {branch}"
        call = lambda name, args: ["tools/call", {"name": name, "arguments": args}]
        project = call("kicad_set_project", {"project_dir": "/var/lib/kicad/t"})

        def tools(*calls, failing=()):
            out = session("kicad-t", [project, *calls])
            for i, result in enumerate(out["results"]):
                text = "\n".join(c.get("text", "") for c in result["content"])
                print(f"kicad-t git: {text[:300]!r}")
                assert bool(result.get("isError")) == (i in failing), text
            return out

        mcp.succeed(
            "test -f /var/lib/kicad/t/a",
            "runuser -u kicad-sync-t -- git clone -q /var/lib/kicad-src/t.git /tmp/t",
        )
        # Its own branch, a commit, a push.
        mcp.succeed(agent("echo b > b"))
        tools(
            call("vcs_fetch", {}),
            call("vcs_branch", {"name": "layout", "create": True}),
            call("vcs_commit_checkpoint", {"message": "b", "auto_drc": False}),
            call("vcs_push", {}),
        )
        mcp.succeed(f"{src_log('layout')} | head -n 1 | grep -qx b", f"! {src_log('main')} | grep -qx b")

        # Someone pushed to main (a footprint, a document): the agent pulls it in while mid-edit, and pushes.
        mcp.succeed(
            upstream("echo c > c && git add c && git commit -qm c && git push -q origin HEAD:main"),
            agent("echo edit >> b"),
        )
        tools(call("vcs_pull", {"branch": "main"}), call("vcs_push", {}))
        mcp.succeed("test -f /var/lib/kicad/t/c", "grep -qx edit /var/lib/kicad/t/b", f"{src_log('layout')} | grep -qx c")
        mcp.succeed(agent("git checkout -q b"))

        # A conflict, the same line on both sides: the pull fails and undoes itself, the agent's commit stays.
        mcp.succeed(
            upstream("git pull -q origin main && echo x > a && git commit -qam x && git push -q origin HEAD:main"),
            agent("echo y > a"),
        )
        tools(call("vcs_commit_checkpoint", {"message": "y", "auto_drc": False}), call("vcs_pull", {"branch": "main"}),
              failing={2})
        mcp.succeed(
            "test ! -e /var/lib/kicad/t/.git/MERGE_HEAD",
            "grep -qx y /var/lib/kicad/t/a",
            "git -C /var/lib/kicad/t log -1 --format=%s | grep -qx y",
        )

        # The gate: main can't be pushed, and no branch can be rewritten or deleted, by the tools or by git itself
        # with the server's config.
        tools(call("vcs_push", {"branch": "main"}), failing={1})
        mcp.succeed(f"! {src_log('main')} | grep -qx y")
        gitconfig = "$(systemctl show -p Environment --value mcp-kicad-t | tr ' ' '\\n' | sed -n 's/^GIT_CONFIG_GLOBAL=//p')"
        raw = lambda cmd: f"runuser -u mcp-kicad-t -- env GIT_CONFIG_GLOBAL={gitconfig} sh -c 'cd /var/lib/kicad/t && {cmd}'"
        layout = mcp.succeed(f"{src_git} rev-parse layout").strip()
        mcp.fail(raw("git push --force origin $(git rev-list --max-parents=0 HEAD):refs/heads/layout"))
        mcp.fail(raw("git push origin :refs/heads/layout"))
        mcp.succeed(f"test $({src_git} rev-parse layout) = {layout}")

    with subtest("kicad live board editing, one board after another"):
        # Through the project's headless KiCad (kicad-api-t): select a board, draw on it, save; then the next.
        mcp.wait_for_unit("kicad-api-t.service")
        repo = "/var/lib/kicad/t"
        for name, y in (("board_a", 20), ("board_b", 40)):
            out = session("kicad-t", [
                ["tools/call", {"name": "kicad_set_project", "arguments": {"project_dir": repo, "pcb_file": f"{repo}/{name}.kicad_pcb"}}],
                ["tools/call", {"name": "pcb_add_track", "arguments": {"x1_mm": 10, "y1_mm": y, "x2_mm": 40, "y2_mm": y}}],
                ["tools/call", {"name": "pcb_save", "arguments": {}}],
            ])
            for result in out["results"]:
                text = "\n".join(c.get("text", "") for c in result["content"])
                print(f"kicad-t {name}: {text[:300]!r}")
                assert not result.get("isError"), text
            mcp.succeed(f"grep -q '(segment' {repo}/{name}.kicad_pcb")
        # A board whose file changed on disk (a pull) is closed unsaved when the agent moves on: KiCad's older copy
        # never goes over it.
        a = f"{repo}/board_a.kicad_pcb"
        session("kicad-t", [
            ["tools/call", {"name": "kicad_set_project", "arguments": {"project_dir": repo, "pcb_file": a}}],
            ["tools/call", {"name": "pcb_add_track", "arguments": {"x1_mm": 10, "y1_mm": 60, "x2_mm": 40, "y2_mm": 60}}],
        ])
        mcp.succeed(f"cp {a} /tmp/board_a && sleep 1 && touch {a}")
        session("kicad-t", [
            ["tools/call", {"name": "kicad_set_project", "arguments": {"project_dir": repo, "pcb_file": f"{repo}/board_b.kicad_pcb"}}],
            ["tools/call", {"name": "pcb_add_track", "arguments": {"x1_mm": 10, "y1_mm": 70, "x2_mm": 40, "y2_mm": 70}}],
        ])
        mcp.succeed(f"cmp {a} /tmp/board_a")
        # Schematic to board with the standard libraries (the library tables tmpfiles links in), then DRC.
        demo = f"{repo}/demo"
        call = lambda name, args: ["tools/call", {"name": name, "arguments": args}]
        out = session("kicad-t", [
            call("kicad_create_new_project", {"path": repo, "name": "demo"}),
            call("kicad_set_project", {"project_dir": demo, "pcb_file": f"{demo}/demo.kicad_pcb", "sch_file": f"{demo}/demo.kicad_sch"}),
            call("sch_add_symbol", {"library": "Device", "symbol_name": "R", "x_mm": 50, "y_mm": 50, "reference": "R1",
                                    "value": "10k", "footprint": "Resistor_SMD:R_0603_1608Metric"}),
            # Its ERC gate would stop the sync on R1's open pins.
            call("pcb_sync_from_schematic", {"allow_open_board": True, "force": True}),
            call("pcb_place_component", {"reference": "R1", "x_mm": 20, "y_mm": 20}),
            call("pcb_save", {}),
            call("run_drc", {}),
            # With the board still open in KiCad, so its lock file is there.
            call("vcs_commit_checkpoint", {"message": "demo", "auto_drc": False}),
        ])
        for result in out["results"]:
            text = "\n".join(c.get("text", "") for c in result["content"])
            print(f"kicad-t demo: {text[:300]!r}")
            assert not result.get("isError"), text
        mcp.succeed(f"grep -q 'R_0603_1608Metric' {demo}/demo.kicad_pcb")
        # The board, schematic and project went in; KiCad's lock and view settings and the server's reports didn't.
        files = mcp.succeed(f"git -C {repo} show --name-only --format= HEAD")
        assert "demo/demo.kicad_pcb" in files and "demo/demo.kicad_sch" in files, files
        assert not any(x in files for x in (".lck", ".kicad_prl", ".kicad-mcp/", "output/")), files
        # Two parts on two nets, routed by KiCadRoutingTools on a copy of the board, in the background, then made
        # the board: DRC finds nothing unconnected.
        rt = f"{repo}/rt"
        rt_project = call("kicad_set_project", {"project_dir": rt, "pcb_file": f"{rt}/rt.kicad_pcb", "sch_file": f"{rt}/rt.kicad_sch"})
        out = session("kicad-t", [
            call("kicad_create_new_project", {"path": repo, "name": "rt"}),
            rt_project,
            *[call("sch_add_symbol", {"library": "Device", "symbol_name": "R", "x_mm": x, "y_mm": 50, "reference": r,
                                      "value": "10k", "footprint": "Resistor_SMD:R_0603_1608Metric"})
              for r, x in (("R1", 50), ("R2", 80))],
            *[call("sch_route_wire_between_pins", {"ref1": "R1", "pin1": p, "ref2": "R2", "pin2": p}) for p in ("1", "2")],
            call("pcb_sync_from_schematic", {"allow_open_board": True, "force": True}),
            call("pcb_set_board_outline", {"width_mm": 30, "height_mm": 20, "origin_x_mm": 0, "origin_y_mm": 0}),
            call("pcb_place_component", {"reference": "R1", "x_mm": 8, "y_mm": 10}),
            call("pcb_place_component", {"reference": "R2", "x_mm": 22, "y_mm": 10, "rotation_deg": 90}),
            call("route_krt_start", {"script": "autoroute.py", "args": ["rt.kicad_pcb", "routed.kicad_pcb"],
                                     "wait_seconds": 0}),
        ])
        for result in out["results"]:
            text = "\n".join(c.get("text", "") for c in result["content"])
            print(f"kicad-t rt: {text[:300]!r}")
            assert not result.get("isError"), text
        assert "Running for" in text or "Finished after" in text, text

        def krt_done(_last: bool) -> bool:
            status = session("kicad-t", [rt_project, call("route_krt_status", {})])["results"][1]
            text = "\n".join(c.get("text", "") for c in status["content"])
            print(f"kicad-t krt: {text[-600:]!r}")
            return "Finished after" in text and "exit code 0" in text

        retry(krt_done, timeout_seconds=600)
        out = session("kicad-t", [
            rt_project,
            # A check that ends within wait_seconds returns its output; copy_board=false keeps the routed board.
            call("route_krt_start", {"script": "check_connected.py", "args": ["routed.kicad_pcb"], "copy_board": False}),
            call("route_krt_apply", {"file": "routed.kicad_pcb"}),
            call("run_drc", {}),
            call("route_krt_docs", {}),
        ])
        for result in out["results"]:
            text = "\n".join(c.get("text", "") for c in result["content"])
            print(f"kicad-t rt: {text[:300]!r}")
            assert not result.get("isError"), text
        texts = ["\n".join(c.get("text", "") for c in r["content"]) for r in out["results"]]
        assert "Finished after" in texts[1], texts[1]
        assert "Unconnected items: 0" in texts[3], texts[3]
        assert "skills/plan-pcb-routing" in texts[4], texts[4]
        mcp.succeed(f"grep -q '(segment' {rt}/rt.kicad_pcb")

        # The project as a workspace: its files, a shell in it, KiCad's own API, the board as an image, and a step
        # after every call that changed a file, which can be gone back to.
        out = session("kicad-t", [
            rt_project,
            call("file_list", {"path": "rt"}),
            call("file_search", {"pattern": "\\(segment", "glob": "*.kicad_pcb", "limit": 2}),
            call("file_write", {"path": "rt/notes.md", "content": "first\n"}),
            call("file_edit", {"path": "rt/notes.md", "old": "first", "new": "second"}),
            call("file_read", {"path": "rt/notes.md"}),
            call("file_read", {"path": "../../../etc/passwd"}),
            call("file_read", {"path": ".git/config"}),
            call("shell_run", {"command": "git status --short && kicad-cli version && python3 -c 'import numpy, shapely' && test -d \"$KRT\" && echo shell-ok"}),
            call("kicad_ipc", {"command": "GetVersion"}),
            call("kicad_ipc", {"command": "GetItems", "message": {"types": ["KOT_PCB_TRACE"]}}),
            call("pcb_render_png", {"dpi": 100}),
            call("vcs_list_steps", {}),
            call("vcs_restore_step", {"step": "refs/kicad-mcp/steps~1", "paths": ["rt/notes.md"]}),
            call("file_read", {"path": "rt/notes.md"}),
            # A binary file in and out (a 1x1 PNG, read back as an image), ngspice, the render's layer sets, a
            # visual diff against the last step, and 3D.
            call("file_write", {"path": "rt/pixel.png", "encoding": "base64", "content": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="}),
            call("file_read", {"path": "rt/pixel.png"}),
            call("shell_run", {"command": "ngspice -v"}),
            call("pcb_render_png", {"layers": "copper", "each_layer": True, "dpi": 100}),
            call("pcb_render_visual_diff", {"before": "refs/kicad-mcp/steps", "dpi": 100}),
            call("pcb_render_3d", {"rotate": "-45,0,45", "width": 400, "height": 300}),
        ])
        texts = ["\n".join(c.get("text", "") for c in r["content"]) for r in out["results"]]
        for i, (result, text) in enumerate(zip(out["results"], texts)):
            print(f"kicad-t workspace: {text[:300]!r}")
            assert bool(result.get("isError")) == (i in (6, 7)), text
        assert "rt/rt.kicad_pcb" in texts[1] and "(segment" in texts[2], texts[1:3]
        assert "second" in texts[5] and "shell-ok" in texts[8] and "exit code 0" in texts[8], (texts[5], texts[8])
        assert '"major": 10' in texts[9] and "kiapi.board.types.Track" in texts[10], texts[9:11]
        assert any(c.get("type") == "image" for c in out["results"][11]["content"]), out["results"][11]
        assert "file_edit: rt/notes.md" in texts[12] and "file_write: rt/notes.md" in texts[12], texts[12]
        assert "first" in texts[14], texts[14]
        images = lambda r: sum(c.get("type") == "image" for c in r["content"])
        assert "Wrote rt/pixel.png (70 B)" in texts[15] and images(out["results"][16]) == 1, texts[15:17]
        assert "ngspice-" in texts[17], texts[17]
        assert images(out["results"][18]) == 2 and "B.Cu, Edge.Cuts" in texts[18], texts[18]
        assert images(out["results"][19]) == 1 and images(out["results"][20]) == 1, texts[19:21]
        # Steps are a ref of their own: the project's index never had notes.md.
        steps_git = f"runuser -u mcp-kicad-t -- git -C {repo}"
        mcp.succeed(f"{steps_git} rev-parse refs/kicad-mcp/steps", f"! {steps_git} ls-files --error-unmatch rt/notes.md")

        out = session("kicad-t", [
            ["tools/call", {"name": "kicad_set_project", "arguments": {"project_dir": repo, "pcb_file": f"{repo}/nope.kicad_pcb"}}],
            ["tools/call", {"name": "pcb_add_track", "arguments": {"x1_mm": 0, "y1_mm": 0, "x2_mm": 1, "y2_mm": 0}}],
        ])
        assert out["results"][1].get("isError"), out
        mcp.fail(f"test -e {repo}/nope.kicad_pcb")

    with subtest("no server opens another over loopback"):
        curl = "${pkgs.curl}/bin/curl -sS --max-time 5 -o /dev/null"
        target = f"http://127.0.0.1:{servers['kicad-t']['port']}/mcp"
        mcp.fail(f"runuser -u mcp-time -- {curl} {target}")
        mcp.fail(f"runuser -u mcp-time -- {curl} http://mcp:{servers['kicad-t']['port']}/mcp")
        # Anyone else on the VM still does (it's the router that keeps others out).
        mcp.succeed(f"{curl} {target}")

    with subtest("servers reach nothing else here, bar their own backend"):
        searx = "http://127.0.0.1:${toString nodes.mcp.homelab.mcp.searxng.port}/"
        mcp.succeed(f"runuser -u mcp-searxng -- {curl} {searx}")
        mcp.fail(f"runuser -u mcp-time -- {curl} {searx}")
        # A browser opens neither its own display's view nor the other's, nor their VNC.
        for port in [*views.values(), *(5900 + d for d in displays)]:
            mcp.fail(f"runuser -u mcp-playwright-chromium -- {curl} http://127.0.0.1:{port}/")
        # X only on the display's socket in its browser's /tmp: no abstract socket for the other browser to open.
        mcp.fail("grep -q '@/tmp/.X11-unix/' /proc/net/unix")

    if "memory" in servers:
        with subtest("memory graph in the state dir"):
            mcp.succeed("grep -q nixos-test /var/lib/mcp-memory/memory.jsonl")
  '';
}
