# home-assistant

Home Assistant on `hosts/virtual/hass` (`10.100.2.11`, apps zone), at `https://ha.peacocks.me` behind Kanidm sign-in
(the `hass` site in `hosts/edge/ionos-de/services.nix`, members of `web_users`), then Home Assistant's own login.
The sign-in in front only takes a browser session, so from outside nothing using Home Assistant's own tokens gets
through: no companion apps, long-lived access tokens or webhooks (`/api/...`), only browsers.

## Router (MikroTik)

Only the edge gets in, before `labs: only home and tunnel in`. From home use the site too:

```routeros
/ip firewall filter
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.2.11 protocol=tcp dst-port=8123 comment="labs: edge to hass" place-before=[find comment="labs: only home and tunnel in"]
```

## Set up

1. Point an A record for `ha.peacocks.me` at the VPS.
2. Install the VM ([hosts/README.md](../../../hosts/README.md#add-a-vm)), add the router rule, deploy the edge,
   then auth (it learns the site's sign-in callback from the edge's config).
3. Open the site, create the owner account (the first to get there takes it).

## Octopus Energy tariff comparison

The integration (BottlecapDave's, `customComponents`) reads the smart meter's half-hourly consumption from
Octopus's API (api.oegb-kraken.energy, api.backend.octopus.energy), out through the tunnel like the rest of labs.

1. Settings, Devices & services, Add integration, Octopus Energy, Account: the API key and account number from
   octopus.energy/dashboard/new/accounts/personal-details/api-access.
2. Add integration, Octopus Energy again, Tariff Comparison, once per tariff to compare: the meter, the product
   code (`code` in api.oegb-kraken.energy/v1/products/, e.g. Agile's `AGILE-24-10-01`) and the tariff code for
   your region (`code` under the product's URL, e.g. `E-1R-AGILE-24-10-01-A`, the letter at the end of your current
   tariff's). Each gives a `..._previous_accumulative_cost_<name>` sensor, the same consumption priced on that tariff.
3. Put those and the current tariff's `..._previous_accumulative_cost` on a dashboard (statistics graph, daily).

Readings arrive a day or so late, so the comparison is for yesterday and before, never today.
