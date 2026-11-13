# Keeps a KiCad project in step with its source's $BRANCH, run in its repository (servers/kicad.nix). One fetch a run
# once set up, git-sync's own: the checks below use origin/$BRANCH as the last run left it.
if ! git rev-parse --quiet --verify "refs/remotes/origin/$BRANCH" >/dev/null; then
  status=0
  git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null || status=$?
  # An empty source (a new repo) takes the project's commits, if there are any and it may push.
  if [ "$status" = 2 ]; then
    if [ "$PUSH" = true ] && git rev-parse --quiet --verify HEAD >/dev/null; then
      exec git push --quiet origin "HEAD:refs/heads/$BRANCH"
    fi
    exit 0
  fi
  [ "$status" = 0 ] || exit "$status"
  git fetch --quiet origin "$BRANCH"
fi

# An empty repo takes the source's branch. checkout refuses to overwrite files an agent left uncommitted, where reset
# would take them.
git rev-parse --quiet --verify HEAD >/dev/null || git checkout --quiet -B "$BRANCH" "origin/$BRANCH"

# Only on $BRANCH, the one git-sync is set up for.
[ "$(git symbolic-ref --short HEAD)" = "$BRANCH" ] || git checkout --quiet "$BRANCH"

# A repo that was a project of its own before it had a source shares no history with it: rebasing would replay all of
# it onto the source. Move it aside (or reset it to the source) by hand.
git merge-base HEAD "origin/$BRANCH" >/dev/null || {
  echo "no history in common with origin/$BRANCH: move $(pwd) aside or reset it to the source" >&2
  exit 1
}

# Pull-only sources fast-forward, never overwriting local commits or changes.
if [ "$PUSH" != true ]; then
  git fetch --quiet origin "$BRANCH"
  exec git merge --quiet --ff-only "origin/$BRANCH"
fi

# On a conflict git-sync stops mid-rebase, with markers in the files agents edit: undo it, so the project keeps its
# own commits and the next run tries again (its log says what conflicts).
git-sync || {
  status=$?
  git rebase --abort 2>/dev/null || true
  exit "$status"
}
