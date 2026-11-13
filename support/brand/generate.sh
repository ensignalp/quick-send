#!/bin/sh
# Regenerates every raster icon from the two brand SVGs in this folder.
# Requires ImageMagick 7 (`magick`) with an SVG delegate (rsvg/inkscape).
set -eu
cd "$(dirname "$0")/../.."
ICON=support/brand/quick-send-icon.svg
DESKTOP_ICON=support/brand/quick-send-icon-desktop.svg # Linux: icon on the freedesktop grid (with margin)
MARK=support/brand/quick-send-mark.svg

render() { # svg size out [color] [content-size]
  mkdir -p "$(dirname "$3")"
  src=$1
  if [ "${4:-}" != "" ]; then
    src=$(mktemp --suffix=.svg); sed "s/currentColor/$4/" "$1" > "$src"
  fi
  inner=${5:-$2}
  magick -background none -density 600 "$src" -resize "${inner}x${inner}" -gravity center -extent "${2}x${2}" "$3"
  [ "${4:-}" != "" ] && rm -f "$src"
  return 0
}

# Desktop (Flutter) app assets: logo-*.png is the full icon, -white/-black are tray marks.
# The tray marks are drawn 28 px tall on the 32 px canvas so they sit a little
# smaller in the top bar than a full-bleed glyph.
# logo-512 is the in-app logo (full bleed); the smaller ones are window/tray icons.
for s in 32 128 256; do render "$DESKTOP_ICON" $s "app/assets/img/logo-$s.png"; done
render "$ICON" 512 app/assets/img/logo-512.png
render "$MARK" 32 app/assets/img/logo-32-white.png '#FFFFFF' 28
render "$MARK" 32 app/assets/img/logo-32-black.png '#000000' 28
render "$MARK" 512 app/assets/img/logo-512-white.png '#FFFFFF'
magick app/assets/img/logo-256.png -define icon:auto-resize=256,128,64,48,32,16 app/assets/img/logo.ico

# Linux packaging (hicolor) and AppImage.
# Every size desktops commonly ask for (dock, app grid, file manager, alt-tab).
for s in 16 24 32 48 64 128 256 512; do render "$DESKTOP_ICON" $s "app/linux/packaging/icons/hicolor/${s}x${s}/apps/com.ensignsoft.quicksend.png"; done
render "$MARK" 32 app/linux/packaging/icons/hicolor/32x32/apps/com.ensignsoft.quicksend-tray.png '#FFFFFF' 28
mkdir -p app/linux/packaging/icons/hicolor/scalable/apps
cp "$DESKTOP_ICON" app/linux/packaging/icons/hicolor/scalable/apps/com.ensignsoft.quicksend.svg
render "$DESKTOP_ICON" 256 support/build/appimage/quick-send.png

# Android (React Native) legacy launcher bitmaps; the adaptive icon is vector XML.
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  d=${pair%%:*}; s=${pair##*:}
  render "$ICON" "$s" "mobile/android/app/src/main/res/mipmap-$d/ic_launcher.png"
  magick "mobile/android/app/src/main/res/mipmap-$d/ic_launcher.png" \
    \( -size "${s}x${s}" xc:none -fill white -draw "circle $((s/2)),$((s/2)) $((s/2)),0" \) \
    -compose DstIn -composite "mobile/android/app/src/main/res/mipmap-$d/ic_launcher_round.png"
done

# Store listing icon (F-Droid / Play, 512 px).
render "$ICON" 512 fastlane/metadata/android/en-US/images/icon.png

# Expo / in-app assets.
mkdir -p mobile/assets
render "$ICON" 1024 mobile/assets/icon.png
render "$MARK" 512 mobile/assets/quick-send-mark.png '#FFFFFF'
echo "Icons regenerated."
