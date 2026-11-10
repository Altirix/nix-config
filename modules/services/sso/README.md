# sso

Kanidm, SSO for the lab, in two halves:

- `server.nix` (`homelab.sso.server`) runs Kanidm on a host, `hosts/virtual/auth` (`10.100.0.10`) at
  `auth.peacocks.me`. It serves `8443` with its own self-signed certificate (`hosts/virtual/auth/tls.pem`, its key
  in auth's secrets) and provisions
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
2. Make its certificate, a self-signed leaf for its domain good for ten years (CA:FALSE: Rust clients like the
   kanidm CLI refuse a CA certificate as a server's). The certificate is committed, the edge accepts only it; the key
   goes in auth's secrets:

   ```sh
   openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
     -subj /CN=auth.peacocks.me -addext subjectAltName=DNS:auth.peacocks.me \
     -addext basicConstraints=critical,CA:FALSE -addext keyUsage=critical,digitalSignature \
     -addext extendedKeyUsage=serverAuth -keyout key.pem -out hosts/virtual/auth/tls.pem
   sops hosts/virtual/auth/secrets.yaml   # kanidm-tls-key: | <key.pem, indented>
   rm key.pem
   ```

   To replace it, do the same and deploy `auth` and `ionos-de`. Then deploy the hypervisors so they pin
   `10.100.0.10` (the VM has no network until then), install the VM ([hosts/README.md](../../README.md#add-a-vm)) and
   add the router rule.
3. Add `oauth2-proxy-cookie-secret` (`openssl rand -base64 32 | tr -- '+/' '-_'`, a full AES-256 key) to
   ionos-de's secrets, and a secret per `sso` site to `secrets/sso.yaml`, keyed by its client (`<gateway>-<site>`).
   Kanidm sets each client's secret from it and the gateway's oauth2-proxies read the same value, so neither copies
   from the other. Only admin, auth and ionos-de can read that file: it holds nothing auth doesn't know anyway.

   ```sh
   openssl rand -base64 32 | tr -- '+/' '-_'
   sops secrets/sso.yaml   # ionos-de-logs: <it>, one per site
   ```

   Deploy `auth` and `ionos-de` (either first), ACME gets the certificate.
4. Give `idm_admin` a password of its own, kept in auth's secrets and set on every start of `kanidm.service`
   (auth doesn't build without it). Then log in with it and send yourself a one-time link to set up the person:

   ```sh
   openssl rand -base64 32
   sops hosts/virtual/auth/secrets.yaml   # kanidm-idm-admin-password: <it>
   kanidm login -H https://auth.peacocks.me -D idm_admin
   kanidm person credential create-reset-token altirix -H https://auth.peacocks.me -D idm_admin
   ```

   Change it by editing the secret and deploying `auth`. Lost it: `kanidmd recover-account -c /etc/kanidm/server.toml
   idm_admin` on the VM prints a new one, good until the next start.

   Open the link it prints and add a passkey.

5. Once MCP switches, the `mcp` client's secret (Kanidm's own) only goes into Claude's connector settings, the edge
   never needs it:

   ```sh
   kanidm system oauth2 show-basic-secret mcp -H https://auth.peacocks.me -D idm_admin
   ```

   oauth2-proxy looks its issuer up when it starts, so a new site's proxy retries until `auth` has its client.

## Sites behind sign-in

`sso` on a `homelab.web` site of the gateway (`hosts/edge/ionos-de/services.nix`) puts Kanidm sign-in in front of all
of it, for anything without its own login: no session, the browser goes to Kanidm and back. `sso = true` lets
`web_users` in, `sso = { title = "Part-DB"; groups = [ "parts_users" ]; }` names its tile and who gets in (the group is
made, add people to it). Add its client's secret to `secrets/sso.yaml` (Set up, step 3), then deploy `auth` (it makes
the site's client from the edge's config) and `ionos-de`. Only the session cookie counts
there, an MCP client's token doesn't open it, the upstream gets `X-Forwarded-User`, and the access log names the
user. Sessions are renewed every 15 minutes, so removing someone from `web_users` signs them out at the next renewal.

## People

Add one to `people` in `hosts/virtual/auth/default.nix` (groups: `web_users` for the sso sites, `mcp_users` for MCP
once it switches), deploy `auth`, and send them a reset link (step 4). Removing them deletes them on the next deploy. Their tokens stop at the latest 15 minutes later; end their
sessions at once with `kanidm person session list <name>` / `destroy`.

## Backups

Nightly to `/var/lib/kanidm/backups`, 7 kept. Restore on a fresh VM with
`kanidmd database restore -c /etc/kanidm/server.toml <file>` before the first start.
