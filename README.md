# Agent HQ

Native macOS 14+ SwiftUI app for coordinating local Codex agents. Create a roster (Chief of Staff, Software Engineer, QA Engineer, or Custom), chat with the selected agent, and let agents hand work to each other through Codex CLI’s app-server.

Bundle ID: `local.agenthq`. The app is **not** App Store sandboxed so Codex can write to folders you choose.

## Requirements

- macOS 14+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46+ (`brew install xcodegen`)
- [Codex CLI](https://github.com/openai/codex) 0.153.x on your `PATH`, signed in (`codex login`)

## Build

```sh
xcodegen generate
open AgentHQ.xcodeproj
```

Or from the command line:

```sh
xcodegen generate
xcodebuild -scheme AgentHQ -destination 'platform=macOS' build
xcodebuild -scheme AgentHQ -destination 'platform=macOS' test
```

## First run

1. Sign in to Codex if you have not already: `codex login`.
2. Launch **Agent HQ**. If Codex is missing or not signed in, the empty state explains how to fix it (**Retry** / **Settings**).
3. Settings (⌘,) can override the Codex binary path when it is not on `PATH`.

Model and thinking effort live on the **composer rail**, not the header. Appearance follows macOS light and dark (GitHub Primer tokens). Enable **Reduce Motion** in System Settings to freeze mascot animations; a status pip still shows the agent’s state.

### Permissions

Agent HQ is a developer tool and is not App Store sandboxed. Grant folder access when the workspace picker asks. File edits inside the workspace do not prompt. Shell, extra network, and paths outside the workspace show a global approval sheet (Allow / Allow always for the prefix / Deny).

### Create a Chief of Staff and an Engineer

1. Click **+ New agent**.
2. Name it `Ada`, role **Chief of Staff**. Pick a mascot (role default is bear; any mascot works). Choose a workspace folder. The **System message** is seeded from the role — edit it if you want. Codex receives it as `developer_instructions`. Click **Create**.
3. Click **+ New agent** again. Name it `Lin`, role **Software Engineer**, pick a mascot, choose a workspace. Create.

Select an agent in the sidebar to chat. Filter the roster with the search box.

### Mascot picker

Each agent has a user-chosen vector mascot, independent of role. The role only suggests a default (CoS → bear, Engineer → cat, QA → owl, Custom → fox). Change it later by clicking the header mascot.

### Edit the system message

Every role has an editable system / role message (not only Custom). After create, click the text-align button in the header to edit it. Saving a change archives the current Codex thread and starts a new one so the new instructions take effect.

### Delete an agent

Right-click an agent in the sidebar and choose **Delete…**. Confirm in the alert. In-flight handoffs involving that agent are failed, its Codex thread is archived if one exists, related handoff records are removed, and the agent is deleted. If it was selected, the selection clears.

### Status pips

Sidebar rows show a status pip:

| State     | Color                         |
|-----------|-------------------------------|
| Idle      | muted                         |
| Working   | accent                        |
| Waiting   | attention (amber)             |
| Approval  | danger (red)                  |

With Reduce Motion, the mascot also shows a matching pip on a still pose.
