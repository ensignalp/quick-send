#!/bin/sh
# Packs app/build/linux/x64/release/bundle into an AppImage (run from app/).
# The AppIndicator stack is bundled because many distributions do not ship it
# by default; GTK, GLib and the C library come from the host system.
set -eu
VERSION=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)
WORK=${TMPDIR:-/tmp}/quick-send-appdir
TOOL=${TMPDIR:-/tmp}/appimagetool-x86_64.AppImage
rm -rf "$WORK" && mkdir -p "$WORK/usr/bin" "$WORK/usr/lib" "$WORK/usr/share/applications"
cp -a build/linux/x64/release/bundle/. "$WORK/usr/bin/"

for lib in libayatana-appindicator3.so.1 libayatana-indicator3.so.7 libayatana-ido3-0.4.so.0 libdbusmenu-glib.so.4 libdbusmenu-gtk3.so.4; do
  path=$(ldconfig -p | awk -v l="$lib" '$1 == l { print $NF; exit }')
  [ -n "$path" ] && cp -L "$path" "$WORK/usr/lib/"
done

mkdir -p "$WORK/usr/share/icons"
cp -a linux/packaging/icons/hicolor "$WORK/usr/share/icons/"   # 16…512 px, scalable SVG, tray icon
cp linux/packaging/icons/hicolor/256x256/apps/com.ensignsoft.quicksend.png "$WORK/com.ensignsoft.quicksend.png"
cp "$WORK/com.ensignsoft.quicksend.png" "$WORK/.DirIcon"
cp linux/packaging/com.ensignsoft.quicksend.desktop "$WORK/com.ensignsoft.quicksend.desktop"
cp linux/packaging/com.ensignsoft.quicksend.desktop "$WORK/usr/share/applications/"

cat > "$WORK/AppRun" <<'RUN'
#!/bin/sh
HERE=$(dirname "$(readlink -f "$0")")
export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Desktop integration. GNOME/KDE find the app icon for the app grid and the dock (the
# window's app id com.ensignsoft.quicksend) through a .desktop file and theme icons; a bare
# AppImage provides neither, so the dock shows an empty icon. Install both for this user,
# and again whenever the AppImage moved. Skipped when a system package already provides
# them; QUICKSEND_NO_DESKTOP_INTEGRATION=1 opts out.
id=com.ensignsoft.quicksend
if [ -n "${APPIMAGE:-}" ] && [ -z "${QUICKSEND_NO_DESKTOP_INTEGRATION:-}" ] && [ ! -e "/usr/share/applications/$id.desktop" ]; then
  data="${XDG_DATA_HOME:-$HOME/.local/share}"
  changed=""
  # Exec argument quoting per the desktop entry spec (escape \ " ` $, then double backslashes).
  QS_EXEC="\"$(printf '%s' "$APPIMAGE" | sed -e 's/[\\"`$]/\\&/g' -e 's/\\/\\\\/g')\"" \
    awk 'index($0, "Exec=quicksend") == 1 { print "Exec=" ENVIRON["QS_EXEC"] substr($0, 15); next } { print }' \
    "$HERE/$id.desktop" > "${TMPDIR:-/tmp}/$id.desktop.$$"
  if ! cmp -s "${TMPDIR:-/tmp}/$id.desktop.$$" "$data/applications/$id.desktop"; then
    mkdir -p "$data/applications" && mv "${TMPDIR:-/tmp}/$id.desktop.$$" "$data/applications/$id.desktop" && changed=1
  else
    rm -f "${TMPDIR:-/tmp}/$id.desktop.$$"
  fi
  for icon in "$HERE"/usr/share/icons/hicolor/*/apps/$id.png "$HERE"/usr/share/icons/hicolor/*/apps/$id.svg; do
    dest="$data/${icon#"$HERE/usr/share/"}"
    if ! cmp -s "$icon" "$dest"; then mkdir -p "$(dirname "$dest")" && cp "$icon" "$dest" && changed=1 && icons_changed=1; fi
  done
  # GNOME Shell (dock, app grid) keeps icons it has loaded until the theme directory's
  # mtime changes; replacing a file in place does not change it, so bump it explicitly.
  if [ -n "${icons_changed:-}" ]; then
    touch "$data/icons/hicolor"
    command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -e "$data/icons/hicolor/icon-theme.cache" ] &&
      gtk-update-icon-cache -q -f -t "$data/icons/hicolor" >/dev/null 2>&1
  fi
  if [ -n "$changed" ] && command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$data/applications" >/dev/null 2>&1
  fi
  # File icon: GNOME Files shows this icon for the AppImage file itself.
  if command -v gio >/dev/null 2>&1; then
    gio set "$APPIMAGE" metadata::custom-icon "file://$data/icons/hicolor/256x256/apps/$id.png" >/dev/null 2>&1
  fi
fi

exec "$HERE/usr/bin/quicksend" "$@"
RUN
chmod +x "$WORK/AppRun"

if [ ! -x "$TOOL" ]; then
  curl -fsSL -o "$TOOL" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$TOOL"
fi
mkdir -p ../dist
# Write next to the target and rename, so a copy that is still running is not overwritten in place.
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$WORK" "../dist/.Quick_Send-$VERSION-x86_64.AppImage.tmp"
mv -f "../dist/.Quick_Send-$VERSION-x86_64.AppImage.tmp" "../dist/Quick_Send-$VERSION-x86_64.AppImage"
echo "AppImage: dist/Quick_Send-$VERSION-x86_64.AppImage"
