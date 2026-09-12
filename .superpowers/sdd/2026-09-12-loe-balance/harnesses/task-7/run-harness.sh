#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../../../../" && pwd)
OUT=$(mktemp "${TMPDIR:-/tmp}/loe-task-7-harness.XXXXXX")
trap 'rm -f "$OUT"' EXIT
swiftc -warnings-as-errors -parse-as-library \
  "$ROOT/Sources/LoeBalance/Core/Money.swift" \
  "$ROOT/Sources/LoeBalance/Core/Models.swift" \
  "$ROOT/Sources/LoeBalance/Animation/DamageAnimationPlanner.swift" \
  "$ROOT/Sources/LoeBalance/Animation/DamageStreamView.swift" \
  "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/Task7Harness.swift" \
  -o "$OUT"
"$OUT"
