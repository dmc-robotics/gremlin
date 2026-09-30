# Gremlin - Project Instructions

## Overview

Native macOS serial monitor/plotter and a project dashboard that builds and loads Arduino sketches with the grot gem (source: `~/code/robotics/grot`). Single user; deployment target macOS 26.0 (the installed Xcode 26.2 can't target 27).

- **Projects** page: cards for Arduino project directories (containing `<dir>.ino` and `.grotconfig`), Build/Load via grot, Config/Sketch/Port status badges, port scanning that rewrites `.grotconfig`, and a resizable output panel.
- **Serial Monitor** page: port/baud/connect in the toolbar, Monitor/Plotter tabs, Raw mode, protocol help, save/clear, send field.
- **Settings** window (⌘,): terminal and editor app pickers, versions.

## Tech Stack

- Swift 6 (strict concurrency), SwiftUI, Swift Charts, Observation (`@Observable`)
- Swift Testing (`import Testing`) for all tests
- XcodeGen: `project.yml` generates `Gremlin.xcodeproj` (gitignored; never edit the project directly)
- No third-party dependencies. Serial I/O is IOKit + POSIX. Ask before adding any package.

## Structure

- `GremlinKit/`: local Swift package with all non-UI logic; no SwiftUI imports
  - `Serial/`: line parser, rolling buffer, port info and heuristics, IOKit discovery, POSIX `SerialConnection`
  - `Projects/`: models, `.grotconfig` parser, `projects.json` store, inspector, FSEvents watcher
  - `Grot/`: process runner, login-shell PATH, `GrotRunner`
  - `Output/`: ANSI escape parser
- `Gremlin/`: app target
  - `Models/`: `@MainActor @Observable` models (`ProjectsModel`, `SerialModel`) injected with `.environment`
  - `Views/`: SwiftUI views per page
  - `Support/`: AppKit bridges (`AppLauncher`, ANSI → `AttributedString`)
  - `Constants.swift`: sizes, baud rates, preference keys. Use constants for magic numbers
  - `Assets.xcassets/AppIcon.appiconset`: app icon, exported from `Design/Gremlin Logo.pxd`. Use full-bleed square artwork; macOS 26 applies its own mask and frames pre-masked icons in a grey border
- `Design/Gremlin Logo.pxd`: Pixelmator Pro source for the app icon
- `GremlinTests/`: model tests with fakes (`Fakes.swift`)

## Conventions

- Keep logic in GremlinKit and test it there. Views should stay thin.
- Side effects go through protocols (`GrotRunning`, `SerialPortListing`, `SerialConnecting`) so models can be tested with fakes.
- Follow the system appearance and accent color. Use semantic colors (`.primary`, `.secondary`, `.red`, `.tint`), not custom palettes.
- Standard macOS patterns: toolbar controls, `ContentUnavailableView` for empty states, `.help()` tooltips, sheets for forms, `confirmationDialog` for destructive actions.
- Settings use `@AppStorage` with keys in `Preferences`.
- **Git:** the user handles all git operations (commits, branches, merges, tags, pushes). Only run git commands that change the repository when explicitly asked.
- **Commit messages** (only for commits the user asks for): one short line ending with the model name in parentheses, e.g. `Fix port scan timeout (Opus 5.5)`. No Co-Authored-By trailer.

## Commands

Xcode isn't the active developer directory (`xcode-select` points at the Command Line Tools), so prefix builds with `DEVELOPER_DIR`:

```zsh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate                                   # after adding/removing files or editing project.yml
(cd GremlinKit && swift test)                       # package tests
xcodebuild -project Gremlin.xcodeproj -scheme Gremlin -derivedDataPath build test   # app tests
xcodebuild -project Gremlin.xcodeproj -scheme Gremlin -derivedDataPath build build  # → build/Build/Products/Debug/Gremlin.app
```

## Notes

- Not sandboxed: needs `/dev/cu.*`, arbitrary project folders, and to launch grot. Signed to run locally.
- grot is found using the PATH from the user's login shell (`ShellEnvironment`), because GUI apps don't inherit it. The lookup runs once, off the main thread, on first use; relative PATH entries are dropped so a project folder can never supply its own `grot`. grot runs with `CLICOLOR_FORCE=1` so the output panel keeps its colors.
- Untrusted input is bounded: serial lines are capped at 4 KB (`LineFramer`), plotter series at 32, the output log at 200 entries. `GrotConfigParser.writePort` only writes `/dev/…` paths and refuses a symlinked `.grotconfig`.
- Projects are stored in `~/Library/Application Support/Gremlin/projects.json`.
- Serial ports are opened by callout path (`/dev/cu.*`) with exclusive access. Rates above 230400 use `IOSSIOSPEED`.
- Pty-based tests can't cover exclusive access, custom baud rates, or DTR reset. Check those on real hardware.
- `TestSketch/gremlin_test/` is a Teensy 4.1 sketch for manual end-to-end testing (see README). The Arduino toolchains on this Mac are Intel binaries, so compiling needs Rosetta.
