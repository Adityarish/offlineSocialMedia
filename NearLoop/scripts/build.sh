#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
target="${1:-macos}"
command -v flutter >/dev/null || { echo 'Install Flutter 3.38.0 and run python3 scripts/bootstrap.py first.' >&2; exit 1; }
case "$target" in
  macos|ios)
    [[ "$(uname -s)" == Darwin ]] || { echo 'Apple builds require macOS.' >&2; exit 1; }
    xcodebuild -version >/dev/null || { echo 'Install full Xcode and select its developer directory.' >&2; exit 1; } ;;
  android) command -v java >/dev/null || { echo 'Install a compatible JDK and Android SDK.' >&2; exit 1; } ;;
  *) echo 'Usage: build.sh android|macos|ios. Windows: build.ps1.' >&2; exit 1 ;;
esac
[[ -f "apps/nearloop/.metadata" ]] || { echo 'Run python3 scripts/bootstrap.py to generate native runners.' >&2; exit 1; }
if [[ "$target" == android ]]; then python3 scripts/prepare_gradle.py; fi
cd apps/nearloop
flutter doctor -v
flutter analyze
flutter test
case "$target" in
  macos) flutter build macos --debug; test -d build/macos/Build/Products/Debug/nearloop.app ;;
  ios) flutter build ios --simulator --debug; test -d build/ios/iphonesimulator/Runner.app ;;
  android) flutter build apk --debug; test -f build/app/outputs/flutter-apk/app-debug.apk ;;
esac
printf '%s\n' 'Development validation build only. See docs/build.md for signed distribution prerequisites.'
