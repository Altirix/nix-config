# partdb

Part-DB on `hosts/virtual/partdb` (`10.100.2.10`, apps zone), at `https://parts.peacocks.me` behind Kanidm sign-in
(the `partdb` site in `hosts/edge/ionos-de/services.nix`, members of `web_users`), then Part-DB's own login.

## Router (MikroTik)

Only the edge gets in, before `labs: only home and tunnel in`. From home use the site too:

```routeros
/ip firewall filter
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.2.10 protocol=tcp dst-port=80 comment="labs: edge to partdb" place-before=[find comment="labs: only home and tunnel in"]
```

## Logged in only

Logged out, Part-DB acts as its built-in `anonymous` user, which a fresh install lets read everything. Disabling that
user changes nothing in 2.4, and its permissions live in Part-DB's database, so taking them away is a one-time step
in its UI: as an admin, open the users admin, edit `anonymous`, take it out of every group and set every permission
to Forbid. Check from a private window that the site only offers the login.
