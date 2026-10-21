#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/docc"
SITE_DIR="$BUILD_DIR/site"
COMBINED_ARCHIVE="$BUILD_DIR/ApiKit.doccarchive"

if [[ -v DOCC_HOSTING_BASE_PATH ]]; then
  HOSTING_BASE_PATH="$DOCC_HOSTING_BASE_PATH"
elif [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  HOSTING_BASE_PATH="${GITHUB_REPOSITORY#*/}"
else
  HOSTING_BASE_PATH="$(basename "$ROOT_DIR")"
fi

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR"
# Only replace generated artifacts; keep DerivedData and package downloads cached.
rm -rf "$COMBINED_ARCHIVE" "$SITE_DIR"

SCHEMES=(ApiKit ApiKit-OAuth ApiKit-Google)
MODULES=(ApiKit ApiKit_OAuth ApiKit_Google)
ARCHIVES=()

for INDEX in {1..3}; do
  SCHEME="${SCHEMES[$INDEX]}"
  MODULE="${MODULES[$INDEX]}"
  echo "Building documentation for $SCHEME"

  xcodebuild docbuild \
    -quiet \
    -scheme "$SCHEME" \
    -derivedDataPath "$BUILD_DIR/derived-data" \
    -destination 'generic/platform=iOS' \
    OTHER_DOCC_FLAGS="--warnings-as-errors"

  ARCHIVE_PATH="$(find "$BUILD_DIR/derived-data/Build/Products" -type d \( -name "$SCHEME.doccarchive" -o -name "$MODULE.doccarchive" \) -print -quit)"
  if [[ -z "$ARCHIVE_PATH" ]]; then
    echo "Failed to locate DocC archive for $MODULE" >&2
    exit 1
  fi
  ARCHIVES+=("$ARCHIVE_PATH")
done

xcrun docc merge \
  "${ARCHIVES[@]}" \
  --output-path "$COMBINED_ARCHIVE" \
  --synthesized-landing-page-name "ApiKit" \
  --synthesized-landing-page-kind "Package" \
  --synthesized-landing-page-topics-style detailedGrid

HOSTING_ARGUMENTS=()
if [[ -n "$HOSTING_BASE_PATH" ]]; then
  HOSTING_ARGUMENTS=(--hosting-base-path "$HOSTING_BASE_PATH")
fi

xcrun docc process-archive transform-for-static-hosting \
  "$COMBINED_ARCHIVE" \
  --output-path "$SITE_DIR" \
  "${HOSTING_ARGUMENTS[@]}"

if ! grep -q '"type"[[:space:]]*:[[:space:]]*"image"' "$SITE_DIR/data/documentation.json"; then
  echo "Merged DocC landing page is missing image resources" >&2
  exit 1
fi

touch "$SITE_DIR/.nojekyll"
echo "DocC site generated at $SITE_DIR"
