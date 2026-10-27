#!/bin/sh
# Builds the downloadable app into dist/: FanController-<version>.dmg and its SHA-256 checksum.
# Run by semantic-release after Scripts/set-version.sh, with the full version (0.2.0-beta.1) for the file
# name; also works locally, where it falls back to MARKETING_VERSION.
#
# The build is ad-hoc signed, without a team, whatever Config/Signing.xcconfig says, so every release is
# built the same way. Such a build reads sensors but can't control fans: the helper only accepts an app
# signed by its own team (see docs/security.md).
set -eu
cd "$(dirname "$0")/.."

version="${1:-$(sed -n 's/^MARKETING_VERSION = //p' Config/Base.xcconfig)}"
derived_data="build/DerivedData"
app="$derived_data/Build/Products/Release/Fan Controller.app"
archive="dist/FanController-$version.dmg"
staging="build/dmg"

rm -rf "$derived_data" "$staging" dist
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
# Xcode before 26 copies the Icon Composer document as is and the app ships without an icon.
/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$app/Contents/Info.plist" >/dev/null 2>&1 ||
    { echo "Build has no app icon: build with Xcode 26 or later" >&2; exit 1; }
# The disk image opens to the app next to a link to Applications, to drag it across. ditto keeps the
# bundle's signature and extended attributes intact.
mkdir -p "$staging"
ditto "$app" "$staging/Fan Controller.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "Fan Controller" -srcfolder "$staging" -fs HFS+ -format UDZO "$archive"
rm -rf "$staging"
(cd dist && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "Built $archive"
cat "$archive.sha256"
