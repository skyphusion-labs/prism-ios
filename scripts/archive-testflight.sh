#!/usr/bin/env bash
# Build an App Store archive of Prism for TestFlight upload.
# Requires: Xcode + personal Apple Developer Program signing
#   Team ID 858878N47M (individual membership; not an org "skyphusion" team).
#   DEVELOPMENT_TEAM is set in project.yml to the same value.
#
# Usage:
#   ./scripts/archive-testflight.sh
#   ./scripts/archive-testflight.sh --export   # also export IPA when profiles allow
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Xcode IPA packaging runs `/usr/bin/rsync -E` (Apple openrsync extended attrs).
# If Homebrew GNU rsync (3.x) is first on PATH, the rsync "server" side rejects
# --extended-attributes → IDEFoundation "Copy failed". Keep system rsync first.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"
if command -v rsync >/dev/null 2>&1; then
  _rsync_ver="$(rsync --version 2>&1 | head -1 || true)"
  if echo "$_rsync_ver" | grep -qi 'samba\|version 3\.'; then
    echo "error: PATH still resolves to GNU rsync ($_rsync_ver)." >&2
    echo "  brew unlink rsync   # or rename /opt/homebrew/bin/rsync" >&2
    echo "  then relaunch Xcode / re-run this script" >&2
    exit 1
  fi
fi

ARCHIVE_DIR="${ARCHIVE_DIR:-$ROOT/build/archives}"
EXPORT_DIR="${EXPORT_DIR:-$ROOT/build/export}"
SCHEME="Prism"
ARCHIVE_PATH="$ARCHIVE_DIR/Prism.xcarchive"
DO_EXPORT=0

for arg in "$@"; do
  case "$arg" in
    --export) DO_EXPORT=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
  esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found (brew install xcodegen)" >&2
  exit 1
fi

echo "==> xcodegen generate"
xcodegen generate

mkdir -p "$ARCHIVE_DIR"

echo "==> archive $SCHEME → $ARCHIVE_PATH"
# Automatic signing under personal Team 858878N47M (project.yml DEVELOPMENT_TEAM).
xcrun xcodebuild \
  -scheme "$SCHEME" \
  -project Prism.xcodeproj \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM=858878N47M \
  CODE_SIGN_STYLE=Automatic \
  archive

echo "Archive ready: $ARCHIVE_PATH"
echo "Upload: Xcode Organizer → Distribute App → App Store Connect → TestFlight"
echo "  or:  xcrun altool --upload-app ... (legacy)"
echo "  or:  xcrun notary / transporter / asc when available"

if [[ "$DO_EXPORT" -eq 1 ]]; then
  mkdir -p "$EXPORT_DIR"
  EXPORT_OPTS="$EXPORT_DIR/ExportOptions.plist"
  if [[ ! -f "$EXPORT_OPTS" ]]; then
    cat > "$EXPORT_OPTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>858878N47M</string>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST
    echo "Wrote $EXPORT_OPTS (edit if your org requires manual profiles)"
  fi
  echo "==> export archive"
  xcrun xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTS" \
    -exportPath "$EXPORT_DIR"
  echo "Export output: $EXPORT_DIR"
fi

echo "Done."
