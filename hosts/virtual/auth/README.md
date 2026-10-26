# auth

Kanidm at `https://auth.peacocks.me`, SSO for the lab. The VM (`10.100.1.13`) serves it on `8443` with its own
self-signed certificate (`kanidm-cert.service`), ionos-de terminates TLS for the name and proxies over the tunnel
(`hosts/edge/ionos-de/auth.nix`). Groups, persons and OAuth2 clients are provisioned from `default.nix` on every
deploy (`kanidm.service` post-start), credentials (passkeys, passwords, TOTP) are each person's own and live only in
Kanidm's database.

| Client | For | Redirect |
|---|---|---|
| `mcp` | Claude's connectors (claude.ai, the apps), confidential | `https://claude.ai/api/mcp/auth_callback` |
| `mcp-cli` | Claude Code, public (PKCE, no secret) | any `http://localhost:<port>/...` |

Both only hand tokens to members of `mcp_users`. Access tokens are ES256 JWTs (`iss`
`https://auth.peacocks.me/oauth2/openid/<client>`, `aud` the client) valid for 15 minutes; clients refresh them.
How the MCP servers check them: [modules/services/mcp/README.md](../../../modules/services/mcp/README.md#from-outside).

## Router (MikroTik)

Only the edge gets in, before `labs: only home and tunnel in`:

```routeros
/ip firewall filter
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.1.13 protocol=tcp dst-port=8443 comment="labs: edge to auth" place-before=[find comment="labs: only home and tunnel in"]
```

## Set up

1. Point an A record for `auth.peacocks.me` at the VPS.
2. Install the VM ([hosts/README.md](../../README.md#add-a-vm)), deploy it, then the hypervisors so they pin
   `10.100.1.13`. Add the router rule.
3. Deploy `ionos-de` with `auth.nix` only (comment out `mcp.nix` until step 5), so ACME gets the certificate.
4. Give yourself a credential. `idm_admin`'s password is reset on the VM, then a one-time link sets up the person.
   Every start of `kanidm.service` (deploys, reboots) resets it again for provisioning, so recover it right
   before each admin session:

   ```sh
   ssh admin@auth sudo kanidmd recover-account -c /etc/kanidm/server.toml idm_admin
   kanidm login -H https://auth.peacocks.me -D idm_admin
   kanidm person credential create-reset-token altirix -H https://auth.peacocks.me -D idm_admin
   ```

   Open the link it prints and add a passkey.

5. Copy the `mcp` client's secret (Kanidm made it) into ionos-de's secrets alongside a cookie secret, then
   deploy `ionos-de` with `mcp.nix`:

   ```sh
   kanidm system oauth2 show-basic-secret mcp -H https://auth.peacocks.me -D idm_admin
   sops hosts/edge/ionos-de/secrets.yaml   # kanidm-mcp-secret: <secret>, oauth2-proxy-cookie-secret: <openssl rand -hex 16>
   ```

   Deploy `auth` before `ionos-de` whenever a client is added: oauth2-proxy looks each issuer up when it
   starts, and one that isn't there yet stays unverifiable until it restarts.

## People

Add one in `default.nix` (`persons.<name>`, groups), deploy, and send them a reset link (step 4). Removing them
from `default.nix` deletes them on the next deploy. Their tokens stop at the latest 15 minutes later; end their
sessions at once with `kanidm person session list <name>` / `destroy`.

## Backups

Nightly to `/var/lib/kanidm/backups`, 7 kept. Restore on a fresh VM with
`kanidmd database restore -c /etc/kanidm/server.toml <file>` before the first start.
