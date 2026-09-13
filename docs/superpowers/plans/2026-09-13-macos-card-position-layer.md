# macOS Card Position and Layer Implementation Plan

**Goal:** Add configurable macOS card placement and layering, then release macOS 0.3.0 while reusing Windows 0.2.0 installers.

**Constraints:** Modify only macOS sources, macOS tests, release documentation/workflow, and shared metadata required for the release. Do not modify files under `windows/`.

## 1. Model and persistence

- [x] Add `CardPositionPreset` and `CardLayer` Codable enums.
- [x] Add both values to `AppPreferences`.
- [x] Migrate legacy saved frames to custom placement.
- [x] Add persistence and migration tests.

## 2. Desktop card behavior

- [x] Calculate four visible-frame corner positions.
- [x] Enable dragging only for custom placement.
- [x] Persist custom moves and reposition presets on selection/screen change.
- [x] Map the three layer values to distinct AppKit levels.
- [x] Add controller behavior tests.

## 3. Settings and coordinator

- [x] Add position picker and custom-mode hint.
- [x] Add three-step layer slider.
- [x] Propagate settings to the live card through `AppCoordinator`.
- [x] Add view-model and coordinator tests.

## 4. Release

- [x] Run macOS source build and attempt the XCTest suite; record the local XCTest toolchain limitation.
- [x] Update 0.3.0 release notes and release workflow.
- [x] Build macOS arm64 and x86_64 packages.
- [x] Verify the Windows v0.2.0 installers and checksums for reuse.
- [x] Publish v0.3.0 and verify its eight assets.
