#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
APP_NAME="Dicta.app"

echo "Building ${APP_NAME} (Release)…"
/usr/bin/xcodebuild \
  -project "${ROOT_DIR}/Dicta.xcodeproj" \
  -scheme Dicta \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  build

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "Build output not found at ${APP_PATH}"
  exit 1
fi

DEST_DIR="/Applications"
if [[ ! -w "${DEST_DIR}" ]]; then
  DEST_DIR="${HOME}/Applications"
  mkdir -p "${DEST_DIR}"
fi

echo "Installing to ${DEST_DIR}/${APP_NAME}…"
/bin/rm -rf "${DEST_DIR}/${APP_NAME}"
/bin/cp -R "${APP_PATH}" "${DEST_DIR}/${APP_NAME}"

echo "Installed: ${DEST_DIR}/${APP_NAME}"
