#!/bin/bash
# K-Research — macOS DMG Build + R2 Upload
# Triggered by K-Dev Dashboard (dmgscript type)
set -e

# ── Constants ─────────────────────────────────────────────────────────────────
SSH="ssh -i /home/claude/.ssh/id_ed25519 -o StrictHostKeyChecking=no Builder@100.73.209.21"
MAC_PATH="/Users/Builder/K-Research"
LINUX_DEST="/home/raphael/K-Dev/Projekte/K-Research/release/"
LOG="/tmp/kresearch_build_mac.log"
KEYCHAIN="/Users/Builder/Library/Keychains/kdev-signing.keychain-db"
KEYCHAIN_PASS="KDev2026!"
SIGNING_ID="Raphael Markus Kaufmann (H6X9JDXF96)"
R2_PREFIX="k-research"
R2_BUCKET="k-advisory-releases"
R2_ACCOUNT="4567be498d4437b735df9c22a7313c06"

# ── R2 Upload helper ──────────────────────────────────────────────────────────
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

echo "[2/6] npm install on MacBook..."
$SSH "
  export PATH=\"/usr/local/bin:/opt/homebrew/bin:\$PATH\"
  cd $MAC_PATH
  npm ci
" 2>&1 | tee -a "$LOG"

echo "[3/6] Building + signing DMG..."
$SSH "
  export PATH=\"/usr/local/bin:/opt/homebrew/bin:\$PATH\"
  security unlock-keychain -p '$KEYCHAIN_PASS' '$KEYCHAIN'
  security list-keychains -d user \
    -s '$KEYCHAIN' /Library/Keychains/System.keychain /System/Library/Keychains/SystemRootCertificates.keychain
  cd $MAC_PATH
  CSC_KEYCHAIN='$KEYCHAIN' CSC_NAME='$SIGNING_ID' \
    npx electron-builder --mac dmg --arm64 --publish=never
" 2>&1 | tee -a "$LOG"

echo "[4/6] Fetching DMG to Linux..."
mkdir -p "$LINUX_DEST"
DMG_REMOTE=$($SSH "find $MAC_PATH/release -name '*.dmg' ! -name '*.blockmap' | sort -V | tail -1")
scp -i /home/claude/.ssh/id_ed25519 -o StrictHostKeyChecking=no \
  "Builder@100.73.209.21:$DMG_REMOTE" \
  "$LINUX_DEST"

DMG_LOCAL="$LINUX_DEST$(basename "$DMG_REMOTE")"
echo "DMG: $DMG_LOCAL"

echo "[5/6] Uploading DMG to R2..."
upload_to_r2 "$DMG_LOCAL" "$R2_PREFIX/$(basename "$DMG_LOCAL")"

echo "[6/6] Generating + uploading latest-arm64-mac.yml..."
SHA=$(openssl dgst -sha512 -binary "$DMG_LOCAL" | base64 | tr -d '\n')
SIZE=$(stat -c%s "$DMG_LOCAL")
VERSION=$(node -e "console.log(require('/home/raphael/K-Dev/Projekte/K-Research/package.json').version)")
DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
DMG_FILENAME=$(basename "$DMG_LOCAL")

cat > "$LINUX_DEST/latest-arm64-mac.yml" << YMLEOF
version: ${VERSION}
files:
  - url: ${DMG_FILENAME}
    sha512: ${SHA}
    size: ${SIZE}
path: ${DMG_FILENAME}
sha512: ${SHA}
releaseDate: ${DATE}
YMLEOF

upload_to_r2 "$LINUX_DEST/latest-arm64-mac.yml" "$R2_PREFIX/latest-arm64-mac.yml" "text/yaml"
upload_to_r2 "$LINUX_DEST/latest-arm64-mac.yml" "$R2_PREFIX/latest-mac.yml" "text/yaml"

echo ""
echo "=== K-Research v${VERSION} build complete ==="
echo "R2 URL: https://pub-f8a055810aee4622b6883b39e71485fe.r2.dev/$R2_PREFIX/$DMG_FILENAME"
ls -lh "$LINUX_DEST"*.dmg 2>/dev/null
