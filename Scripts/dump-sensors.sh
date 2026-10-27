#!/bin/sh
# Prints this Mac's model, fans and every temperature key the SMC exposes.
# Attach the output to a model support issue (see docs/supported-models.md).
set -eu
cd "$(dirname "$0")/../Packages/FanKit"
swift build --product smc-dump >&2
"$(swift build --show-bin-path)/smc-dump"
