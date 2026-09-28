#!/bin/bash
cd "$(dirname "$0")" || exit 1
bash scripts/build.sh
STATUS=$?
echo
if [[ "$STATUS" != 0 ]]; then echo "构建失败。请保留上面的完整错误信息。"; fi
read -r -p "按回车关闭…" _
exit "$STATUS"
