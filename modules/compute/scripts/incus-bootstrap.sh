# Joins the cluster through any member, or creates it on the seed, then applies the cluster-wide preseed.
# Env: SERVER_NAME, SEED, PEERS ("ip ..."), SEED_PRESEED, JOIN_PRESEED, PRESEED,
#      CERTIFICATES ("name=path ..."), JOIN_CERT, JOIN_KEY
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
    if ! INCUS_CONF=$conf incus remote add peer "https://$peer:8443" --accept-certificate --auth-type tls < /dev/null > /dev/null; then
      echo "$peer: join cert not trusted or unreachable" >&2
      continue
    fi
    INCUS_CONF=$conf incus cluster revoke-token "peer:$SERVER_NAME" > /dev/null 2>&1 || true
    if token=$(INCUS_CONF=$conf incus cluster add "peer:$SERVER_NAME" --quiet); then
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

for entry in $CERTIFICATES; do
  name=${entry%%=*}
  cert=${entry#*=}
  fingerprint=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d : | tr '[:upper:]' '[:lower:]')
  incus query "/1.0/certificates/$fingerprint" > /dev/null 2>&1 || incus config trust add-certificate "$cert" --name "$name"
done

incus admin init --preseed < "$PRESEED"
