# logs

VictoriaLogs (`homelab.logs.collector`, `collector.nix`) on `hosts/virtual/logs` (`10.100.0.11`), the lab's logs in one place. Every host ships its journal to it
(`homelab.logs.shipTo`, `systemd-journal-upload`, which resumes where it stopped after an outage; the edge's
nginx access log goes to the journal as `nginx_access`), and Claude Code sends its tool calls over OpenTelemetry
([MCP usage](../../../modules/services/mcp/README.md#usage)). `rea` ships too, the one connection the router
lets it open (`labs: rea ships logs`): a sample running there reaches nginx's `/insert/` and nothing more, it can
forge or flood lines like any compromised sender. Kept 90 days.

VictoriaLogs only listens on loopback. nginx on the VM serves `/insert/` alone on `9428` (every sender) and
`/select/` alone on `9427` (home): senders can add lines, never read them, delete them or reach VictoriaLogs'
`/internal/` endpoints, so a compromised host can't clean up after itself (it can still flood or forge its own
lines). There's no disk-usage limit on purpose, a flood can't push old days out: a full volume stops new lines
instead, watch it.

Web UI: `https://logs.peacocks.me` after Kanidm sign-in (members of `web_users`, the `logs` site in `hosts/edge/ionos-de/services.nix`), or
`http://10.100.0.11:9427/select/vmui` from home. Queries are [LogsQL](https://docs.victoriametrics.com/victorialogs/logsql/):

```
_HOSTNAME:ionos-de _SYSTEMD_UNIT:sshd.service                    # ssh on the edge
_HOSTNAME:auth _SYSTEMD_UNIT:kanidm.service error                  # Kanidm errors
SYSLOG_IDENTIFIER:nginx_access "/time/mcp"                         # MCP requests through the edge, with the client
_HOSTNAME:* | stats by (_HOSTNAME) count()                         # who's sending
```

## Router (MikroTik)

In modules/networking/README.md (Router): `labs: logs in` (the edge, mgmt, home and labs), `labs: rea ships logs`
(ahead of `labs: rea opens nothing`), `labs: home reads logs` and `labs: edge reads logs`. Anyone on home can read every log (MCP calls' arguments
included), narrow `labs: home reads logs` to the machines that need it if that's too wide.

## Set up

1. Deploy the hypervisors so they pin `10.100.0.11` (the VM has no network until then), then install the VM
   ([hosts/README.md](../../README.md#add-a-vm)). Add the router rules.
2. Give it a data volume (VictoriaLogs won't start without it):

   ```sh
   incus storage volume create ceph logs-data --type=block size=200GiB
   incus config device add logs data disk pool=ceph source=logs-data
   ssh admin@logs.incus lsblk                                  # the new, empty disk, e.g. sdb
   ssh admin@logs.incus 'sudo mkfs.ext4 -L logs-data /dev/sdb && sudo systemctl restart victorialogs'
   ```

3. Point an A record for `logs.peacocks.me` at the VPS, deploy `auth` (it learns the site's callback), then the
   other hosts, they start uploading. A host deployed before the VM exists keeps retrying and sends its backlog
   once it can.
