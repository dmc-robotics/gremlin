# Gremlin

A native macOS serial monitor, plotter and Arduino project dashboard. It builds and loads sketches with `grot`.

## Features

- **Projects**: add Arduino project directories and see board, core, port and baud from `.grotconfig`. Status badges show config validity (`grot validate`), whether the sketch exists and whether the port is connected. Build and Load run grot, and the output panel shows the colored results. Clicking the Port badge finds your Arduino and updates `.grotconfig`. Changes made to files on disk appear automatically.
- **Serial Monitor**: connect from the toolbar, view timestamped and color-coded lines or raw output, plot `key:value` data, send commands, and save or clear the log.
- **Settings** (⌘,): choose the terminal and editor apps used to open project folders and files.

## Serial protocol

```
temp:25               data (plotted)
x:10,y:20,z:30        several values on one line
ERROR:message         also WARN, INFO, DEBUG — colored in the monitor
anything else         plain text
```

## Requirements

- macOS 26 or later, Xcode 26, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- `grot` on your login shell's PATH

## Build

```zsh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # if xcode-select points at the CLT
xcodegen generate
xcodebuild -project Gremlin.xcodeproj -scheme Gremlin -derivedDataPath build build
open build/Build/Products/Debug/Gremlin.app
```

Or run `xcodegen generate` and open `Gremlin.xcodeproj` in Xcode.

## Test

```zsh
(cd GremlinKit && swift test)
xcodebuild -project Gremlin.xcodeproj -scheme Gremlin -derivedDataPath build test
```

## App icon

The icon's source is `Design/Gremlin Logo.pxd` (Pixelmator Pro). To update it, export an `.icns`, then replace the PNGs in `Gremlin/Assets.xcassets/AppIcon.appiconset`:

```zsh
iconutil -c iconset "Gremlin Logo.icns" -o /tmp/Gremlin.iconset
cp /tmp/Gremlin.iconset/*.png Gremlin/Assets.xcassets/AppIcon.appiconset/
```

Keep the artwork full-bleed and square. macOS applies the rounded mask itself.

## Test sketch

`TestSketch/gremlin_test/` is a Teensy 4.1 sketch that exercises Gremlin. Add that folder as a project, then **Build** and **Load** it (press the Teensy's program button when loading). Connect in the Serial Monitor.

The sketch streams `sine`, `cosine` and `ramp` data at 20 Hz for the plotter, plus a `DEBUG:` heartbeat every 5 s. Type `help` in the send field for commands that exercise specific cases:

| Command | Checks |
|---|---|
| `levels` | Log-level colors; lowercase `error:` stays plain text |
| `burst [n]` | 500-line buffer trimming and UI responsiveness (default 600 lines) |
| `rate <hz>` | Throughput, 1–2000 samples/s |
| `gap` / `slow` | Plotter gaps and series that start later |
| `malformed` | Near-miss lines that must not be plotted |
| `partial` | A line that arrives in pieces |
| `long`, `utf8`, `blank` | Long, non-ASCII and empty lines |
| `echo`, `ping`, `led on\|off` | The send field, including several commands in one send (Shift-Return) |
| `pause` / `resume`, `status` | Stream control |

Teensy USB serial ignores the baud rate and doesn't reset when the port opens. Use an Arduino board to check baud rates and DTR reset. Reflashing while connected disconnects the port, which exercises the "Connection lost" path.
