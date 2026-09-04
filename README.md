# Agent HQ

Native macOS 14+ SwiftUI shell for coordinating local Codex agents. Bundle ID: `local.agenthq`.

The app is not App Store sandboxed.

## Requirements

- macOS 14+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46+

## Build

```sh
xcodegen generate
xcodebuild -scheme AgentHQ -destination 'platform=macOS' build
```

Open `AgentHQ.xcodeproj` after generating to run from Xcode.
