# pre-receive of a KiCad project's push gate (servers/kicad.nix): every branch an agent pushes goes on to the
# project's source ($KICAD_SOURCE), never forced, before the gate takes it. The gate itself already refused force
# updates and deletions (receive.denyNonFastForwards, receive.denyDeletes); this refuses the protected branches
# ($KICAD_PROTECTED, space-separated: they change only by your merges), deleting by any other way and anything but
# branches. If the source refuses, so does the gate, with the source's reason.
zero=0000000000000000000000000000000000000000
while read -r _ new ref; do
  case "$ref" in
    refs/heads/*) ;;
    *) echo "only branches can be pushed, not $ref" >&2; exit 1 ;;
  esac
  for protected in $KICAD_PROTECTED; do
    if [ "$ref" = "refs/heads/$protected" ]; then
      echo "$protected is protected: push a branch of your own (vcs_branch create=true), it gets merged on GitHub" >&2
      exit 1
    fi
  done
  if [ "$new" = "$zero" ]; then
    echo "deleting ${ref#refs/heads/} isn't allowed" >&2
    exit 1
  fi
  git push --quiet "$KICAD_SOURCE" "$new:$ref" || exit 1
done
