# inventree

InvenTree on `hosts/virtual/inventree` (`10.100.2.12`, apps zone), at `https://inventree.peacocks.me` behind Kanidm
sign-in (the `inventree` site in `hosts/edge/ionos-de/services.nix`, members of `web_users`), next to Part-DB
(modules/services/partdb) to compare. There's no second login: the edge names the signed-in user in
`X-Forwarded-User` and InvenTree's remote login takes it. Only the edge reaches port 80, so nobody else can name a
user.

## Router (MikroTik)

`labs: edge to inventree` on the router (Altirix/Mikrotik).

## Set up

1. Point an A record for `inventree.peacocks.me` at the VPS. Deploy the hypervisors, install the VM
   ([hosts/README.md](../../../hosts/README.md#add-a-vm)), add the router rule (Altirix/Mikrotik).
2. Give its sign-in client a secret, then deploy `auth` (it makes the client, `ionos-de-inventree`) and `ionos-de`:

   ```sh
   openssl rand -base64 32 | tr -- '+/' '-_'
   sops secrets/sso.yaml   # ionos-de-inventree: <it>
   ```

3. Make yourself InvenTree's admin, with your Kanidm name. Signing in makes a user without permissions, so this
   promotes it, and makes it first if you haven't signed in yet (its password is never used, sign-in comes from the
   edge):

   ```sh
   ssh admin@inventree.incus sudo inventree-manage shell -c "from django.contrib.auth.models import User; u, _ = User.objects.get_or_create(username='altirix'); u.is_superuser = u.is_staff = True; u.save()"
   ```

   Others who sign in get a user without permissions: give them some in its admin.

## Backups

Uploads are in `/var/lib/inventree/data/media`, the database is PostgreSQL; `inventree-manage dbbackup` and
`mediabackup` write both to `/var/lib/inventree/data/backups`.
