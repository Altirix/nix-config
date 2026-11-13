{ lib, nodes }:

# The router's names for the lab (README.md, Router): <host>.<domain> for every host on a VLAN with a domain
# (mgmt.internal), <instance>.labs.internal for every labs instance. `nix eval --raw .#router.dns` prints them, the
# script swaps the router's old ones for these.
let
  ip = address: lib.head (lib.splitString "/" address);
  hosts = lib.attrValues (lib.filterAttrs (_: n: n.config ? homelab) nodes);

  vlanNames = lib.concatMap (n: lib.concatMap (v: lib.optional (v.domain != null && v.address != null)
    { name = "${n.config.networking.hostName}.${v.domain}"; address = ip v.address; })
    (lib.attrValues (n.config.homelab.lan.vlans or { }))) hosts;

  # Every compute host carries the same list.
  compute = lib.findFirst (n: n.config.homelab ? labs && n.config.homelab.labs ? instances) null hosts;
  labsNames = lib.optionals (compute != null) (lib.mapAttrsToList
    (name: address: { name = "${name}.labs.internal"; inherit address; }) compute.config.homelab.labs.instances);
in
lib.concatLines ([
  "/ip dns static"
  "remove [find comment=nix-config]"
] ++ map (e: "add name=${e.name} address=${e.address} comment=nix-config") (vlanNames ++ labsNames))
