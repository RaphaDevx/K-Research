#!/bin/bash
# K-Research — macOS DMG + Zip Build + R2 Upload (mit Auto-Updater Support)
# Triggered by K-Dev Dashboard (dmgscript type)
set -e

SSH="ssh -i /home/claude/.ssh/id_ed25519 -o StrictHostKeyChecking=no Builder@100.73.209.21"
MAC_PATH="/Users/Builder/K-Research"
LINUX_DEST="/home/raphael/K-Dev/Projekte/K-Research/release/"
LOG="/tmp/kresearch_build_mac.log"
KEYCHAIN="/Users/Builder/Library/Keychains/kdev-signing.keychain-db"
SIGNING_ID="Raphael Markus Kaufmann (H6X9JDXF96)"
R2_PREFIX="k-research"
R2_BUCKET="k-advisory-releases"
R2_ACCOUNT="4567be498d4437b735df9c22a7313c06"

upload_to_r2() {
  local FILE="$1" KEY="$2" CONTENT_TYPE="${3:-application/octet-stream}"
  source /home/claude/.keys/tokens.env
  ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$KEY")
  curl -s -X PUT \
    "https://api.cloudflare.com/client/v4/accounts/${R2_ACCOUNT}/r2/buckets/${R2_BUCKET}/objects/$ENCODED" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: $CONTENT_TYPE" \
    --data-binary "@$FILE" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('R2 OK:', d['result']['key'] if d.get('success') else 'FAIL: '+str(d))" 2>/dev/null
}

echo "[1/6] Syncing to MacBook..."
rsync -az --delete \
  --exclude=node_modules \
  --exclude=release \
  --exclude=.git \
  --exclude="*.log" \
  -e "ssh -i /home/claude/.ssh/id_ed25519 -o StrictHostKeyChecking=no" \
  /home/raphael/K-Dev/Projekte/K-Research/ \
  Builder@100.73.209.21:"$MAC_PATH/"

echo "[2/6] npm ci on MacBook..."
$SSH "
  export PATH=\"/usr/local/bin:/opt/homebrew/bin:\$PATH\"
  cd $MAC_PATH && npm ci
" 2>&1 | tee -a "$LOG"

echo "[3/6] Building DMG + Zip (signed)..."
$SSH "
  export PATH=\"/usr/local/bin:/opt/homebrew/bin:\$PATH\"
  /Users/Builder/bin/kdev-unlock-keychain
  security list-keychains -d user \
    -s '$KEYCHAIN' /Library/Keychains/System.keychain /System/Library/Keychains/SystemRootCertificates.keychain
  cd $MAC_PATH
  CSC_KEYCHAIN='$KEYCHAIN' CSC_NAME='$SIGNING_ID' \
    npx electron-builder --mac dmg zip --arm64 --publish=never
" 2>&1 | tee -a "$LOG"

echo "[4/6] Fetching artifacts to Linux..."
mkdir -p "$LINUX_DEST"

DMG_REMOTE=$($SSH "find $MAC_PATH/release -name '*.dmg' ! -name '*.blockmap' | sort -V | tail -1")
ZIP_REMOTE=$($SSH "find $MAC_PATH/release -name '*arm64*mac.zip' 2>/dev/null | sort -V | tail -1" || true)
YML_REMOTE="$MAC_PATH/release/latest-arm64-mac.yml"

scp -i /home/claude/.ssh/id_ed25519 -o StrictHostKeyChecking=no \
  "Builder@100.73.209.21:$DMG_REMOTE" "$LINUX_DEST"

if [ -n "$ZIP_REMOTE" ]; then
  scp -i /home/claude/.ssh/id_ed25519 -o StrictHostKeyChecking=no \
    "Builder@100.73.209.21:$ZIP_REMOTE" "$LINUX_DEST"
fi

# Get the yml that electron-builder generated (correctly references zip for updater)
$SSH "[ -f $YML_REMOTE ] && cat $YML_REMOTE" > "$LINUX_DEST/latest-arm64-mac.yml" 2>/dev/null || true

echo "[5/6] Uploading to R2..."
DMG_LOCAL="$LINUX_DEST$(basename "$DMG_REMOTE")"
upload_to_r2 "$DMG_LOCAL" "$R2_PREFIX/$(basename "$DMG_LOCAL")"

if [ -n "$ZIP_REMOTE" ]; then
  ZIP_LOCAL="$LINUX_DEST$(basename "$ZIP_REMOTE")"
  upload_to_r2 "$ZIP_LOCAL" "$R2_PREFIX/$(basename "$ZIP_LOCAL")" "application/zip"
fi

echo "[6/6] Uploading YMLs for auto-updater..."
if [ -s "$LINUX_DEST/latest-arm64-mac.yml" ]; then
  upload_to_r2 "$LINUX_DEST/latest-arm64-mac.yml" "$R2_PREFIX/latest-arm64-mac.yml" "text/yaml"
  cp "$LINUX_DEST/latest-arm64-mac.yml" "$LINUX_DEST/latest-mac.yml"
  upload_to_r2 "$LINUX_DEST/latest-mac.yml" "$R2_PREFIX/latest-mac.yml" "text/yaml"
  echo "YML uploaded (references zip for OTA updates)"
else
  echo "WARNING: no latest-arm64-mac.yml from electron-builder"
fi

echo ""
VERSION=$(node -e "console.log(require('/home/raphael/K-Dev/Projekte/K-Research/package.json').version)")
echo "=== K-Research v${VERSION} build complete ==="
echo "DMG (initial install): https://pub-f8a055810aee4622b6883b39e71485fe.r2.dev/$R2_PREFIX/$(basename "$DMG_LOCAL")"
[ -n "$ZIP_REMOTE" ] && echo "Zip (auto-update):      https://pub-f8a055810aee4622b6883b39e71485fe.r2.dev/$R2_PREFIX/$(basename "$ZIP_REMOTE")"
echo "YML (updater check):   https://pub-f8a055810aee4622b6883b39e71485fe.r2.dev/$R2_PREFIX/latest-arm64-mac.yml"
ls -lh "$LINUX_DEST" 2>/dev/null
