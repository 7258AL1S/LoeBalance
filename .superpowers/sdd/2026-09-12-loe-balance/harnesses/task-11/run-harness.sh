#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../../../../" && pwd)
HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

# Keep this check bounded in restricted Command Line Tools environments. The
# package build remains the authoritative compiler check when SwiftPM works.
perl -e 'alarm 20; exec @ARGV' sh "$HARNESS_DIR/Task11StaticCheck.sh" "$ROOT"
