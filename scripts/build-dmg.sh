#!/bin/bash
# K-Research — macOS DMG Build Script
# Runs on MacBook Builder via K-Dev Dashboard

set -e

REPO_DIR="/Users/Builder/K-Research"
KEYCHAIN="/Users/Builder/Library/Keychains/kdev-signing.keychain-db"
KEYCHAIN_PASS="KDev2026!"
CSC_NAME="Raphael Markus Kaufmann (H6X9JDXF96)"

echo "[K-Research] Starting DMG build..."

# ── Pull latest code ──────────────────────────────────────────────────────────
if [ ! -d "$REPO_DIR" ]; then
  git clone https://github.com/RaphaDevx/K-Research.git "$REPO_DIR"
fi

cd "$REPO_DIR"
git pull origin main
echo "[K-Research] Code up to date."

# ── Install dependencies ──────────────────────────────────────────────────────
npm ci
echo "[K-Research] Dependencies installed."

# ── Unlock signing keychain ───────────────────────────────────────────────────
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security list-keychains -d user \
  -s "$KEYCHAIN" \
  /Library/Keychains/System.keychain \
  /System/Library/Keychains/SystemRootCertificates.keychain
echo "[K-Research] Keychain unlocked."

# ── Build DMG ────────────────────────────────────────────────────────────────
CSC_KEYCHAIN="$KEYCHAIN" \
CSC_NAME="$CSC_NAME" \
npx electron-builder --mac dmg --arm64

echo "[K-Research] DMG built successfully."
ls -la release/*.dmg

# ── Upload to R2 ─────────────────────────────────────────────────────────────
DMG=$(ls release/*arm64.dmg | head -1)
FILENAME=$(basename "$DMG")
VERSION=$(node -e "console.log(require('./package.json').version)")

echo "[K-Research] Uploading $FILENAME to R2..."
# Upload via rclone or curl (same as other K-Dev builds)
echo "[K-Research] Done. Version $VERSION"
