# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a native macOS menu bar application that monitors Claude Code token usage in real-time. It's written in Swift using SwiftUI and AppKit frameworks. The application displays token usage statistics, burn rate, and predictions in the macOS menu bar.

This project is a Swift/macOS adaptation of the original [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) by Maciek-roboblog. The core token tracking logic and usage calculation algorithms are based on their implementation. This macOS version would not exist without their pioneering work.

Repository: `claude-code-usage-monitor-macos`
App Name: `Claude Code Usage Monitor`

## Project Structure

The repository structure:

- **`src/`** - Source code directory containing all Swift files
- **`output/`** - Build output directory (generated)
- **`Makefile`** - Build automation and all build logic
- **`Package.swift`** - Swift Package Manager configuration
- **`Info.plist`** - macOS application metadata

### Core Components

- **`main.swift`** - Application entry point
- **`AppDelegate.swift`** - macOS app lifecycle management and menu bar setup  
- **`ClaudeUsageMonitor.swift`** - Core business logic for token tracking and calculations
- **`ClaudeDataLoader.swift`** - Performance-optimized data loader with:
  - Cached ISO8601DateFormatter instances
  - Memory-mapped file I/O
  - Concurrent file processing with TaskGroup
  - 24-hour mtime filtering to skip old files
  - Byte-level line processing
- **`ContentView.swift`** - SwiftUI view for the popover UI

### Data Flow

1. The app reads usage data from `~/.claude/projects/*.jsonl` files
2. Files older than 24 hours are automatically skipped for performance
3. `ClaudeDataLoader` parses JSONL entries with concurrent processing
4. `ClaudeUsageMonitor` calculates session windows, burn rates, and predictions
5. UI updates every 6 seconds with current usage statistics

### Key Concepts

- **Session Windows**: Claude uses 5-hour rolling windows for token limits
- **Token Weighting**: Opus models use a 5x multiplier, Sonnet models use 1x
- **Burn Rate**: Calculated from the last hour of usage across all sessions
- **Plan Detection**: Automatically detects Pro/Max5/Max20 plans from historical usage

## Build System

This project uses a Makefile for all build operations. Available targets:

```bash
# Build universal binary (x86_64 + arm64)
make build

# Create .app bundle
make bundle

# Create unsigned distribution ZIP (for developers)
make dist

# Sign app for local testing
make sign DEVELOPER_ID="Developer ID Application: Your Name (XXXXXXXXXX)"

# Notarize app (adds staple)
make notarize DEVELOPER_ID="Developer ID Application: Your Name (XXXXXXXXXX)" APPLE_ID=your@email.com TEAM_ID=YOUR_TEAM_ID

# Create signed distribution ZIP (for end users)
make dist-signed DEVELOPER_ID="Developer ID Application: Your Name (XXXXXXXXXX)" APPLE_ID=your@email.com TEAM_ID=YOUR_TEAM_ID

# Clean build artifacts
make clean
```

### Quick Start

```bash
# Build and create app bundle
make bundle

# The app will be at: output/Claude Code Usage Monitor.app
# You can:
# - Double-click to run
# - Copy to /Applications
# - Add to Login Items
```

### Distribution

```bash
# Create signed distribution package
make sign DEVELOPER_ID="Developer ID Application: Your Name (XXXXXXXXXX)"

# Or create unsigned distribution ZIP
make dist
```

## Recent Performance Optimizations

The codebase has undergone dramatic performance improvements, reducing startup time from 11 seconds to under 2 seconds:

1. **ISO8601DateFormatter Caching** - Eliminates 77% of processing time by reusing formatter instances
2. **Memory-Mapped File I/O** - Uses `.mappedIfSafe` option for efficient large file handling
3. **Concurrent Processing** - TaskGroup parallelizes file loading across CPU cores
4. **mtime-based Filtering** - Skips files older than 24 hours, reducing file scans by 80-90%
5. **Byte-Level Processing** - Avoids string conversion overhead by processing at Data level
6. **Efficient Directory Traversal** - Uses FileManager.enumerator instead of multiple directory scans

When modifying the data loading logic, ensure these optimizations are maintained.

## Testing Approach

When adding tests, create test files in the appropriate directory and ensure they validate the performance optimizations.

## Platform Requirements

- macOS 13.0+
- Swift 5.9+
- Xcode 15.0+ (for development)

## Environment Variables

- `CLAUDE_DATA_PATHS` or `CLAUDE_DATA_PATH` - Override default Claude data directory locations
- Default location: `~/.claude/projects/*.jsonl`

## App Bundle Creation

The `make bundle` command creates a proper macOS application bundle:
1. Builds the release version with universal binary support (x86_64 + arm64)
2. Creates the bundle directory structure in `output/`
3. Copies executable and Info.plist
4. Signs the app with ad-hoc signature for local use

The resulting `.app` can be distributed or installed in `/Applications`.

For Developer ID signing (required for distribution outside the App Store):
- Use `make sign` - requires a valid Developer ID certificate
- All signing logic is integrated directly in the Makefile

## Developer ID Distribution

If you have an Apple Developer Program membership ($99/year):

1. **Get Developer ID Certificate**:
   - Open Xcode > Settings > Accounts
   - Select your Apple ID > Manage Certificates
   - Click '+' > Developer ID Application

2. **Build and Sign**:
   ```bash
   # Sign with Developer ID
   make sign DEVELOPER_ID="Developer ID Application: Your Name (XXXXXXXXXX)"
   ```
   
   This signs the app bundle for local testing.

3. **Notarize and Create Distribution Package**:
   ```bash
   # Complete distribution build
   make dist-signed DEVELOPER_ID="Developer ID Application: Your Name (XXXXXXXXXX)" APPLE_ID=your@email.com TEAM_ID=YOUR_TEAM_ID
   ```
   
   This will:
   - Sign the app (if not already signed)
   - Submit for notarization
   - Wait for Apple's approval
   - Staple the ticket to the app
   - Create final distribution ZIP: `output/Claude Code Usage Monitor.zip`

