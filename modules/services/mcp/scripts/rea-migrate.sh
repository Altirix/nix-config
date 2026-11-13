# Once per project (rea.nix): what it made as the one shared rea user before it had a user of its own becomes its
# own. The marker is root's, in a directory only root writes. chown -R doesn't follow symlinks samples may plant.
for p in "$@"; do
  dir=/var/lib/rea/$p
  [ -e "$dir/.owned" ] && continue
  for sub in scratch home; do
    [ -d "$dir/$sub" ] && chown -R "rea-$p:rea-$p" "$dir/$sub"
  done
  # nginx (the group) serves it.
  [ -d "$dir/shared" ] && chown -R "rea-$p:nginx" "$dir/shared"
  touch "$dir/.owned"
done
