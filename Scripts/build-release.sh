#!/bin/sh
# Builds the downloadable app into dist/: FanController-<version>.zip and its SHA-256 checksum.
# Run by semantic-release after Scripts/set-version.sh; also works locally.
#
# The build is ad-hoc signed, without a team, whatever Config/Signing.xcconfig says, so every release is
# built the same way. Such a build reads sensors but can't control fans: the helper only accepts an app
# signed by its own team (see docs/security.md).
set -eu
cd "$(dirname "$0")/.."

version="$(sed -n 's/^MARKETING_VERSION = //p' Config/Base.xcconfig)"
derived_data="build/DerivedData"
app="$derived_data/Build/Products/Release/FanController.app"
archive="dist/FanController-$version.zip"

rm -rf "$derived_data" dist
mkdir -p dist

xcodebuild \
    -project FanController.xcodeproj \
    -scheme FanController \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data" \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    build | grep -E '^(\*\*|error:|.*: error:)' || true
[ -d "$app" ] || { echo "Build failed: $app not found" >&2; exit 1; }

codesign --verify --deep --strict "$app"
# ditto keeps the bundle's signature and extended attributes intact, unlike zip.
ditto -c -k --keepParent "$app" "$archive"
(cd dist && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "Built $archive"
cat "$archive.sha256"
