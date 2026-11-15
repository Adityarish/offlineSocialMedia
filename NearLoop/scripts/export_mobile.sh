#!/usr/bin/env bash
# Build local installable artifacts. Does not upload or publish anything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/../flutter-env.sh" ]]; then source "$ROOT/../flutter-env.sh"; fi
TARGET="${1:-android}"
case "$TARGET" in android|ios|all) ;; *) echo 'Usage: bash scripts/export_mobile.sh android|ios|all' >&2; exit 2;; esac
if [[ "$TARGET" == android || "$TARGET" == all ]]; then
  python3 "$ROOT/scripts/prepare_gradle.py"
fi
cd "$ROOT/apps/nearloop"
flutter pub get
flutter analyze --no-pub lib test/social_ui_test.dart
flutter test --no-pub test/social_ui_test.dart
OUT="$ROOT/release/0.2.0/apps"
mkdir -p "$OUT"
if [[ "$TARGET" == android || "$TARGET" == all ]]; then
  flutter build apk --debug --no-pub
  cp build/app/outputs/flutter-apk/app-debug.apk "$OUT/NearLoop-0.2.0-android-debug.apk"
  echo "Android development APK: $OUT/NearLoop-0.2.0-android-debug.apk"
fi
if [[ "$TARGET" == ios || "$TARGET" == all ]]; then
  [[ "$(uname -s)" == Darwin ]] || { echo 'iOS builds require macOS and Xcode.' >&2; exit 1; }
  flutter build ipa --release --export-method development --no-pub
  shopt -s nullglob
  IPAS=(build/ios/ipa/*.ipa)
  [[ ${#IPAS[@]} -gt 0 ]] || { echo 'Xcode did not export a signed IPA. Configure the Runner team and device provisioning.' >&2; exit 1; }
  cp "${IPAS[0]}" "$OUT/NearLoop-0.2.0-ios-development.ipa"
  echo "Provisioned iOS development IPA: $OUT/NearLoop-0.2.0-ios-development.ipa"
fi
python3 "$ROOT/tools/package_source.py"
