# Claude Code Usage Monitor for macOS

<p align="center">
  <img width="463" height="628" alt="スクリーンショット 2025-07-16 20 23 14" src="https://github.com/user-attachments/assets/b6be05bd-09f1-40f8-a8d8-fc413f79f9e4"/>
</p>

A native macOS menu bar application that monitors Claude Code token usage in real-time.

This is a Swift/macOS adaptation of [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) by Maciek-roboblog, adding a native GUI for macOS users.

## Features

- Real-time token usage monitoring (updates every 6 seconds)
- Color-coded progress bars (green/yellow/red)
- Burn rate tracking with visual indicators
- Smart predictions for token depletion
- Automatic plan detection (Pro/Max5/Max20)
- Native macOS menu bar integration

## Installation

```bash
# Clone and build
git clone https://github.com/Sapeet/claude-code-usage-monitor-macos.git
cd claude-code-usage-monitor-macos

# Build and create app bundle
make bundle

# Copy to Applications
cp -r "output/Claude Code Usage Monitor.app" /Applications/
```

## Build Commands

```bash
make              # Build universal binary
make bundle       # Create .app bundle
make dist         # Create distribution ZIP
make clean        # Clean build artifacts

# For distribution (requires Developer ID certificate)
make dist-signed DEVELOPER_ID="Developer ID Application: Your Name (XXXXXXXXXX)" \
                 APPLE_ID=your@email.com \
                 TEAM_ID=XXXXXXXXXX
```

## How It Works

The app monitors Claude Code usage by reading JSONL files from:
- `~/.claude/projects/*.jsonl` (default)
- Or paths in `CLAUDE_DATA_PATHS` environment variable

It tracks:
- Token usage in 5-hour session windows
- Burn rate from the last hour
- Time until token depletion
- Session reset times

## UI Overview

**Menu Bar**: Shows usage percentage and burn rate emoji

**Popover**: Displays detailed information including:
- Token usage progress bar
- Current burn rate with emoji indicator
- Predictions and warnings
- Session timing information

## Burn Rate Indicators

- 🐌 < 100 tokens/min
- 🚶 100-300 tokens/min
- 🏃 300-600 tokens/min
- 🚗 600-1000 tokens/min
- ✈️ 1000-2000 tokens/min
- 🚀 > 2000 tokens/min

## Requirements

- macOS 13.0+
- Swift 5.9+
- Active Claude Code usage

## Credits

This project is inspired by and based on [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) by Maciek-roboblog. The original Python implementation provided the foundation for token tracking logic and usage calculations.

## License

MIT License