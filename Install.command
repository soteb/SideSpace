#!/bin/bash
cd "$(dirname "$0")" || exit 1
bash scripts/install.sh
STATUS=$?
echo
read -r -p "按回车关闭…" _
exit "$STATUS"
