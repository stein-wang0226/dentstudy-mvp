#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v flutter >/dev/null || { echo '请先安装 Flutter 3.35+，见 README.md'; exit 1; }
PYTHON_BIN="${PYTHON_BIN:-python3}"
# Generate vendor-owned platform wrappers without replacing application sources.
bootstrap_backup="$(mktemp -d)"
trap 'rm -rf "$bootstrap_backup"' EXIT
cp pubspec.yaml "$bootstrap_backup/pubspec.yaml"
cp -R lib "$bootstrap_backup/lib"
cp -R test "$bootstrap_backup/test"
flutter create --no-pub --platforms=android,ios --org com.example --project-name dentstudy .
cp "$bootstrap_backup/pubspec.yaml" pubspec.yaml
cp -R "$bootstrap_backup/lib/." lib/
cp -R "$bootstrap_backup/test/." test/
# Flutter's generated counter test does not apply to this app.
if [ -f test/widget_test.dart ] && grep -q 'Counter increments smoke test' test/widget_test.dart; then
  rm test/widget_test.dart
fi
"$PYTHON_BIN" configure_platforms.py
flutter pub get
echo '平台文件已生成。请运行 flutter analyze、flutter test 后再构建安装包。'
