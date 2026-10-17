# Joins the cluster through any member, or creates it on the seed, then applies the cluster-wide preseed.
# Env: SERVER_NAME, SEED, PEERS ("ip ..."), SEED_PRESEED, JOIN_PRESEED, PRESEED,
#      CERTIFICATES ("name=path ..."), RESTRICTED_CERTIFICATES ("name=project,...=path ..."), JOIN_CERT, JOIN_KEY,
#      INSTANCE_PROFILES ("instance=profile,... ..."), WINDOWS_UNATTEND ("pool volume iso", or empty)
incus admin waitready --timeout 60

if ! incus cluster list > /dev/null 2>&1; then
  # Separate client config so the join cert never touches root's incus remotes.
  conf=$(mktemp -d)
  trap 'rm -rf "$conf"' EXIT
  install -m 0600 "$JOIN_CERT" "$conf/client.crt"
  install -m 0600 "$JOIN_KEY" "$conf/client.key"

  # The seed tries peers first too, so a reinstalled seed rejoins instead of forking a second cluster.
  token=""
  for peer in $PEERS; do
    INCUS_CONF=$conf incus remote add peer "https://$peer:8443" --accept-certificate --auth-type tls < /dev/null > /dev/null 2>&1 || continue
    INCUS_CONF=$conf incus cluster revoke-token "peer:$SERVER_NAME" > /dev/null 2>&1 || true
    if token=$(INCUS_CONF=$conf incus cluster add "peer:$SERVER_NAME" --quiet 2> /dev/null); then
      break
    fi
    token=""
    INCUS_CONF=$conf incus remote remove peer
  done

  if [[ -n $token ]]; then
    jq --arg token "$token" '.cluster.cluster_token = $token' "$JOIN_PRESEED" | incus admin init --preseed
  elif [[ $SERVER_NAME == "$SEED" ]]; then
    incus admin init --preseed < "$SEED_PRESEED"
  else
    echo "no cluster member handed out a join token yet" >&2
    exit 1
  fi
fi

fingerprint() {
  openssl x509 -in "$1" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d : | tr '[:upper:]' '[:lower:]'
}

for entry in $CERTIFICATES; do
  name=${entry%%=*}
  cert=${entry#*=}
  incus query "/1.0/certificates/$(fingerprint "$cert")" > /dev/null 2>&1 || incus config trust add-certificate "$cert" --name "$name"
done

incus admin init --preseed < "$PRESEED"

# Added after the preseed so the profiles exist. Instances that don't exist yet get them on a later start.
profiles_of() {
  incus query "/1.0/instances/$1" 2> /dev/null | jq -r '.profiles | join(" ")'
}
for entry in $INSTANCE_PROFILES; do
  instance=${entry%%=*}
  profiles=${entry#*=}
  current=$(profiles_of "$instance") || continue
  for profile in ${profiles//,/ }; do
    # Every member runs this, another may have added it in the meantime.
    [[ " $current " == *" $profile "* ]] || incus profile add "$instance" "$profile" \
      || [[ " $(profiles_of "$instance") " == *" $profile "* ]]
  done
done

# Attached per VM for the install only, so the preseed never points at it. The description says which build it is,
# ISO volumes refuse any config change, user.* included. A changed one is replaced unless a VM mid-install still has
# it attached, then the next start does. Every member runs this, one losing a race fails and retries.
if [[ -n $WINDOWS_UNATTEND ]]; then
  read -r pool volume iso <<< "$WINDOWS_UNATTEND"
  current=$(incus storage volume get -p "$pool" "custom/$volume" description 2> /dev/null) || current=missing
  if [[ $current != "$iso" ]]; then
    if [[ $current == missing ]] || incus storage volume delete "$pool" "custom/$volume"; then
      incus storage volume import "$pool" "$iso" "$volume" --type=iso
      incus storage volume set -p "$pool" "custom/$volume" description="$iso"
    fi
  fi
fi

# After the preseed, so they are only ever authorized the way its config says.
for entry in $RESTRICTED_CERTIFICATES; do
  name=${entry%%=*}
  rest=${entry#*=}
  projects=${rest%%=*}
  cert=${rest#*=}
  if existing=$(incus query "/1.0/certificates/$(fingerprint "$cert")" 2> /dev/null); then
    jq -e .restricted <<< "$existing" > /dev/null || echo "warning: $name is already trusted unrestricted, left as is" >&2
  else
    incus config trust add-certificate "$cert" --name "$name" --restricted --projects "$projects"
  fi
done
