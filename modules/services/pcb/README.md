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
Each is an empty repo you push to; a push updates its checkout (`receive.denyCurrentBranch=updateInstead`), so
agents and the pages see it at once:

```sh
git remote add pcb admin@pcb.labs.internal:/var/lib/pcb/<project>
git push pcb main
```

What agents changed is in that checkout, uncommitted: look at it with `ssh admin@pcb.labs.internal git -C
/var/lib/pcb/<project> status`, commit it there and pull. A push refuses to land on uncommitted changes, so pull or
commit theirs first.

## Router (MikroTik)

`labs: edge to pcb` (80, the pages, and 8200-8299, a server per project) in modules/networking/README.md (Router).
ssh from home for git is `labs: home ssh, rdp`.

## Set up

1. Point an A record for `pcb.peacocks.me` at the VPS. Deploy the hypervisors, install the VM
   ([hosts/README.md](../../../hosts/README.md#add-a-vm)), add the router rule.
2. Deploy `auth` (it makes the site's client, `ionos-de-pcb`), add its secret to ionos-de's secrets and deploy
   `ionos-de`:

   ```sh
   kanidm system oauth2 show-basic-secret ionos-de-pcb -D idm_admin
   sops hosts/edge/ionos-de/secrets.yaml   # sso-pcb-secret: <secret>
   ```
