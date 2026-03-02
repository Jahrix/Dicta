#!/usr/bin/env bash
set -euo pipefail

SPARKLE_VERSION="${1:-2.9.0}"
DESTINATION="${2:-$PWD/.sparkle-tools/$SPARKLE_VERSION}"
ARCHIVE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"

mkdir -p "$DESTINATION"

if [[ ! -x "$DESTINATION/bin/sign_update" || ! -x "$DESTINATION/bin/generate_appcast" ]]; then
  ARCHIVE_PATH="$DESTINATION/Sparkle-for-Swift-Package-Manager.zip"
  curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"
  unzip -oq "$ARCHIVE_PATH" -d "$DESTINATION"
fi

printf '%s\n' "$DESTINATION"
