#!/usr/bin/env bash
# Builds the Quick Send RPM from an existing Flutter Linux release bundle.
# Usage: packaging/rpm/build-rpm.sh [version]   (run from repo root after
#        `cd app && fvm flutter build linux --release`)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="${1:-$(sed -n 's/^version: \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' "$ROOT/app/pubspec.yaml")}"
BUNDLE="$ROOT/app/build/linux/x64/release/bundle"
[[ -x "$BUNDLE/quicksend" ]] || { echo "Missing $BUNDLE/quicksend; build Flutter Linux release first" >&2; exit 1; }
TOP="$ROOT/build/rpm"
STAGE="$TOP/stage/quicksend-$VERSION"
rm -rf "$TOP"; mkdir -p "$STAGE" "$TOP"/{SOURCES,SPECS,RPMS,SRPMS,BUILD,BUILDROOT}
cp -a "$BUNDLE" "$STAGE/bundle"
cp "$ROOT"/app/linux/packaging/com.ensignsoft.quicksend.{desktop,metainfo.xml} "$STAGE/"
cp -a "$ROOT/app/linux/packaging/icons" "$STAGE/icons"
cp "$ROOT/packaging/firewalld/quicksend.xml" "$ROOT/LICENSE" "$ROOT/NOTICE" "$STAGE/"
tar -C "$TOP/stage" -czf "$TOP/SOURCES/quicksend-$VERSION-linux-x86_64.tar.gz" "quicksend-$VERSION"
rpmbuild ${RPMBUILD_ARGS:-} --define "_topdir $TOP" --define "qs_version $VERSION" -bb "$ROOT/packaging/rpm/quicksend.spec"
find "$TOP/RPMS" -name '*.rpm' -print
