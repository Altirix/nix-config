# pcb

KiCad projects on `hosts/virtual/pcb` (`10.100.1.13`, agents zone), for you and for agents.

- **You**: edit in KiCad on your PC (or Windows-11), with each project a git repo on the VM. The pages at
  `https://pcb.peacocks.me` (Kanidm sign-in, members of `web_users`) show every project as it is on the VM: the
  schematic (PDF, SVG), both sides of the board (SVG, 3D render) and an interactive BOM, re-rendered within two
  minutes of a change.
- **Agents**: each project has its own KiCad MCP Pro server at `https://mcp.peacocks.me/kicad/<project>/mcp` (bearer
  tokens and agentgateway's call log like every MCP server, modules/services/mcp/README.md), confined to that
  project. Agents on different projects never share a server or files; agents on the same project share both, so
  give each line of work its own project. Headless: ERC/DRC, DFM, BOM and exports run through `kicad-cli`, tools
  that drive a running KiCad are hidden. `mode` is `write` (they edit schematics and boards), `readonly` keeps them
  to inspecting, checking and exporting. Its outputs still need your review before fabrication.

Add a project to `projects` in `hosts/virtual/pcb/default.nix` and deploy `pcb` (and `ionos-de`, for its MCP route).

## Where the files come from

A project can follow the repo you commit it to (`sources`): the VM fetches it every minute and fast-forwards its
checkout, so a push there reaches the MCP server and the pages within a minute. With `push`, what agents commit on
the VM goes back up the same way:

```nix
sources.palmremote = { url = "git@github.com:you/palmremote.git"; push = true; };
deployKey = true;
```

An ssh source needs a deploy key: make one, add its public half to the repo on GitHub (Settings, Deploy keys, with
write access for `push`) and its private half to the pcb VM's secrets (a public https source needs neither):

```sh
ssh-keygen -t ed25519 -N '' -C pcb -f pcb-deploy-key
sops hosts/virtual/pcb/secrets.yaml   # pcb-deploy-key: | <pcb-deploy-key, indented>
```

Nothing is overwritten: a checkout with uncommitted changes, or one that has diverged from its source, is left alone
and the sync says why (`journalctl -u pcb-sync`). A project without a source is a repo you push to directly over ssh
(`git push admin@pcb.labs.internal:/var/lib/pcb/<project> main`), its checkout follows the push
(`receive.denyCurrentBranch=updateInstead`).

## What agents can do

In `write` mode the servers run KiCad MCP Pro's `builder` tool set: `kicad_create_new_project` starts a design in
the project (a subfolder for each board if it holds several), `sch_*` and `pcb_*` edit schematics and boards, the
validation tools run ERC and DRC, and `vcs_commit_checkpoint` commits the result, which `push` sends to the source.
Leave an agent's edits committed or discarded: uncommitted, they hold the sync back.

## Router (MikroTik)

`labs: edge to pcb` (80, the pages, and 8200-8299, a server per project) in modules/networking/README.md (Router).
ssh from home for git is `labs: home ssh, rdp`.

## Set up

1. Point an A record for `pcb.peacocks.me` at the VPS. Deploy the hypervisors, install the VM
   ([hosts/README.md](../../../hosts/README.md#add-a-vm)), add the router rule.
2. Give its sign-in client a secret, then deploy `auth` (it makes the client, `ionos-de-pcb`) and `ionos-de`:

   ```sh
   openssl rand -base64 32 | tr -- '+/' '-_'
   sops secrets/sso.yaml   # ionos-de-pcb: <it>
   ```
