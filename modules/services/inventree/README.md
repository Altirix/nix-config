# inventree

InvenTree on `hosts/virtual/inventree` (`10.100.2.12`, apps zone), at `https://inventree.peacocks.me` behind Kanidm
sign-in (the `inventree` site in `hosts/edge/ionos-de/services.nix`, members of `web_users`), next to Part-DB
(modules/services/partdb) to compare. There's no second login: the edge names the signed-in user in
`X-Forwarded-User` and InvenTree's remote login takes it. Only the edge reaches port 80, so nobody else can name a
user.

## Router (MikroTik)

`labs: edge to inventree` in modules/networking/README.md (Router).

## Set up

1. Point an A record for `inventree.peacocks.me` at the VPS. Deploy the hypervisors, install the VM
   ([hosts/README.md](../../../hosts/README.md#add-a-vm)), add the router rule.
2. Give its sign-in client a secret, then deploy `auth` (it makes the client, `ionos-de-inventree`) and `ionos-de`:

   ```sh
   openssl rand -base64 32 | tr -- '+/' '-_'
   sops secrets/sso.yaml   # ionos-de-inventree: <it>
   ```

3. Make yourself InvenTree's admin before signing in, with your Kanidm name, so the first sign-in lands on it (a
   user InvenTree makes on its own has no permissions). The password is never used, sign-in comes from the edge:

   ```sh
   ssh admin@inventree.incus sudo inventree-manage createsuperuser --username altirix --email ''
   ```

   Others who sign in get a user without permissions: give them some in its admin.

## Backups

Uploads are in `/var/lib/inventree/data/media`, the database is PostgreSQL; `inventree-manage dbbackup` and
`mediabackup` write both to `/var/lib/inventree/data/backups`.
