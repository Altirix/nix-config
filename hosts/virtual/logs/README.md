# logs

VictoriaLogs on `10.100.0.11`, the lab's logs in one place. Every host ships its journal to it
(`modules/system/logs.nix`, `systemd-journal-upload`, which resumes where it stopped after an outage; the edge's
nginx access log goes to the journal as `nginx_access`), and Claude Code sends its tool calls over OpenTelemetry
([MCP usage](../../../modules/services/mcp/README.md#usage)). `rea-dynamic` ships nothing, it may not open
connections. Kept 90 days.

VictoriaLogs only listens on loopback. nginx on the VM serves `/insert/` alone on `9428` (every sender) and
`/select/` alone on `9427` (home): senders can add lines, never read them, delete them or reach VictoriaLogs'
`/internal/` endpoints, so a compromised host can't clean up after itself (it can still flood or forge its own
lines). There's no disk-usage limit on purpose, a flood can't push old days out: a full volume stops new lines
instead, watch it.

Web UI: `https://logs.peacocks.me` after Kanidm sign-in (members of `web_users`, `hosts/edge/ionos-de/logs.nix`), or
`http://10.100.0.11:9427/select/vmui` from home. Queries are [LogsQL](https://docs.victoriametrics.com/victorialogs/logsql/):

```
_HOSTNAME:ionos-de _SYSTEMD_UNIT:sshd.service                    # ssh on the edge
_HOSTNAME:auth _SYSTEMD_UNIT:kanidm.service error                  # Kanidm errors
SYSLOG_IDENTIFIER:nginx_access "/time/mcp"                         # MCP requests through the edge, with the user
_HOSTNAME:* | stats by (_HOSTNAME) count()                         # who's sending
```

## Router (MikroTik)

Senders: the edge's tunnel address, mgmt (hypervisors), home (printers, Claude Code, the UI) and every labs zone
(modules/networking/README.md), never `rea-dynamic` (`10.100.1.12`, excluded in the rule itself). At the top, ahead
of `labs: rea-dynamic opens nothing`, `labs: mcp to the internet only` (mcp's journal goes to a private address)
and `labs: only home and tunnel in`:

```routeros
/ip firewall address-list
add list=log-senders address=10.0.0.1 comment="edge"
add list=log-senders address=10.90.0.0/24 comment="mgmt"
add list=log-senders address=10.10.0.0/24 comment="home"
add list=log-senders address=10.100.0.0/16 comment="labs"

/ip firewall filter
add chain=forward action=accept connection-state=new src-address-list=log-senders src-address=!10.100.1.12 dst-address=10.100.0.11 protocol=tcp dst-port=9428 comment="labs: logs in" place-before=0
add chain=forward action=accept connection-state=new in-interface="VLAN 10 HomeNet" dst-address=10.100.0.11 protocol=tcp dst-port=9427 comment="labs: home reads logs" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.0.11 protocol=tcp dst-port=9427 comment="labs: edge reads logs" place-before=[find comment="labs: only home and tunnel in"]
```

Anyone on home can read every log (MCP calls' arguments included). Narrow `labs: home reads logs` to the
machines that need it if that's too wide.

## Set up

1. Deploy the hypervisors so they pin `10.100.0.11` (the VM has no network until then), then install the VM
   ([hosts/README.md](../../README.md#add-a-vm)). Add the router rules.
2. Give it a data volume (VictoriaLogs won't start without it):

   ```sh
   incus storage volume create ceph logs-data --type=block size=200GiB
   incus config device add logs data disk pool=ceph source=logs-data
   ssh admin@logs lsblk                                   # the new, empty disk, e.g. sdb
   ssh admin@logs 'sudo mkfs.ext4 -L logs-data /dev/sdb && sudo systemctl restart victorialogs'
   ```

3. Point an A record for `logs.peacocks.me` at the VPS, deploy `auth` (it learns the site's callback), then the
   other hosts, they start uploading. A host deployed before the VM exists keeps retrying and sends its backlog
   once it can.
