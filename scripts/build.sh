#!/bin/bash
# Local, dependency-free Release build. Uses the macOS SDK selected by xcrun.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误：此脚本只能在 Mac 上编译；需要 macOS SDK 26 或更新版本。" >&2
  exit 1
fi
if ! xcrun --find clang >/dev/null 2>&1; then
  echo "请先安装并启动 Xcode，接受许可并完成组件安装。" >&2
  exit 1
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SDK_MAJOR="${SDK_VERSION%%.*}"
if [[ ! "$SDK_MAJOR" =~ ^[0-9]+$ ]] || (( SDK_MAJOR < 26 )); then
  echo "需要 macOS SDK 26+；当前为 $SDK_VERSION。检查 Xcode 的 Command Line Tools 选择。" >&2
  exit 1
fi
ARCH="${ARCH:-arm64}"
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
  echo "ARCH 只接受 arm64 或 x86_64。默认版本针对 Apple Silicon。" >&2
  exit 1
fi
OUT="$ROOT/build"
mkdir -p "$OUT"
STAGE="$(mktemp -d "$OUT/.compile.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/SideSpace.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGE/objects"
COMMON=(-arch "$ARCH" -isysroot "$SDK" -mmacosx-version-min=26.0 -std=c11
        -Oz -g -Wall -Wextra -fblocks -fvisibility=hidden
        -I"$ROOT/Sources/Core" -I"$ROOT/Sources/App")
OBJECTS=()
for SOURCE in "$ROOT"/Sources/Core/*.c "$ROOT"/Sources/App/*.m; do
  OBJECT="$STAGE/objects/$(basename "${SOURCE%.*}").o"
  ARGS=("${COMMON[@]}")
  if [[ "$SOURCE" == *.m ]]; then ARGS+=(-fobjc-arc); fi
  echo "编译 $(basename "$SOURCE")"
  xcrun clang "${ARGS[@]}" -c "$SOURCE" -o "$OBJECT"
  OBJECTS+=("$OBJECT")
done
BINARY="$APP/Contents/MacOS/SideSpace"
xcrun clang -arch "$ARCH" -isysroot "$SDK" -mmacosx-version-min=26.0 \
  "${OBJECTS[@]}" -Wl,-dead_strip \
  -framework AppKit -framework Carbon -framework ApplicationServices \
  -framework CoreGraphics -framework CoreFoundation -framework ServiceManagement \
  -o "$BINARY"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/MenuBarIcon.pdf" "$APP/Contents/Resources/MenuBarIcon.pdf"
for LOCALE in "$ROOT"/Resources/*.lproj; do
  cp -R "$LOCALE" "$APP/Contents/Resources/"
done
cp "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable SideSpace" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.jimmyliang.SideSpace" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 26.0" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
xcrun dsymutil "$BINARY" -o "$STAGE/SideSpace.app.dSYM"
xcrun strip -x "$BINARY"
# '-' is a local ad-hoc signature, not Developer ID signing/notarization.
codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
plutil -lint "$APP/Contents/Info.plist"
# Only replace this project's generated build output. No installed app is changed.
rm -rf "$OUT/SideSpace.app" "$OUT/SideSpace.app.dSYM"
mv "$APP" "$OUT/SideSpace.app"
mv "$STAGE/SideSpace.app.dSYM" "$OUT/SideSpace.app.dSYM"
echo
file "$OUT/SideSpace.app/Contents/MacOS/SideSpace"
echo "完成：$OUT/SideSpace.app"
echo "请先安装到固定的 Applications 目录，再打开、授权和启用登录启动。"
