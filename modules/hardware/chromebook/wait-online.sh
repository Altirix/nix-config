# Run before chromebook-mark-good: a kernel that boots without a usable network is
# not confirmed, so the next reset falls back. Waits for a default route.
timeout=${1:-120}
for (( i = 0; i < timeout; i++ )); do
  if [[ -n $(ip route show default) || -n $(ip -6 route show default) ]]; then
    exit 0
  fi
  sleep 1
done
echo "No default route after ${timeout}s, not confirming this boot" >&2
exit 1
