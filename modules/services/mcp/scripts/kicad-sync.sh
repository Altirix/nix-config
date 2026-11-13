# git-sync for a KiCad project, run in its repository (servers/kicad.nix). It needs a branch to sync: an empty repo
# takes the source's $BRANCH first.
git rev-parse --quiet --verify HEAD >/dev/null || {
  git fetch --quiet origin "$BRANCH"
  git reset --quiet --hard FETCH_HEAD
}

# On a conflict git-sync stops mid-rebase, with markers in the files agents edit: undo it, so the project keeps its
# own commits and the next run tries again (its log says what conflicts).
git-sync || {
  status=$?
  git rebase --abort 2>/dev/null || true
  exit "$status"
}
