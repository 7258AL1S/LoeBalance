#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../../../../" && pwd)
OUT=$(mktemp "${TMPDIR:-/tmp}/loe-task-6-harness.XXXXXX")
trap 'rm -f "$OUT"' EXIT
swiftc -parse-as-library \
  "$ROOT/Sources/LoeBalance/Refresh/RefreshScheduler.swift" \
  "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/Task6Harness.swift" \
  -o "$OUT"
"$OUT"
