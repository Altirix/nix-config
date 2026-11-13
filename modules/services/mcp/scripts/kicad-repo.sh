# A KiCad project's repository at $REPO (servers/kicad.nix): pushes land in it directly (its checkout follows),
# shared by the kicad group, its hooks the store's ($HOOKS). With $URL, set up for git-sync to keep $BRANCH in step with it. git-sync then refuses
# rather than committing uncommitted changes itself, so an agent's half-done edits never go up.
[ -e "$REPO/.git" ] || git init -q -b "${BRANCH:-main}" --shared=group "$REPO"
git -C "$REPO" config receive.denyCurrentBranch updateInstead
git -C "$REPO" config core.hooksPath "$HOOKS"

if [ -n "${URL:-}" ]; then
  git -C "$REPO" remote get-url origin >/dev/null 2>&1 || git -C "$REPO" remote add origin "$URL"
  git -C "$REPO" remote set-url origin "$URL"
  git -C "$REPO" config "branch.$BRANCH.remote" origin
  git -C "$REPO" config "branch.$BRANCH.merge" "refs/heads/$BRANCH"
  git -C "$REPO" config "branch.$BRANCH.sync" true
  git -C "$REPO" config "branch.$BRANCH.autocommitscript" \
    'echo "uncommitted changes: commit them (vcs_commit_checkpoint) or discard them"; exit 1'
fi

chgrp -R kicad "$REPO/.git"
