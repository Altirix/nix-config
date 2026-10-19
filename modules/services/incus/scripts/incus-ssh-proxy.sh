# ssh ProxyCommand for `ssh incus-<instance>`, reaches the VM's sshd over vsock so it works before the VM has a network.
# Relays over stdin/stdout, so it also works run through ssh from another machine.
# Looks the vsock id up on every connect, it changes when the VM is recreated.
# Args: host (incus-<instance>, or <instance>.<anything> from another machine) port
# Env: SELF
instance=${1#incus-}
instance=${instance%%.*}
port=${2:-22}

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

# vsock only reaches VMs on this member.
if [ "$location" != "$SELF" ]; then
  echo "incus-ssh-proxy: $instance runs on $location, ssh from there" >&2
  exit 1
fi

exec socat - "VSOCK-CONNECT:$cid:$port"
