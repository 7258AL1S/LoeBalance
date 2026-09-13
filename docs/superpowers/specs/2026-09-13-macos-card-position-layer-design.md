# macOS Card Position and Layer Design

## Goal

Add user-configurable placement and window layering to the macOS desktop balance card while leaving all Windows sources and behavior unchanged.

## Behavior

- `CardPositionPreset` provides `topLeft`, `bottomLeft`, `topRight`, `bottomRight`, and `custom`.
- Presets use the selected screen's visible frame with a 24-point inset and are clamped when the work area is smaller than the card.
- `custom` restores and persists the card's `NSWindow` frame. Only custom mode enables dragging by the window background.
- Existing preferences with a saved `desktopFrame` but no new position key migrate to `custom`; older preferences without a frame migrate to bottom-right.
- `CardLayer` provides three persisted values: below desktop icons, between desktop icons and applications, and above applications.
- The settings UI uses a three-step slider. Changes are persisted and applied to the live card immediately.

## Window-layer boundary

The first two values use Core Graphics desktop/icon window levels bounded below normal application windows. The third uses AppKit's floating level. Full-screen and system-protected windows may still supersede the card; this is documented rather than presenting an absolute guarantee.

## Components

- `Core/Models.swift`: Codable enums and display titles.
- `Persistence/PreferencesStore.swift`: persisted values and legacy migration.
- `DesktopCard/DesktopCardController.swift`: frame calculation, drag policy, screen changes, and level mapping.
- `Settings/SettingsViewModel.swift`: transactional persistence and coordinator callbacks.
- `Settings/SettingsView.swift`: position picker, custom hint, and layer slider.
- `App/AppCoordinator.swift`: applies settings to the live card.

## Testing

Add coverage for JSON round trips and legacy migration, all four corner frames, custom/preset drag policy, distinct ordered window levels, settings callbacks, and coordinator propagation. Run `swift build` for the app and `swift test` where XCTest is available.

## Release

Version 0.3.0 publishes newly built macOS arm64 and x86_64 packages. Windows installers are copied unchanged from the v0.2.0 release and are not rebuilt or modified.
