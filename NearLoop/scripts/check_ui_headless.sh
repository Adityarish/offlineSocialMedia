#!/usr/bin/env bash
# Runs actual Flutter widget tests without opening a VM-service/test-server port.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/../flutter-env.sh" ]]; then source "$ROOT/../flutter-env.sh"; fi
SDK="$(python3 -c 'import pathlib,shutil; print(pathlib.Path(shutil.which("flutter")).resolve().parents[1])')"
TESTER="$SDK/bin/cache/artifacts/engine/darwin-x64/flutter_tester"
[[ -x "$TESTER" ]] || { echo 'This fallback runner requires the macOS Flutter test engine.' >&2; exit 1; }
cd "$ROOT/apps/nearloop"
flutter build bundle --debug --no-pub --target=test/social_ui_test.dart --dart-define="NEARLOOP_SCREENSHOTS=$ROOT/release/ui-preview"
LOG="$ROOT/release/ui-preview/widget-tests.log"
mkdir -p "$(dirname "$LOG")"
# Match flutter test's Ahem font as well as the platform font used for previews.
FLUTTER_TEST=true "$TESTER" --disable-vm-service --non-interactive --use-test-fonts --flutter-assets-dir=build/flutter_assets build/flutter_assets/kernel_blob.bin 2>&1 | tee "$ROOT/release/ui-preview/widget-tests-ahem.log"
grep -Fq 'All tests passed!' "$ROOT/release/ui-preview/widget-tests-ahem.log"
FLUTTER_TEST=true "$TESTER" --disable-vm-service --non-interactive --flutter-assets-dir=build/flutter_assets build/flutter_assets/kernel_blob.bin 2>&1 | tee "$LOG"
# flutter_tester can exit zero even when the standalone test runner reports failures.
grep -Fq 'All tests passed!' "$LOG"
# Leave normal app assets behind, never a test-target kernel.
flutter build bundle --debug --no-pub --target=lib/main.dart
