# sso

Kanidm, SSO for the lab, in two halves:

- `server.nix` (`homelab.sso.server`) runs Kanidm on a host, `hosts/virtual/auth` (`10.100.0.10`) at
  `auth.peacocks.me`. It serves `8443` with its own self-signed certificate (`kanidm-cert.service`) and provisions
  groups, people (`people`) and OAuth2 clients on every start (`kanidm.service` post-start). Credentials (passkeys,
  passwords, TOTP) are each person's own and live only in Kanidm's database.
- `gateway.nix` (`homelab.sso.gateway`) makes a host its front door, ionos-de (`hosts/edge/ionos-de/services.nix`):
  it serves the server's domain over the tunnel, accepting only the server's certificate, and runs an oauth2-proxy
  for each of that host's `sso` sites. Sites attach with `sso` like forwards attach to the WireGuard exit, the server
  makes a client for each from the gateway's config.

| Client | For | Redirect |
|---|---|---|
| `mcp` | Claude's connectors (claude.ai, the apps), confidential | `https://claude.ai/api/mcp/auth_callback` |
| `mcp-cli` | Claude Code, public (PKCE, no secret) | any `http://localhost:<port>/...` |
| `<gateway>-<site>` (`ionos-de-logs`, `ionos-de-partdb`) | that site's oauth2-proxy on the edge, browser sign-in, confidential | `https://<site>/oauth2/callback` |

Each site is a tile in Kanidm's app list (its `sso.title`, landing on the site) for the people in its
`sso.groups` (`web_users` unless it says), and only signs them in. `mcp` and `mcp-cli` only hand tokens to members
of `mcp_users`; nobody is in it until MCP switches, their tiles would lead nowhere. MCP
doesn't use `mcp` and `mcp-cli` yet, mcp.peacocks.me still takes bearer tokens; they're ready for the switch. Access tokens are ES256 JWTs (`iss`
`https://auth.peacocks.me/oauth2/openid/<client>`, `aud` the client) valid for 15 minutes; clients refresh them.
How the MCP servers check them: [modules/services/mcp/README.md](../../../modules/services/mcp/README.md#from-outside).

## Router (MikroTik)

Only the edge gets in, `labs: edge to auth` in modules/networking/README.md (Router).

## Set up

1. Point an A record for `auth.peacocks.me` at the VPS.
2. Deploy the hypervisors so they pin `10.100.0.10` (the VM has no network until then), then install the VM
   ([hosts/README.md](../../README.md#add-a-vm)). Add the router rule.
   Pin its certificate on the edge (ionos-de warns while it's missing, and then doesn't check what answers):

   ```sh
   ssh admin@incus-auth sudo cat /var/lib/kanidm-cert/chain.pem > hosts/virtual/auth/tls.pem   # on a hypervisor, commit it
   ```

   It's good for ten years. To replace it, delete `/var/lib/kanidm-cert/*.pem` on the VM, run
   `systemctl restart kanidm-cert kanidm`, copy it again and deploy ionos-de.
3. Add `oauth2-proxy-cookie-secret` (`openssl rand -base64 32 | tr -- '+/' '-_'`, a full AES-256 key) and a
   placeholder `sso-<site>-secret` for each `sso` site to ionos-de's secrets (it doesn't build without them), deploy
   `auth` then `ionos-de`, so ACME gets the certificate.
4. Give yourself a credential. `idm_admin`'s password is reset on the VM, then a one-time link sets up the person.
   Every start of `kanidm.service` (deploys, reboots) resets it again for provisioning, so recover it right
   before each admin session:

   ```sh
   ssh admin@incus-auth sudo kanidmd recover-account -c /etc/kanidm/server.toml idm_admin
   kanidm login -H https://auth.peacocks.me -D idm_admin
   kanidm person credential create-reset-token altirix -H https://auth.peacocks.me -D idm_admin
   ```

   Open the link it prints and add a passkey.

5. Replace each placeholder with its client's secret (Kanidm made it), then deploy `ionos-de` again. Once MCP
   switches, the `mcp` client's secret only goes into Claude's connector settings, the edge never needs it:

   ```sh
   kanidm system oauth2 show-basic-secret ionos-de-<site> -H https://auth.peacocks.me -D idm_admin
   sops hosts/edge/ionos-de/secrets.yaml   # sso-<site>-secret: <secret>
   ```

   Deploy `auth` before `ionos-de` whenever a client is added: oauth2-proxy looks each issuer up when it
   starts, and one that isn't there yet stays unverifiable until it restarts.

## Sites behind sign-in

`sso` on a `homelab.web` site of the gateway (`hosts/edge/ionos-de/services.nix`) puts Kanidm sign-in in front of all
of it, for anything without its own login: no session, the browser goes to Kanidm and back. `sso = true` lets
`web_users` in, `sso = { title = "Part-DB"; groups = [ "parts_users" ]; }` names its tile and who gets in (the group is
made, add people to it). Deploy `auth` first (it makes the site's client from the edge's config), add the client's
secret as `sso-<site>-secret` (Set up, step 5), then deploy `ionos-de`. Only the session cookie counts
there, an MCP client's token doesn't open it, the upstream gets `X-Forwarded-User`, and the access log names the
user. Sessions are renewed every 15 minutes, so removing someone from `web_users` signs them out at the next renewal.

## People

Add one to `people` in `hosts/virtual/auth/default.nix` (groups: `web_users` for the sso sites, `mcp_users` for MCP
once it switches), deploy `auth`, and send them a reset link (step 4). Removing them deletes them on the next deploy. Their tokens stop at the latest 15 minutes later; end their
sessions at once with `kanidm person session list <name>` / `destroy`.

## Backups

Nightly to `/var/lib/kanidm/backups`, 7 kept. Restore on a fresh VM with
`kanidmd database restore -c /etc/kanidm/server.toml <file>` before the first start.
