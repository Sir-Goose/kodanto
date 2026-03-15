# kodanto

A native macOS frontend for [opencode](https://opencode.ai) - a SwiftUI-based GUI that talks directly to the opencode server protocol.

## Overview

kodanto provides a polished, native macOS interface for interacting with opencode AI. It launches your installed `opencode` binary directly and communicates via the server protocol, giving you a seamless chat experience with terminal integration, session management, and real-time synchronization.

## Features

- **Native macOS UI** - Built with SwiftUI for a polished, responsive experience
- **Chat Transcript** - Rich conversation view with markdown rendering and tool call visualization
- **Integrated Terminal** - Built-in terminal panel powered by WebSocket connection
- **Session Management** - Organize conversations with a sidebar session list
- **Live Sync** - Real-time synchronization between UI and opencode backend
- **Composer** - Rich text input with support for attachments and context
- **Workspace Awareness** - Understands your project context and file structure
- **Connection Manager** - Manage multiple opencode connections

## Requirements

- macOS 14.0+
- Xcode 15.0+
- [opencode](https://opencode.ai) installed on your system

## Installation

1. Clone the repository:
```bash
git clone git@github.com:Sir-Goose/kodanto.git
cd kodanto
```

2. Open in Xcode:
```bash
open kodanto.xcodeproj
```

3. Build and run (⌘+R)

**Note:** The app sandbox is disabled so kodanto can launch your installed `opencode` binary directly.

## Development

### SourceKit / LSP Setup

This project uses `xcode-build-server` so `sourcekit-lsp` can understand the Xcode project more reliably.

If `buildServer.json` becomes stale on a different machine or after moving the repo, regenerate it from the repo root:

```sh
xcode-build-server config -project "kodanto.xcodeproj" -scheme "kodanto"
```

After regenerating, restart your editor so the updated build-server configuration is picked up.

### Project Structure

```
kodanto/
├── App/                    # App entry point
├── Core/                   # Core utilities and extensions
├── Features/               # Feature modules
│   ├── Composer/          # Message input composer
│   ├── Connections/       # Connection management
│   ├── LiveSync/          # Real-time sync coordinator
│   ├── SessionDetail/     # Session detail views
│   ├── Terminal/          # Terminal integration
│   ├── Transcript/        # Chat transcript views
│   └── Workspace/         # Workspace management
├── Models/                # Data models
├── Services/              # Backend services
└── Views/                 # Shared UI components
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌃ + ` | Toggle Terminal Panel |
| ⌘⇧ + , | Open Connections Manager |
| ⌘⇧ + D | Open Diagnostics |

## Architecture

kodanto follows a clean architecture pattern with:
- **Stores** - State management and business logic
- **Views** - SwiftUI presentation layer
- **Services** - Backend communication and opencode integration
- **Models** - Data structures and types

The app communicates with opencode via a sidecar process that manages the server protocol connection.

## License

MIT License - see LICENSE file for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
