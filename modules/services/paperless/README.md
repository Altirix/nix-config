# paperless

Paperless-ngx on `hosts/virtual/paperless` (`10.100.2.11`, apps zone): documents with OCR, tags and full-text
search, at `https://docs.peacocks.me` behind Kanidm sign-in (the `paperless` site in `hosts/edge/ionos-de/services.nix`,
members of `web_users`). There's no second login: the edge names the signed-in user in `X-Forwarded-User` and
Paperless takes it for its web UI. Only the edge reaches port 80, so nobody else can name a user. LLMs use it
through MCP (`modules/services/mcp/servers/paperless.nix`) on the token-only API port 8000, where that header is
removed.

## Router (MikroTik)

`labs: edge to paperless` (80) and `labs: mcp to paperless` (8000) on the router (Altirix/Mikrotik).

## Set up

1. Point an A record for `docs.peacocks.me` at the VPS. Deploy the hypervisors, install the VM
   ([hosts/README.md](../../../hosts/README.md#add-a-vm)), add the router rules (Altirix/Mikrotik).
2. Give its sign-in client a secret, then deploy `auth` (it makes the client, `ionos-de-paperless`) and `ionos-de`:

   ```sh
   openssl rand -base64 32 | tr -- '+/' '-_'
   sops secrets/sso.yaml   # ionos-de-paperless: <it>
   ```

3. Make yourself Paperless' admin, with your Kanidm name. Signing in makes a user without permissions, so this
   promotes it, and makes it first if you haven't signed in yet (its password is never used, sign-in comes from the
   edge):

   ```sh
   ssh admin@paperless.incus sudo paperless-manage shell -c "from django.contrib.auth.models import User; u, _ = User.objects.get_or_create(username='altirix'); u.is_superuser = u.is_staff = True; u.save()"
   ```

   Others who sign in get a user without permissions: give them some in its admin (Users & Groups).

## MCP

The MCP server (on the mcp VM) acts as a view-only `mcp` user: it sees every document, tag, correspondent, document
type, storage path, custom field and note, and can change none of them. Paperless makes that user and its group,
shares everything with the group to view (on every start and every 15 minutes, so new documents are shared too) and
sets its token from `secrets/paperless.yaml`, which the mcp VM reads as well. So the token is made once, before
either deploys:

```sh
openssl rand -hex 20
sops secrets/paperless.yaml   # paperless-mcp-token: <it>
```

It's at `https://mcp.peacocks.me/paperless/mcp` through agentgateway, where every call is logged.

## Backups

Documents and their archive versions are in `/var/lib/paperless/media`, the database is PostgreSQL. Paperless'
own export (`services.paperless.exporter`) writes both to one directory.
