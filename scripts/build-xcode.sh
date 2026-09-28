#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then echo "需要 macOS 与完整 Xcode。" >&2; exit 1; fi
xcodebuild -project "$ROOT/SideSpace.xcodeproj" -scheme SideSpace \
  -configuration Release -derivedDataPath "$ROOT/build/DerivedData" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
echo "编译结果：$ROOT/build/DerivedData/Build/Products/Release/SideSpace.app"
