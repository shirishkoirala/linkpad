#!/bin/sh
# Called by Xcode before the app is signed. Match the Flutter app architectures.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/go/bin:/usr/local/bin:$PATH"
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
output=$1
mkdir -p "$(dirname -- "$output")"
cd "$repo"
export GOOS=darwin CGO_ENABLED=1
export CGO_CFLAGS="${CGO_CFLAGS:-} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET:-12.0}"
export CGO_LDFLAGS="${CGO_LDFLAGS:-} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET:-12.0}"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
for architecture in ${ARCHS:-$(uname -m)}; do
  case "$architecture" in
    arm64|arm64e) export GOARCH=arm64 ;;
    x86_64) export GOARCH=amd64 ;;
    *) echo "Unsupported server architecture: $architecture" >&2; exit 1 ;;
  esac
  go build -trimpath -o "$temporary/$GOARCH" ./cmd/linkpad
done
/usr/bin/lipo -create "$temporary"/* -output "$output"
/usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$output"
