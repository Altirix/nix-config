# oauth2-proxy for site $SITE (default.nix), with the arguments it's given. Its own cookie key, derived from the
# host's: a session sealed for one site doesn't open another. A site's client secret, if it has one, is a credential.
if [ "$(wc -c < "$CREDENTIALS_DIRECTORY/cookie-secret")" -lt 32 ]; then
  echo "oauth2-proxy-cookie-secret is under 32 bytes, see modules/services/sso/README.md" >&2
  exit 1
fi
{ cat "$CREDENTIALS_DIRECTORY/cookie-secret"; printf %s "$SITE"; } | openssl dgst -sha256 -binary \
  | basenc --base64url | tr -d '\n' > "$RUNTIME_DIRECTORY/cookie-secret"

client=()
if [ -e "$CREDENTIALS_DIRECTORY/client-secret" ]; then
  client=("--client-secret-file=$CREDENTIALS_DIRECTORY/client-secret")
fi
exec oauth2-proxy "$@" --cookie-secret-file="$RUNTIME_DIRECTORY/cookie-secret" "${client[@]}"
