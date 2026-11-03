# The pinned kernel ships every Tomato DTB the board module packs, and the
# early storage/USB/display modules resolve against it.
test -s "$earlyModules/lib/modules/$modDirVersion/modules.dep"
for rev in 1 2 3; do
  fdtget -t s "$kernel/dtbs/mediatek/mt8195-cherry-tomato-r$rev.dtb" / compatible | grep -F "google,tomato-rev$rev"
done
fdtget -t s "$kernel/dtbs/mediatek/mt8195-cherry-tomato-r3.dtb" / compatible | grep -F 'google,tomato-rev4'

# The radio kill overlay applies to every revision and releases both lines.
dtc -@ -I dts -O dtb -o radio-kill.dtbo "$radioKill"
for rev in 1 2 3; do
  fdtoverlay -i "$kernel/dtbs/mediatek/mt8195-cherry-tomato-r$rev.dtb" -o board.dtb radio-kill.dtbo
  test "$(fdtget board.dtb /soc/pinctrl@10005000/wifi-kill-hog gpios)" = '61 0'
  test "$(fdtget board.dtb /soc/pinctrl@10005000/bt-kill-hog gpios)" = '59 0'
  fdtget board.dtb /soc/pinctrl@10005000/wifi-kill-hog output-high
  fdtget board.dtb /soc/pinctrl@10005000/bt-kill-hog output-high
done
touch "$out"
