#!/bin/sh
# Builds the "over the internet" helper (packages/qs_internet, iroh) and copies it
# into the Flutter Linux bundle, next to the app executable, where the app looks
# for it (lib/quick_send/internet_transfer.dart). Run after `flutter build linux`.
set -eu
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
BUNDLE=${1:-"$REPO/app/build/linux/x64/release/bundle"}
cargo build --release --locked --manifest-path "$REPO/packages/qs_internet/Cargo.toml" --bin qs-internet
install -m 755 "$REPO/packages/qs_internet/target/release/qs-internet" "$BUNDLE/qs-internet"
echo "qs-internet -> $BUNDLE/qs-internet"
