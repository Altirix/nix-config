# paperless

Paperless-ngx on `hosts/virtual/paperless` (`10.100.2.11`, apps zone): documents with OCR, tags and full-text
search, at `https://docs.peacocks.me` behind Kanidm sign-in (the `paperless` site in `hosts/edge/ionos-de/services.nix`,
members of `web_users`). There's no second login: the edge names the signed-in user in `X-Forwarded-User` and
Paperless takes it for its web UI. Only the edge reaches port 80, so nobody else can name a user. LLMs use it
through MCP (`modules/services/mcp/servers/paperless.nix`) on the token-only API port 8000, where that header is
removed.

## Router (MikroTik)

`labs: edge to paperless` (80) and `labs: mcp to paperless` (8000) in modules/networking/README.md (Router).

## Set up

1. Point an A record for `docs.peacocks.me` at the VPS. Deploy the hypervisors, install the VM
   ([hosts/README.md](../../../hosts/README.md#add-a-vm)), add the router rules.
2. Deploy `auth` (it makes the site's client, `ionos-de-paperless`), add its secret to ionos-de's secrets and
   deploy `ionos-de`:

   ```sh
   kanidm system oauth2 show-basic-secret ionos-de-paperless -D idm_admin
   sops hosts/edge/ionos-de/secrets.yaml   # sso-paperless-secret: <secret>
   ```

3. Make yourself Paperless' admin before signing in, with your Kanidm name, so the first sign-in lands on it (a
   user Paperless makes on its own has no permissions). The password is never used, sign-in comes from the edge:

   ```sh
   ssh admin@incus-paperless sudo paperless-manage createsuperuser --username altirix --email ''
   ```

   Others who sign in get a user without permissions: give them some in its admin (Users & Groups).

## MCP

The server can list, read, upload, edit and delete. What it may do is the permissions of the Paperless user its
token belongs to, so give it one of its own: in Users & Groups, add `mcp` with View on documents, tags,
correspondents, document types, custom fields and notes (add Add on documents if LLMs should file uploads). Give
it a token in Paperless' Django admin, `https://docs.peacocks.me/admin/` (Auth Token, Tokens, Add, user `mcp`), and
put it in the mcp VM's secrets:

```sh
sops hosts/virtual/mcp/secrets.yaml   # paperless-mcp-token: <token>
```

Uncomment `paperless` in `hosts/virtual/mcp/default.nix` and deploy `mcp`; it's at
`https://mcp.peacocks.me/paperless/mcp` through agentgateway, where every call is logged.

## Backups

Documents and their archive versions are in `/var/lib/paperless/media`, the database is PostgreSQL. Paperless'
own export (`services.paperless.exporter`) writes both to one directory.
