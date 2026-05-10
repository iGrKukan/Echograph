#!/bin/bash
# Bootstraps fastlane/secrets/ on a new Mac by symlinking it to iCloud Drive.
#
# This file is OK to commit because it doesn't touch any secrets — it just
# wires up the symlink. The real secrets live in iCloud Drive at:
#   ~/Library/Mobile Documents/com~apple~CloudDocs/voicekeep-secrets/
#
# Usage on a fresh clone:
#   bash fastlane/setup_secrets.sh
#
# On the very first Mac (where you generated the keys), you'll have populated
# the iCloud folder once with `cp fastlane/secrets/*.p8 "$ICLOUD"/voicekeep-secrets/`.
# After that every other Mac just needs this script.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs/voicekeep-secrets"
LOCAL_LINK="$REPO_ROOT/fastlane/secrets"
ALT_LINK="$REPO_ROOT/private_keys"

if [ ! -d "$ICLOUD" ]; then
    echo "❌ iCloud Drive folder not found:"
    echo "   $ICLOUD"
    echo
    echo "Make sure iCloud Drive is enabled in System Settings → Apple ID,"
    echo "and that you've populated the folder on at least one Mac:"
    echo "   mkdir -p \"$ICLOUD\""
    echo "   cp /path/to/AuthKey_*.p8 \"$ICLOUD/\""
    exit 1
fi

# fastlane/secrets — used by Python scripts in fastlane/
if [ ! -L "$LOCAL_LINK" ]; then
    rm -rf "$LOCAL_LINK"
    ln -s "$ICLOUD" "$LOCAL_LINK"
    echo "✓ Symlinked fastlane/secrets → iCloud Drive"
else
    echo "↻ fastlane/secrets is already a symlink"
fi

# private_keys/ — used by xcrun altool for App Store upload
mkdir -p "$ALT_LINK"
for p8 in "$ICLOUD"/AuthKey_*.p8; do
    [ -f "$p8" ] || continue
    name="$(basename "$p8")"
    if [ ! -f "$ALT_LINK/$name" ]; then
        ln -s "$p8" "$ALT_LINK/$name"
        echo "✓ Symlinked private_keys/$name → iCloud Drive"
    fi
done

echo
echo "✓ Setup complete."
echo
echo "Next steps:"
echo "  1. Open the project in Xcode and let it set up signing."
echo "  2. Verify keys are visible:"
echo "     ls -la $LOCAL_LINK"
