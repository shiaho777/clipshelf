#!/bin/bash
set -euo pipefail

clear 2>/dev/null || true
echo "========================================"
echo "  ClipShelf — Fix Damaged App"
echo "  修复「已损坏，无法打开」"
echo "========================================"
echo

CANDIDATES=(
  "/Applications/ClipShelf.app"
  "$HOME/Applications/ClipShelf.app"
)

TARGET=""
for path in "${CANDIDATES[@]}"; do
  if [ -d "$path" ]; then
    TARGET="$path"
    break
  fi
done

if [ -z "$TARGET" ]; then
  echo "未找到已安装的 ClipShelf.app"
  echo "请先从 DMG 把 ClipShelf 拖到「应用程序」，再运行本脚本。"
  echo
  echo "ClipShelf.app not found in Applications."
  echo "Install from the DMG first, then run this script again."
  echo
  read -r -p "按回车键关闭 / Press Enter to close..." _
  exit 1
fi

echo "目标 / Target:"
echo "  $TARGET"
echo
echo "执行: xattr -cr \"$TARGET\""
echo

# Clear quarantine on this script itself if needed, then the app
xattr -cr "$0" 2>/dev/null || true
xattr -cr "$TARGET"

echo
echo "完成 / Done."
echo "请从「应用程序」重新打开 ClipShelf。"
echo "Open ClipShelf from Applications again."
echo
read -r -p "按回车键关闭 / Press Enter to close..." _
