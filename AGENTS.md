# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

# Leader Key Development Guide

## Build & Test Commands

- Build and run: `xcodebuild -scheme "Leader Key" -configuration Debug build`
- Run all tests: `xcodebuild -scheme "Leader Key" -testPlan "TestPlan" test`
- Run single test: `xcodebuild -scheme "Leader Key" -testPlan "TestPlan" -only-testing:Leader KeyTests/UserConfigTests/testInitializesWithDefaults test`
- Bump version: `bin/bump`
- Create release: `bin/release`

## Architecture Overview

Leader Key is a macOS application that provides customizable keyboard shortcuts. The core architecture consists of:

**Key Components:**

- `AppDelegate`: Application lifecycle, global shortcuts registration, update management
- `Controller`: Central event handling, manages key sequences and window display
- `UserConfig`: JSON configuration management with validation
- `UserState`: Tracks navigation through key sequences
- `MainWindow`: Base class for theme windows

**Theme System:**

- Themes inherit from `MainWindow` and implement `draw()` method
- Available themes: MysteryBox, Mini, Breadcrumbs, ForTheHorde, Cheater
- Each theme provides different visual representations of shortcuts

**Caps Lock Trigger (`Leader Key/Trigger/`):**

Optional, off by default, and independent of the `KeyboardShortcuts` path.
Three layers stacked on each other:

- `CapsLockRemap` points the physical Caps Lock at a function key (F18 by
  default) by writing `UserKeyMapping` on an IOHIDEventSystemClient. This must
  happen first: macOS debounces the real Caps Lock in the HID layer by ~80ms
  and sends no key repeats for it, which makes tap-versus-hold timing
  unusable. The property is client-level, not per-service, and it outlives the
  process, so `TriggerManager.stop()` has to hand it back.
- `HyperTap` runs a `CGEventTap` on its own thread and swallows the trigger
  key outright, so there is nothing to replay and no rollover to resolve. A
  chord becomes Hyper (⌃⌥⇧⌘ merged into the event), a lone hold opens the
  panel, a quick release is a tap.
- `TriggerManager` owns both, watches the relevant `Defaults` keys, and
  re-applies after wake.

`HIDEventSystem` holds the `@_silgen_name` bindings for the private IOKit HID
symbols. `CapsLockState` flips the real Caps Lock through the service-level
`HIDCapsLockState` property; `IOHIDSetModifierLockState` reads fine but its
writes are ignored, so do not reach for it.

Needs Accessibility for the tap, and the app cannot be sandboxed.

**Configuration Flow:**

- Config stored at `~/Library/Application Support/Leader Key/config.json`
- `FileMonitor` watches for changes and triggers reload
- `ConfigValidator` ensures no key conflicts
- Actions support: applications, URLs, commands, folders

**Testing Architecture:**

- Uses XCTest with custom `TestAlertManager` for UI testing
- Tests use isolated UserDefaults and temporary directories
- Focus on configuration validation and state management

## Code Style Guidelines

- **Imports**: Group Foundation/AppKit imports first, then third-party libraries (Combine, Defaults)
- **Naming**: Use descriptive camelCase for variables/functions, PascalCase for types
- **Types**: Use explicit type annotations for public properties and parameters
- **Error Handling**: Use appropriate error handling with do/catch blocks and alerts
- **Extensions**: Create extensions for additional functionality on existing types
- **State Management**: Use @Published and ObservableObject for reactive UI updates
- **Testing**: Create separate test cases with descriptive names, use XCTAssert\* methods
- **Access Control**: Use appropriate access modifiers (private, fileprivate, internal)
- **Documentation**: Use comments for complex logic or non-obvious implementations

Follow Swift idioms and default formatting (4-space indentation, spaces around operators).

