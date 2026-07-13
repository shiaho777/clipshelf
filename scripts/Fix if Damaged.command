#!/bin/bash
set -euo pipefail

clear 2>/dev/null || true
echo "========================================"
echo "  ClipShelf — Fix Damaged App"
echo "  修复「已损坏，无法打开」"
echo "========================================"
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CANDIDATES=(
  "/Applications/ClipShelf.app"
  "$HOME/Applications/ClipShelf.app"
  "$SCRIPT_DIR/ClipShelf.app"
)

TARGET=""
for path in "${CANDIDATES[@]}"; do
  if [ -d "$path" ]; then
    TARGET="$path"
    break
  fi
done

if [ -z "$TARGET" ]; then
  echo "未找到 ClipShelf.app / ClipShelf.app not found."
  echo
  echo "请先把 ClipShelf 拖到「应用程序」，再运行本脚本。"
  echo "Drag ClipShelf to Applications first, then run this again."
  echo
  read -r -p "按回车键关闭 / Press Enter to close..." _
  exit 1
fi

echo "目标 / Target:"
echo "  $TARGET"
echo
echo "正在清除隔离属性 (xattr -cr)..."
echo "Clearing quarantine attributes..."
echo

if xattr -cr "$TARGET"; then
  echo "完成 / Done."
  echo
  echo "现在可以从「应用程序」启动 ClipShelf。"
  echo "You can now open ClipShelf from Applications."
  echo
  echo "若仍被拦截：右键 ClipShelf → 打开 → 打开"
  echo "If still blocked: right-click ClipShelf → Open → Open"
else
  echo "失败 / Failed. 可尝试手动执行："
  echo "  xattr -cr \"$TARGET\""
  read -r -p "按回车键关闭 / Press Enter to close..." _
  exit 1
fi

echo
read -r -p "按回车键关闭 / Press Enter to close..." _
