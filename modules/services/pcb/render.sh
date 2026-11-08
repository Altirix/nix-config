# Renders every project in $PROJECTS whose KiCad files changed since its last render into $WWW/<project>, and
# writes $WWW/index.html. Each renders from a copy: KiCad writes its local settings (.kicad_prl) next to what it
# opens, and an agent's save mid-render doesn't land in a half-read board. A project without a board or schematic
# yet gets a placeholder. Steps that fail are logged and skipped, the rest still renders.
set -u

step() {
  "$@" >>"$log" 2>&1 || echo "failed: $*" >>"$log"
}

index="$WWW/index.html.new"
echo '<!doctype html><meta charset=utf-8><title>PCB projects</title><h1>PCB projects</h1><ul>' >"$index"

for project in $PROJECTS; do
  src="$DIR/$project"
  out="$WWW/$project"
  mkdir -p "$out"
  echo "<li><a href=\"$project/\">$project</a></li>" >>"$index"

  stamp=$(find "$src" -path "$src/.git" -prune -o -type f -name '*.kicad_*' ! -name '*.kicad_prl' -printf '%T@ %p\n' |
    sort | sha256sum)
  if [ "$stamp" = "$(cat "$out/.stamp" 2>/dev/null)" ]; then
    continue
  fi

  log="$out/render.log"
  : >"$log"
  work=$(mktemp -d)
  (cd "$src" && find . -path ./.git -prune -o -type f -print0 | cpio -0 -pdm --quiet "$work")
  pro=$(find "$work" -name '*.kicad_pro' -print | head -n 1)
  base=${pro%.kicad_pro}
  page="$out/index.html.new"
  echo "<!doctype html><meta charset=utf-8><title>$project</title><h1>$project</h1>" >"$page"

  if [ -n "$pro" ] && [ -e "$base.kicad_sch" ]; then
    step kicad-cli sch export pdf -o "$out/schematic.pdf" "$base.kicad_sch"
    rm -rf "$out/schematic"
    step kicad-cli sch export svg -o "$out/schematic" "$base.kicad_sch"
    echo '<h2>Schematic</h2><p><a href="schematic.pdf">PDF</a></p>' >>"$page"
    for svg in "$out"/schematic/*.svg; do
      [ -e "$svg" ] && echo "<p><img src=\"schematic/$(basename "$svg")\" style=\"max-width:100%\"></p>" >>"$page"
    done
  fi

  if [ -n "$pro" ] && [ -e "$base.kicad_pcb" ]; then
    pcb="$base.kicad_pcb"
    step kicad-cli pcb export svg --mode-single --exclude-drawing-sheet --page-size-mode 2 \
      -l F.Cu,F.SilkS,F.Mask,Edge.Cuts -o "$out/front.svg" "$pcb"
    step kicad-cli pcb export svg --mode-single --exclude-drawing-sheet --page-size-mode 2 --mirror \
      -l B.Cu,B.SilkS,B.Mask,Edge.Cuts -o "$out/back.svg" "$pcb"
    step kicad-cli pcb render --side top -w 1600 -h 1000 -o "$out/top.png" "$pcb"
    step kicad-cli pcb render --side bottom -w 1600 -h 1000 -o "$out/bottom.png" "$pcb"
    # Its generator is a wx app, it wants a display even without a window.
    step xvfb-run -a generate_interactive_bom --no-browser --dest-dir "$out" --name-format ibom "$pcb"
    {
      echo '<h2>Board</h2><p><a href="ibom.html">Interactive BOM</a></p>'
      echo '<p><img src="top.png" style="max-width:49%"> <img src="bottom.png" style="max-width:49%"></p>'
      echo '<p><img src="front.svg" style="max-width:49%;background:#fff"> <img src="back.svg" style="max-width:49%;background:#fff"></p>'
    } >>"$page"
  fi

  [ -z "$pro" ] && echo '<p>No KiCad project here yet, push one.</p>' >>"$page"
  echo '<p><a href="render.log">Render log</a></p>' >>"$page"
  mv "$page" "$out/index.html"
  echo "$stamp" >"$out/.stamp"
  rm -rf "$work"
done

echo '</ul>' >>"$index"
mv "$index" "$WWW/index.html"
