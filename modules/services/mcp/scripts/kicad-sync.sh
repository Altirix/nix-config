# Keeps a KiCad project in step with its source's $BRANCH, run in its repository (servers/kicad.nix). An empty repo
# takes the source's first.
git fetch --quiet origin "$BRANCH"
git rev-parse --quiet --verify HEAD >/dev/null || git reset --quiet --hard FETCH_HEAD

# Only on $BRANCH, the one git-sync is set up for.
[ "$(git symbolic-ref --short HEAD)" = "$BRANCH" ] || git checkout --quiet "$BRANCH"

# A repo that was a project of its own before it had a source shares no history with it: rebasing would replay all of
# it onto the source. Move it aside (or reset it to the source) by hand.
git merge-base HEAD FETCH_HEAD >/dev/null || {
  echo "no history in common with origin/$BRANCH: move $(pwd) aside or reset it to the source" >&2
  exit 1
}

# Pull-only sources fast-forward, never overwriting local commits or changes.
if [ "$PUSH" != true ]; then
  exec git merge --quiet --ff-only FETCH_HEAD
fi

# On a conflict git-sync stops mid-rebase, with markers in the files agents edit: undo it, so the project keeps its
# own commits and the next run tries again (its log says what conflicts).
git-sync || {
  status=$?
  git rebase --abort 2>/dev/null || true
  exit "$status"
}
