# Keeps every project in $SOURCES ("project=url=branch=push ...") in step with its upstream's branch, so what's
# committed there reaches the project's MCP server and pages, and with push, what agents commit on the VM
# (vcs_commit_checkpoint) goes back up. Nothing here overwrites work: a checkout with uncommitted changes, or that
# has diverged from its upstream, is left alone and says so. A project's first sync checks the branch out into the
# still empty repo.
set -u

for source in $SOURCES; do
  project=${source%%=*}
  rest=${source#*=}
  push=${rest##*=}
  rest=${rest%=*}
  branch=${rest##*=}
  url=${rest%=*}
  repo="$DIR/$project"

  if [ "$(git -C "$repo" remote get-url origin 2>/dev/null)" != "$url" ]; then
    git -C "$repo" remote remove origin 2>/dev/null
    git -C "$repo" remote add origin "$url"
  fi

  if ! git -C "$repo" fetch --quiet origin "$branch"; then
    echo "$project: can't fetch $branch from $url"
    continue
  fi

  if ! git -C "$repo" rev-parse --quiet --verify HEAD >/dev/null; then
    git -C "$repo" reset --quiet --hard FETCH_HEAD && echo "$project: checked out $(git -C "$repo" rev-parse --short HEAD)"
    continue
  fi

  if [ -n "$(git -C "$repo" status --porcelain)" ]; then
    echo "$project: has uncommitted changes, not updated (commit them, vcs_commit_checkpoint, or discard them)"
    continue
  fi

  local=$(git -C "$repo" rev-parse HEAD)
  upstream=$(git -C "$repo" rev-parse FETCH_HEAD)
  [ "$local" = "$upstream" ] && continue

  if git -C "$repo" merge-base --is-ancestor HEAD FETCH_HEAD; then
    git -C "$repo" merge --quiet --ff-only FETCH_HEAD &&
      echo "$project: $(git -C "$repo" rev-parse --short "$local") -> $(git -C "$repo" rev-parse --short HEAD)"
  elif git -C "$repo" merge-base --is-ancestor FETCH_HEAD HEAD; then
    if [ "$push" = true ]; then
      git -C "$repo" push --quiet origin "HEAD:$branch" && echo "$project: pushed $(git -C "$repo" rev-parse --short HEAD)"
    else
      echo "$project: has commits $url doesn't, not pushed (push = false)"
    fi
  else
    echo "$project: has diverged from $url, not updated (merge one into the other)"
  fi
done
