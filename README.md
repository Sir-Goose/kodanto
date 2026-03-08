# kodanto

## Development

### SourceKit / LSP setup

This project uses `xcode-build-server` so `sourcekit-lsp` can understand the Xcode project more reliably.

If `buildServer.json` becomes stale on a different machine or after moving the repo, regenerate it from the repo root:

```sh
xcode-build-server config -project "kodanto.xcodeproj" -scheme "kodanto"
```

After regenerating, restart OpenCode so the updated build-server configuration is picked up.
