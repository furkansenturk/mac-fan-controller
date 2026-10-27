#!/bin/sh
# Sets the app's version, e.g. Scripts/set-version.sh 0.2.0. Run by semantic-release before each release.
#
# CFBundleVersion is set to the same value: the app compares it with the installed helper's to decide when
# the helper must restart, so it has to change with every release.
set -eu
version="$1"
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Not a version: $version" >&2; exit 1; }

config="$(dirname "$0")/../Config/Base.xcconfig"
sed -i '' \
    -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $version/" \
    -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $version/" \
    "$config"
grep -E '^(MARKETING_VERSION|CURRENT_PROJECT_VERSION) = ' "$config"
