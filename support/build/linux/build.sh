#!/bin/sh
# Builds the Quick Send Linux release bundle and an AppImage inside the
# container from ./Containerfile. Host mounts: the repo, the pinned Flutter SDK
# (fvm), the pub cache and the Rust toolchain. Output: dist/Quick_Send-<ver>-x86_64.AppImage
#
#   support/build/linux/build.sh            # build image (if needed) + bundle + AppImage
#   PODMAN_ROOT=/tmp/qs-podman support/build/linux/build.sh   # keep container storage off /home
set -eu
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
FLUTTER_VERSION=$(sed -n 's/.*"flutter": *"\([^"]*\)".*/\1/p' "$REPO/.fvmrc")
SDK="$HOME/fvm/versions/$FLUTTER_VERSION"
PODMAN="podman"
if [ -n "${PODMAN_ROOT:-}" ]; then PODMAN="podman --root $PODMAN_ROOT/root --runroot $PODMAN_ROOT/run"; fi

$PODMAN image exists qs-linux-build || $PODMAN build -t qs-linux-build -f "$REPO/support/build/linux/Containerfile" "$REPO/support/build/linux"

mkdir -p "$REPO/build/tools"
$PODMAN run --rm --userns=keep-id --network=host --security-opt label=disable \
  -e QS_RELEASES_REPO="${QS_RELEASES_REPO:-}" -e QS_UPDATE_PUBLIC_KEY="${QS_UPDATE_PUBLIC_KEY:-}" -e TMPDIR="$REPO/build/tools" \
  -e HOME=/tmp/qs-home -e CARGO_HOME="$HOME/.cargo" -e RUSTUP_HOME="$HOME/.rustup" -e PUB_CACHE="$HOME/.pub-cache" \
  -e PATH="$SDK/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin" \
  -v "$REPO:$REPO" -v "$SDK:$SDK" -v "$HOME/.pub-cache:$HOME/.pub-cache" \
  -v "$HOME/.cargo:$HOME/.cargo" -v "$HOME/.rustup:$HOME/.rustup" \
  -w "$REPO/app" qs-linux-build sh -euc 'mkdir -p /tmp/qs-home
    flutter config --no-analytics >/dev/null
    # Newer libayatana marks tray_manager'\''s API deprecated; do not fail on it.
    export CXXFLAGS=-Wno-error=deprecated-declarations
    flutter build linux --release --dart-define=QS_RELEASES_REPO="${QS_RELEASES_REPO:-}" --dart-define=QS_UPDATE_PUBLIC_KEY="${QS_UPDATE_PUBLIC_KEY:-}"
    sh ../support/build/linux/bundle-internet-helper.sh
    sh ../support/build/linux/make-appimage.sh
  '
