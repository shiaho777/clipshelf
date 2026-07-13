#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM_ID="${CLIPSHELF_DEVELOPMENT_TEAM:-${1:-}}"

if [[ -z "$TEAM_ID" ]]; then
  if command -v defaults >/dev/null 2>&1; then
    TEAM_ID="$(defaults read com.apple.dt.Xcode IDEProvisioningTeams 2>/dev/null | sed -n 's/.*teamID = \([A-Z0-9]\{10\}\);.*/\1/p' | head -1 || true)"
  fi
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "No Development Team found."
  echo "Pass your 10-character Team ID:"
  echo "  ./scripts/setup-icloud-signing.sh YOUR_TEAM_ID"
  echo "Or set CLIPSHELF_DEVELOPMENT_TEAM and re-run."
  exit 1
fi

mkdir -p Config
cat > Config/Signing.xcconfig <<XCC
DEVELOPMENT_TEAM = $TEAM_ID
CODE_SIGN_STYLE = Automatic
XCC

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

echo "Wrote Config/Signing.xcconfig with DEVELOPMENT_TEAM=$TEAM_ID"
echo "Next: open ClipShelf.xcodeproj in Xcode → Signing & Capabilities → confirm iCloud/CloudKit container iCloud.com.nicebro.ClipShelf → Run."
