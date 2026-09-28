#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then echo "需要 macOS。" >&2; exit 1; fi
PID="$(pgrep -x SideSpace | head -1 || true)"
if [[ -z "$PID" ]]; then echo "请先启动已安装的 Release 版 SideSpace。" >&2; exit 1; fi
echo "=== $(date) ==="
echo "请勿在 Xcode 调试器或 Sanitizer 下比较 Release 常驻内存。"
ps -p "$PID" -o pid=,etime=,rss=,%cpu=,command=
echo "=== vmmap summary ==="
vmmap -summary "$PID" || echo "系统拒绝 vmmap 访问；改用活动监视器或 Instruments。"
if command -v footprint >/dev/null 2>&1; then
  echo "=== physical footprint ==="
  footprint -p "$PID" || echo "footprint 当前不可读取；不自动请求 root 权限。"
fi
