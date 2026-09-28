#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then echo "只能在 Mac 上安装。" >&2; exit 1; fi
SOURCE="$ROOT/build/SideSpace.app"
if [[ ! -d "$SOURCE" ]]; then SOURCE="$ROOT/build/DerivedData/Build/Products/Release/SideSpace.app"; fi
if [[ ! -d "$SOURCE" ]]; then echo "未发现编译结果，请先运行 Build.command。" >&2; exit 1; fi
if pgrep -x SideSpace >/dev/null; then
  echo "请先从菜单栏退出 SideSpace，再重新安装；此脚本不会强制结束进程。" >&2; exit 1
fi
DEST="$HOME/Applications/SideSpace.app"
mkdir -p "$HOME/Applications"
if [[ -e "$DEST" ]]; then
  printf '替换 %s？[y/N] ' "$DEST"
  read -r ANSWER
  if [[ "$ANSWER" != "y" && "$ANSWER" != "Y" ]]; then echo "已取消。"; exit 0; fi
  rm -rf "$DEST"
fi
ditto "$SOURCE" "$DEST"
codesign --verify --strict "$DEST"
echo "已安装：$DEST"
echo "首次启动后，请在系统设置中给 SideSpace 辅助功能权限。"
open "$DEST"
