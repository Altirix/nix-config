# The pinned kernel ships every Tomato DTB the board module packs, and the
# early storage/USB/display modules resolve against it.
test -s "$earlyModules/lib/modules/$modDirVersion/modules.dep"
for rev in 1 2 3; do
  fdtget -t s "$kernel/dtbs/mediatek/mt8195-cherry-tomato-r$rev.dtb" / compatible | grep -F "google,tomato-rev$rev"
done
fdtget -t s "$kernel/dtbs/mediatek/mt8195-cherry-tomato-r3.dtb" / compatible | grep -F 'google,tomato-rev4'
touch "$out"
