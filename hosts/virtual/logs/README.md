# logs

VictoriaLogs at `http://10.100.1.14:9428`, the lab's logs in one place. Every host ships its journal to it
(`modules/system/logs.nix`, `systemd-journal-upload`, which resumes where it stopped after an outage), log files
that bypass the journal are followed into it first (`homelab.logs.files`, e.g. `nginx-access` on the edge), and
Claude Code sends its tool calls over OpenTelemetry ([MCP usage](../../../modules/services/mcp/README.md#usage)).
`rea-dynamic` ships nothing, it may not open connections. Kept 90 days, or less once the volume is 85% full.

Hosts can only add lines. What's stored is only changed or removed on this VM, so a compromised host can't clean up
after itself, but it can flood or forge its own lines.

Web UI: `http://10.100.1.14:9428/select/vmui`. Queries are [LogsQL](https://docs.victoriametrics.com/victorialogs/logsql/):

```
_HOSTNAME:ionos-de _SYSTEMD_UNIT:sshd.service                    # ssh on the edge
_HOSTNAME:auth _SYSTEMD_UNIT:kanidm.service error                  # Kanidm errors
SYSLOG_IDENTIFIER:nginx-access "/time/mcp"                         # MCP requests through the edge, with the user
_HOSTNAME:* | stats by (_HOSTNAME) count()                         # who's sending
```

## Router (MikroTik)

Senders: the edge's tunnel address, mgmt (hypervisors), home (printers, Claude Code, the UI) and the labs VMs that
ship, never `rea-dynamic` (`10.100.1.12`). At the top, ahead of `labs: mcp to the internet only` (mcp's journal
goes to a private address) and `labs: only home and tunnel in`:

```routeros
/ip firewall address-list
add list=log-senders address=10.0.0.1 comment="edge"
add list=log-senders address=10.90.0.0/24 comment="mgmt"
add list=log-senders address=10.10.0.0/24 comment="home"
add list=log-senders address=10.100.1.10-10.100.1.11 comment="partdb, mcp"
add list=log-senders address=10.100.1.13 comment="auth"

/ip firewall filter
add chain=forward action=accept connection-state=new src-address-list=log-senders dst-address=10.100.1.14 protocol=tcp dst-port=9428 comment="labs: logs in" place-before=0
```

The same port serves queries, so anyone on home can read every log (MCP calls' arguments included). Narrow
`home` to the machines that need it if that's too wide.

## Set up

1. Install the VM ([hosts/README.md](../../README.md#add-a-vm)), deploy it, then the hypervisors so they pin
   `10.100.1.14`. Add the router rules.
2. Give it a data volume (VictoriaLogs won't start without it):

   ```sh
   incus storage volume create ceph logs-data --type=block size=200GiB
   incus config device add logs data disk pool=ceph source=logs-data
   ssh admin@logs lsblk                                   # the new, empty disk, e.g. sdb
   ssh admin@logs 'sudo mkfs.ext4 -L logs-data /dev/sdb && sudo systemctl restart victorialogs'
   ```

3. Deploy the other hosts, they start uploading. A host deployed before the VM exists keeps retrying and sends
   its backlog once it can.
