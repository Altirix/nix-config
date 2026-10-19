# ssh ProxyCommand for `ssh incus-<instance>`, reaches the VM's sshd over vsock so it works before the VM has a network.
# A VM on another member is reached through that member's relay over the mesh, so any member works as the entry point.
# Relays over stdin/stdout, so it also works run through ssh from another machine.
# Looks everything up on every connect, the vsock id and member change when the VM is recreated or moved.
# Args: host (incus-<instance>, or <instance>.<anything> from another machine) port
#       --serve: relay side, reads the instance name from stdin and only reaches local VMs on port 22
# Env: SELF, MEMBERS ("name=address ..."), RELAY_PORT
if [ "${1:-}" = "--serve" ]; then
  serve=1
  if ! read -r -t 10 instance; then
    echo "incus-ssh-proxy: no instance name" >&2
    exit 1
  fi
  port=22
else
  serve=0
  instance=${1#incus-}
  instance=${instance%%.*}
  port=${2:-22}
fi

if [[ ! "$instance" =~ ^[a-zA-Z0-9-]+$ ]]; then
  echo "incus-ssh-proxy: invalid instance name" >&2
  exit 1
fi

info=$(incus query "/1.0/instances/$instance")
status=$(jq -r '.status' <<< "$info")
location=$(jq -r '.location' <<< "$info")
cid=$(jq -r '.config["volatile.vsock_id"] // empty' <<< "$info")

# The vsock id stays set after a VM stops.
if [ "$status" != Running ] || [ -z "$cid" ]; then
  echo "incus-ssh-proxy: $instance isn't a running VM" >&2
  exit 1
fi

if [ "$location" = "$SELF" ]; then
  exec socat - "VSOCK-CONNECT:$cid:$port"
fi

# The relay never hops again, the asking member already picked the right one.
if [ "$serve" = 1 ] || [ "$port" != 22 ]; then
  echo "incus-ssh-proxy: $instance runs on $location, only port 22 is relayed from other members" >&2
  exit 1
fi

address=""
for member in $MEMBERS; do
  if [ "${member%%=*}" = "$location" ]; then
    address=${member#*=}
  fi
done

if [ -z "$address" ]; then
  echo "incus-ssh-proxy: $instance runs on $location, which isn't a known member" >&2
  exit 1
fi

{
  printf '%s\n' "$instance"
  exec cat
} | socat - "TCP:$address:$RELAY_PORT"
