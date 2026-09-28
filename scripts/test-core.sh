#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/smartwindow-test.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
CC="${CC:-clang}"
FLAGS=(-std=c11 -O1 -g -Wall -Wextra -Werror)
if [[ "${SANITIZE:-0}" == "1" ]]; then FLAGS+=(-fsanitize=address,undefined -fno-omit-frame-pointer); fi
"$CC" "${FLAGS[@]}" \
    -I"$ROOT/Sources/Core" "$ROOT/Sources/Core/SWLayout.c" "$ROOT/Tests/layout_tests.c" \
    -lm -o "$OUT/layout-tests"
"$OUT/layout-tests"
