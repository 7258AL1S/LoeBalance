#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../../../../" && pwd)
HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
OUT=$(mktemp "${TMPDIR:-/tmp}/loe-task-10-harness.XXXXXX")
trap 'rm -f "$OUT"' EXIT
swiftc -warnings-as-errors -parse-as-library \
  "$ROOT/Sources/LoeBalance/Core/Models.swift" \
  "$ROOT/Sources/LoeBalance/Core/Money.swift" \
  "$ROOT/Sources/LoeBalance/Networking/APIModels.swift" \
  "$ROOT/Sources/LoeBalance/Auth/CredentialStore.swift" \
  "$ROOT/Sources/LoeBalance/Auth/AuthManager.swift" \
  "$ROOT/Sources/LoeBalance/Persistence/PreferencesStore.swift" \
  "$ROOT/Sources/LoeBalance/Refresh/RefreshScheduler.swift" \
  "$ROOT/Sources/LoeBalance/Settings/LoginViewModel.swift" \
  "$ROOT/Sources/LoeBalance/Settings/LoginView.swift" \
  "$ROOT/Sources/LoeBalance/Settings/SettingsViewModel.swift" \
  "$ROOT/Sources/LoeBalance/Settings/SettingsView.swift" \
  "$ROOT/Sources/LoeBalance/Settings/SettingsWindowController.swift" \
  "$ROOT/Sources/LoeBalance/Support/LaunchAtLoginService.swift" \
  "$HARNESS_DIR/Task10Harness.swift" \
  -o "$OUT"
"$OUT"
