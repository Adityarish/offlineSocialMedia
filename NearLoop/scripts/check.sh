#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/test_schema.py
command -v flutter >/dev/null || { echo 'Flutter 3.38.0 is required for Dart analysis and tests.' >&2; exit 1; }
(cd apps/nearloop && flutter pub get)
dart format apps/nearloop/lib apps/nearloop/test packages
(cd apps/nearloop && flutter analyze && flutter test)
