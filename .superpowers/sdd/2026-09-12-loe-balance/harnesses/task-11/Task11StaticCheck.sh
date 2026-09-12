#!/bin/sh
set -eu
ROOT=${1:?worktree root required}

require_file() {
    test -f "$1" || { printf 'FAIL: missing %s\n' "$1" >&2; exit 1; }
}

require_pattern() {
    file=$1
    pattern=$2
    label=$3
    rg -q --fixed-strings "$pattern" "$file" || {
        printf 'FAIL: %s (%s)\n' "$label" "$file" >&2
        exit 1
    }
}

APP="$ROOT/Sources/LoeBalance/App"
COORDINATOR="$APP/AppCoordinator.swift"
DELEGATE="$APP/AppDelegate.swift"
MAIN="$APP/main.swift"
LOGGER="$ROOT/Sources/LoeBalance/Support/Logger.swift"
TESTS="$ROOT/Tests/LoeBalanceTests/AppCoordinatorTests.swift"

for file in "$COORDINATOR" "$DELEGATE" "$MAIN" "$LOGGER" "$TESTS"; do
    require_file "$file"
done

require_pattern "$COORDINATOR" 'func start() async' 'coordinator start'
require_pattern "$COORDINATOR" 'func handleRefreshResult(_ result: RefreshResult)' 'refresh result transition'
require_pattern "$COORDINATOR" 'func refreshNow()' 'manual refresh transition'
require_pattern "$COORDINATOR" 'func openSettings()' 'settings transition'
require_pattern "$COORDINATOR" 'func toggleDesktopCard()' 'desktop-card transition'
require_pattern "$COORDINATOR" 'func logout() async' 'logout transition'
require_pattern "$COORDINATOR" 'func applicationDidWake()' 'wake transition'
require_pattern "$COORDINATOR" 'let authentication: any CoordinatorAuthenticating' 'injectable authentication'
require_pattern "$COORDINATOR" 'let scheduler: any RefreshScheduling' 'injectable scheduler'
require_pattern "$COORDINATOR" 'let desktopCard: any DesktopCardPresenting' 'injectable desktop surface'
require_pattern "$COORDINATOR" 'let statusBar: any StatusBarPresenting' 'injectable status surface'

card_present=$(rg -n 'desktopCard\.present\(snapshot:' "$COORDINATOR" | head -1 | cut -d: -f1)
status_present=$(rg -n 'statusBar\.present\(' "$COORDINATOR" | head -1 | cut -d: -f1)
card_play=$(rg -n 'desktopCard\.play\(' "$COORDINATOR" | head -1 | cut -d: -f1)
status_play=$(rg -n 'statusBar\.play\(' "$COORDINATOR" | head -1 | cut -d: -f1)
test "$card_present" -lt "$card_play" || { printf 'FAIL: desktop snapshot must precede animation\n' >&2; exit 1; }
test "$status_present" -lt "$status_play" || { printf 'FAIL: status snapshot must precede animation\n' >&2; exit 1; }

require_pattern "$DELEGATE" 'NSWorkspace.didWakeNotification' 'wake observer'
require_pattern "$DELEGATE" 'coordinator.stopForTermination()' 'termination cleanup'
require_pattern "$MAIN" 'application.setActivationPolicy(.accessory)' 'accessory activation'
require_pattern "$LOGGER" 'category: "auth"' 'auth logger category'
require_pattern "$LOGGER" 'category: "api"' 'api logger category'
require_pattern "$LOGGER" 'category: "refresh"' 'refresh logger category'
require_pattern "$LOGGER" 'category: "desktop"' 'desktop logger category'
require_pattern "$LOGGER" 'category: "status"' 'status logger category'

if rg -n 'accessToken|refreshToken|password|httpBody|response body' "$COORDINATOR" "$LOGGER"; then
    printf 'FAIL: secret/body logging marker found\n' >&2
    exit 1
fi

require_pattern "$TESTS" 'testMissingSessionOpensLoginAndDoesNotStartScheduler' 'missing-session test'
require_pattern "$TESTS" 'testRestoredSessionStartsSchedulerForBaselineRefresh' 'restore test'
require_pattern "$TESTS" 'testSuccessfulRefreshPresentsBothSurfacesBeforeAnimations' 'ordered presentation test'
require_pattern "$TESTS" 'testLogoutStopsClearsHidesAndOpensLogin' 'logout test'
require_pattern "$TESTS" 'testWakeAndNetworkRecoveryRequestImmediateRefresh' 'recovery test'

printf '%s\n' 'task-11 static harness passed: composition root, lifecycle transitions, ordered presentation, logging categories, and coordinator tests'
