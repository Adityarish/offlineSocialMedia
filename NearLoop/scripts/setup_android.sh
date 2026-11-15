#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/../flutter-env.sh" ]]; then source "$ROOT/../flutter-env.sh"; fi
command -v sdkmanager >/dev/null || { echo 'Install Android Studio command-line tools, then add sdkmanager to PATH.' >&2; exit 1; }
java -version
: "${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK directory}"
# Review and accept the Android licenses interactively in your Terminal.
sdkmanager --sdk_root="$ANDROID_HOME" --licenses
sdkmanager --sdk_root="$ANDROID_HOME" 'platform-tools' 'platforms;android-36' 'build-tools;35.0.0' 'ndk;28.2.13676358'
flutter doctor -v
