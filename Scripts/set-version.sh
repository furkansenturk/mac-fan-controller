#!/bin/sh
# Sets the app's version, e.g. Scripts/set-version.sh 0.2.0 or 0.2.0-beta.1. Run by semantic-release before
# each release.
#
# Bundle versions must be numbers, so a pre-release keeps 0.2.0 as its marketing version and becomes
# 0.2.0.1 as its CFBundleVersion. The app compares CFBundleVersion with the installed helper's to decide
# when the helper must restart, so it has to change with every release, pre-releases included.
set -eu
version="$1"
base="${version%%-*}"
echo "$base" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Not a version: $version" >&2; exit 1; }
if [ "$version" = "$base" ]; then
    build="$base"
else
    number="$(echo "$version" | sed -n 's/^[0-9.]*-beta\.\([0-9][0-9]*\)$/\1/p')"
    [ -n "$number" ] || { echo "Not a beta version: $version" >&2; exit 1; }
    build="$base.$number"
fi

config="$(dirname "$0")/../Config/Base.xcconfig"
sed -i '' \
    -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $base/" \
    -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $build/" \
    "$config"
grep -E '^(MARKETING_VERSION|CURRENT_PROJECT_VERSION) = ' "$config"
