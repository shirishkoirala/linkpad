#!/bin/bash
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd /work
mkdir -p /results
cat /etc/os-release > /results/linux-release.txt
ldd --version > /results/libc-version.txt
flutter --version | tee /results/flutter-version.txt
go version | tee /results/go-version.txt
xvfb-run -a env LINKPAD_X11_INTEGRATION=1 go test -race -v ./... > /results/go-tests.log 2>&1
go vet ./... > /results/go-vet.log 2>&1
cd mobile
flutter analyze > /results/flutter-analyze.log 2>&1
LINKPAD_DESKTOP_TEST_BINARY=/work/mobile/build/linux/x64/release/bundle/lib/linkpad-server \
  flutter test > /results/flutter-tests.log 2>&1
ldd build/linux/x64/release/bundle/linkpad_controller > /results/linked-libraries.txt
if grep -q 'not found' /results/linked-libraries.txt; then cat /results/linked-libraries.txt; exit 1; fi
dbus-run-session -- xvfb-run -a python3 "$script_dir/linux-container-smoke.py" > /results/desktop-smoke.log 2>&1
tar -czf /results/Linkpad-Linux-x86_64-desktop.tar.gz -C build/linux/x64/release/bundle .
echo 'Build, Go X11 integration, Flutter tests, desktop startup/shutdown, and dependency checks passed.'
