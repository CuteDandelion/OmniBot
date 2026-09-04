# Agent HQ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a native macOS SwiftUI app where you create agents (role + chosen vector mascot + workspace), chat with the selected agent on the right, and agents can hand work to each other via Codex CLI app-server.

**Architecture:** One SwiftUI app owns the roster and UI. On launch it spawns a single `codex app-server` child and speaks JSON-RPC over stdio. Each agent is a SwiftData row plus one Codex thread (`cwd`, model, effort, role instructions). Handoffs are an app-hosted MCP `handoff` tool: the sender’s turn pauses, a card appears in both transcripts, the target gets a new turn, and the tool returns the result. Command approvals are a global native sheet.

**Tech Stack:** macOS 14+ SwiftUI, SwiftData, XcodeGen, Codex CLI 0.153.x app-server, app-owned MCP over stdio.

**Spec:** This document (approved design + implementation tasks). Repo is empty: `/Users/cutedandelion/Documents/ChatGPT/Compliance-Demo`.

## Global Constraints

- Native macOS SwiftUI only. Not a web app, Electron, or Tauri.
- GitHub Primer visual system (tokens below). SF Pro. 13pt body. 6pt card radius.
- Product name: **Agent HQ**. Bundle ID: `local.agenthq`.
- Engine: local `codex app-server` (JSON-RPC). Do not bundle Codex. Default binary: `codex` on PATH; Settings may override.
- App is **not** App Store sandboxed (developer tool; child process must write user-chosen folders).
- `clientInfo.name` for initialize: `agent_hq`.
- Sandbox/approval: `workspaceWrite` + `onRequest`. File edits in cwd do not prompt; shell / extra-net / outside-cwd do.
- v1 is HQ + sequential visible handoffs, not a parallel team orchestra.
- Any agent may call `handoff`. Cycles (A waiting on B waiting on A) are rejected. One in-flight outbound handoff per agent.
- Chat is Codex-quiet: user text, assistant markdown, one Working row, handoff cards, GitHub-style diffs. No raw tool JSON in the main thread.
- Model and thinking effort live on the **composer rail**, not the header.
- Mascot is **user-selectable** per agent, independent of role. Role preset only suggests a default.
- Waiting handoff plays a looping mascot wait animation (Reduce Motion → still pose + pip).
- Persist agents/handoffs in SwiftData. Transcripts live in Codex thread rollouts.
- v1 out of scope: parallel orchestra, App Store sandbox, bundling Codex, cloud agents, voice, plugin marketplace UI.

---

## Approved design

### Shell

`NavigationSplitView`. Sidebar ~260pt: filter, agent rows (32pt mascot, name, role caption, status pip), **+ New agent**. Header: 40pt mascot (click to change mascot), name · role, truncated workspace path (click → `NSOpenPanel`). Composer: multiline field; bottom rail `[model ▾] [effort ▾] Send/Stop`.

```
┌──────────────┬─────────────────────────────────────────────┐
│ Agent HQ     │  [mascot] Ada · Chief of Staff              │
│              │  ~/Documents/ChatGPT/MyBusiness             │
│ 🔍           ├─────────────────────────────────────────────┤
│ [mascot] Ada │  you / answer / handoff card / working      │
│  Chief of St ├─────────────────────────────────────────────┤
│ + New agent  │  Message Ada…                               │
│              │  [gpt-5.6-sol ▾] [medium ▾]          Send   │
└──────────────┴─────────────────────────────────────────────┘
```

**New agent sheet:** name, role preset (Chief of Staff / Software Engineer / QA Engineer / Custom + blurb), **mascot grid**, workspace folder. Model/effort default from last used or Codex default.

**Primer tokens (light / dark):**

| Token   | Light     | Dark      |
|---------|-----------|-----------|
| canvas  | `#ffffff` | `#0d1117` |
| subtle  | `#f6f8fa` | `#161b22` |
| border  | `#d0d7de` | `#30363d` |
| fg      | `#1f2328` | `#e6edf3` |
| muted   | `#656d76` | `#8b949e` |
| accent  | `#0969da` | `#2f81f7` |

Success / danger / attention: Primer greens/reds/ambers.

### Mascots

Catalog (`MascotKind`, raw `String`, CaseIterable): `bear`, `cat`, `owl`, `fox`, `rabbit`, `penguin`, `frog`, `corgi`. Each is a SwiftUI vector `MascotView` (no bitmaps).

Role default suggestion only: CoS → bear, Engineer → cat, QA → owl, Custom → fox. User can pick any mascot in the create sheet and later via a popover grid from the header mascot.

**States:** `idle` (gentle bounce), `hover` (blink), `working` (typing), `needsApproval` (alert), `waiting` (loop: shift weight, glance aside, tap paw). Waiting plays on the sender header mascot and the handoff-card mascot. Target plays `working`. `accessibilityReduceMotion`: freeze at a still frame of that state + status pip.

### Codex mapping

Launch → spawn `codex app-server` → `initialize` / `initialized` → `model/list`. Create agent → `thread/start` (`cwd`, `model`, `sandbox: workspaceWrite`, `approvalPolicy: onRequest`, role `developer_instructions`). Select → `thread/resume` + `thread/read(includeTurns: true)`. Send → `turn/start` with composer model/effort. Stop → `turn/interrupt`. Change workspace → archive old thread, `thread/start` with new cwd.

### Handoff

App binary also runs `--mcp` as a stdio MCP server. GUI listens on a unix socket under Application Support. App-server is spawned with that MCP attached (`mcp_servers.agenthq`). Tool:

```
handoff(agent_id: string, brief: string)
```

Tool description includes the live roster (id, name, role). On call: persist `Handoff`, insert cards in both UIs, pause sender on the MCP response, `turn/start` the target with a structured brief. When the target turn completes (including nested non-cycle handoffs), return the summary to the MCP call; sender resumes; card → done/failed. **Open** switches the selected agent.

Approvals: global sheet (mascot + name, command, Allow / Allow always for prefix / Deny). Background specialists can still prompt.

### Role instructions (shipped)

- **Chief of Staff:** Coordinate. Break work up. Use `handoff` to specialists. Summarize back to the user. Do not implement large code changes yourself.
- **Software Engineer:** Implement in the workspace. Edit/write/tests as needed. Handoff to QA when implementation is ready to verify.
- **QA Engineer:** Write/run tests, report failures with evidence, hand back to Engineering with a fix brief.
- **Custom:** The user blurb is the role.

---

## File map

```
AgentHQ/
  project.yml
  README.md
  .gitignore
  AgentHQ/
    AgentHQApp.swift
    Info.plist
    AgentHQ.entitlements          # sandbox disabled
    Theme/Tokens.swift
    Models/Agent.swift
    Models/Handoff.swift
    Models/RolePreset.swift
    Models/MascotKind.swift
    AppSupport/AppSession.swift   # selected agent, banners, models catalog
    AppSupport/CodexProcess.swift
    AppSupport/HandoffOrchestrator.swift
    AppSupport/MCPBridge.swift    # unix socket server for --mcp child
    Mascots/MascotView.swift
    Mascots/MascotState.swift
    Mascots/MascotPicker.swift
    Features/SidebarView.swift
    Features/AgentRow.swift
    Features/ChatView.swift
    Features/TranscriptView.swift
    Features/HandoffCard.swift
    Features/ComposerView.swift
    Features/AgentHeader.swift
    Features/NewAgentSheet.swift
    Features/ApprovalSheet.swift
    Features/EmptyStateView.swift
    Features/SettingsView.swift
    MCP/MCPMain.swift             # stdio MCP when argv contains --mcp
  CodexClient/                    # local Swift package
    Package.swift
    Sources/CodexClient/
      JSONRPC.swift
      AppServerClient.swift
      ProtocolTypes.swift         # generated + thin wrappers
    Tests/CodexClientTests/
      JSONRPCTests.swift
      AppServerClientTests.swift
  AgentHQTests/
    HandoffOrchestratorTests.swift
    AgentModelTests.swift
  Fixtures/
    app-server-sample.jsonl
```

Schemas: run `codex app-server generate-json-schema --out AgentHQ/CodexClient/Schemas` during Task 3 and check in. Decode with `ProtocolTypes.swift` (hand-written Codable for the methods we call, not a giant generated dump unless generation is clean).

---

## Key types (lock names)

```swift
enum RolePreset: String, Codable, CaseIterable {
    case chiefOfStaff, softwareEngineer, qaEngineer, custom
    var defaultTitle: String { /* Chief of Staff, Software Engineer, QA Engineer, Custom */ }
    var defaultMascot: MascotKind { /* bear, cat, owl, fox */ }
    var developerInstructions: String { /* shipped prompts above */ }
}

enum MascotKind: String, Codable, CaseIterable {
    case bear, cat, owl, fox, rabbit, penguin, frog, corgi
}

enum MascotState: String { case idle, hover, working, waiting, needsApproval }

enum AgentRuntimeStatus: String { case idle, working, waiting, needsApproval }

@Model final class Agent {
    @Attribute(.unique) var id: UUID
    var name: String
    var role: RolePreset
    var customRoleTitle: String?
    var customInstructions: String?
    var mascot: MascotKind
    var workspacePath: String
    var model: String
    var reasoningEffort: String
    var threadId: String?
    var createdAt: Date
    var displayRole: String { role == .custom ? (customRoleTitle ?? "Custom") : role.defaultTitle }
}

@Model final class HandoffRecord {
    @Attribute(.unique) var id: UUID
    var fromAgentId: UUID
    var toAgentId: UUID
    var brief: String
    var status: String // pending | running | done | failed
    var resultSummary: String?
    var createdAt: Date
}

struct ChatItem: Identifiable {
    let id: String
    enum Kind {
        case user(String)
        case assistant(String)
        case working(detail: String?)
        case handoff(HandoffRecord)
        case diff(path: String, summary: String)
    }
    var kind: Kind
}
```

`AppServerClient` public API:

```swift
public struct ClientInfo: Sendable {
    public var name: String
    public var title: String
    public var version: String
}

public final class AppServerClient: Sendable {
    public init(executableURL: URL, extraConfig: [String: String])
    public func start() async throws
    public func initialize(clientInfo: ClientInfo) async throws
    public func initialized() async throws
    public func listModels() async throws -> [ModelInfo]
    public func threadStart(_ params: ThreadStartParams) async throws -> Thread
    public func threadResume(threadId: String) async throws -> Thread
    public func threadRead(threadId: String, includeTurns: Bool) async throws -> ThreadReadResult
    public func threadArchive(threadId: String) async throws
    public func turnStart(_ params: TurnStartParams) async throws -> Turn
    public func turnInterrupt(threadId: String) async throws
    public func respondApproval(requestId: JSONRPCID, decision: ApprovalDecision) async throws
    public var events: AsyncStream<ServerEvent>
}

public struct ModelInfo: Sendable {
    public var id: String
    public var displayName: String
    public var defaultReasoningEffort: String?
    public var supportedReasoningEfforts: [ReasoningEffort]
    public var isDefault: Bool
}
```

Handoff MCP tool input: `{ "agent_id": "<uuid>", "brief": "..." }`. Return text summary or JSON-RPC/MCP error on cycle/unknown.

---

### Task 1: Scaffold macOS app + Primer shell

**Files:** Create `project.yml`, `AgentHQ/AgentHQApp.swift`, `Theme/Tokens.swift`, `Features/SidebarView.swift`, `Features/ChatView.swift` (placeholder), `Features/EmptyStateView.swift`, `Info.plist`, `AgentHQ.entitlements`, `.gitignore`, `README.md`.

**Produces:** A runnable `.app` with split view, Primer colors light/dark, empty roster, “New agent” button that does not persist yet.

- [ ] **Step 1:** Add `.gitignore` for `.build/`, `DerivedData/`, `*.xcuserstate`, `.DS_Store`.
- [ ] **Step 2:** Write `project.yml` (XcodeGen): macOS 14.0, bundle `local.agenthq`, sources `AgentHQ`, test target `AgentHQTests`, package dep on local `CodexClient` (stub Package.swift allowed this task if needed to generate). `CODE_SIGN_IDENTITY: "-"` for local. Entitlements file with **App Sandbox false** (omit `com.apple.security.app-sandbox` or set it false).
- [ ] **Step 3:** `Tokens.swift` with Color assets via Swift `Color(hex:)` for the table above; `Font.body` 13pt, caption 12pt; `cardRadius = 6`.
- [ ] **Step 4:** `AgentHQApp`: `WindowGroup` + `NavigationSplitView` column width 260. Sidebar header “Agent HQ”, empty list, toolbar plus. Detail: empty state copy “Create an agent to start.” Apply canvas background.
- [ ] **Step 5:** Generate the project (`xcodegen generate`) and `xcodebuild -scheme AgentHQ -destination 'platform=macOS' build`. Expected: BUILD SUCCEEDED.
- [ ] **Step 6:** Commit `chore: scaffold Agent HQ macOS shell`.

### Task 2: SwiftData agents, new-agent sheet, mascot picker (no Codex yet)

**Files:** `Models/*`, `Mascots/*`, `Features/NewAgentSheet.swift`, `Features/AgentRow.swift`, `Features/AgentHeader.swift`, `AgentHQTests/AgentModelTests.swift`.

**Produces:** Create/select agents locally. Mascot grid on create and via header click. Workspace via `NSOpenPanel`. Role defaults mascot but does not lock it.

- [ ] **Step 1:** Write `AgentModelTests` asserting `RolePreset.chiefOfStaff.defaultMascot == .bear` and that assigning `.corgi` to a CoS agent is allowed.
- [ ] **Step 2:** Implement `RolePreset`, `MascotKind`, `@Model Agent`.
- [ ] **Step 3:** `MascotView(kind:state:size:)` — distinct silhouette per kind (ears/beak/snout), idle bounce 1.6s, hover blink. Previews for all kinds × light/dark.
- [ ] **Step 4:** `MascotPicker`: 4×2 grid of 48pt mascots, selection ring in accent. Used in `NewAgentSheet` and header popover.
- [ ] **Step 5:** `NewAgentSheet`: name field, role picker (changing role **suggests** default mascot only if the user has not manually picked), mascot grid, “Choose folder…”. Save inserts `Agent`.
- [ ] **Step 6:** Sidebar lists agents; selection drives `AgentHeader` (mascot, `displayRole`, path). Click mascot → picker popover writes `agent.mascot`.
- [ ] **Step 7:** Run `xcodebuild test -scheme AgentHQ -destination 'platform=macOS'`. Commit `feat: agent roster, roles, and mascot picker`.

### Task 3: CodexClient JSON-RPC + fake server tests

**Files:** `CodexClient/Package.swift`, `Sources/CodexClient/*`, `Tests/CodexClientTests/*`, `Fixtures/app-server-sample.jsonl`.

**Produces:** Typed client that can initialize, list models, start/resume threads, start/interrupt turns, and surface events/approvals. No UI.

- [ ] **Step 1:** Run `codex app-server generate-json-schema --out AgentHQ/CodexClient/Schemas` (or repo-relative `CodexClient/Schemas`). Check in.
- [ ] **Step 2:** Implement newline-delimited JSON-RPC: write request with incrementing `id`; match responses; notifications have no `id`.
- [ ] **Step 3:** Fake stdio fixture test: feed initialize result, `thread/start` result, `item/agentMessage/delta`, `turn/completed`. Assert `events` yields those.
- [ ] **Step 4:** Fake approval: server request `item/commandExecution/requestApproval` (or the method name from the generated schema — **use the schema, do not guess**). Client `respondApproval`.
- [ ] **Step 5:** `swift test --package-path CodexClient`. Commit `feat: Codex app-server JSON-RPC client`.

### Task 4: Spawn app-server, model catalog, empty/error states

**Files:** `AppSupport/CodexProcess.swift`, `AppSupport/AppSession.swift`, `Features/SettingsView.swift`, `Features/EmptyStateView.swift`, `Features/ComposerView.swift` (model/effort menus wired to catalog, send still no-op if no thread).

**Produces:** Launching the app starts Codex. Settings for binary path. Composer shows real `model/list` + efforts. Missing binary → empty state.

- [ ] **Step 1:** `CodexProcess` resolves executable (`UserDefaults` key `codexPath` else `PATH`). Spawns `app-server` with MCP config pointing at `Bundle.main.executableURL` + `--mcp` and a unix socket path in Application Support (`Handoff.sock`).
- [ ] **Step 2:** `AppSession` on appear: start client, initialize `agent_hq` / `Agent HQ` / version, `listModels()`, store catalog. Crash → one reconnect, then banner “Codex disconnected”.
- [ ] **Step 3:** Empty states: “Codex CLI not found”, “Codex is not signed in” (detect from initialize/error payload), Retry + Settings.
- [ ] **Step 4:** Composer rail: model menu from catalog; effort menu from `supportedReasoningEfforts` of the selected model; persist onto the selected `Agent`.
- [ ] **Step 5:** Manual: run the app, confirm model list matches `codex debug models` roughly. Commit `feat: spawn Codex app-server and load models`.

### Task 5: Threads + quiet chat

**Files:** `Features/TranscriptView.swift`, `Features/ComposerView.swift`, `Features/ChatView.swift`, `AppSupport/AppSession.swift`.

**Produces:** Selecting an agent resumes/starts its thread. Send streams assistant text. Working row while a turn is active. Stop interrupts. Workspace change archives + new thread.

- [ ] **Step 1:** On agent select: if `threadId` nil, `threadStart` with cwd/model/sandbox/approval/developer_instructions from role (custom uses `customInstructions`); save `threadId`. Else `threadResume` + `threadRead(includeTurns: true)` and map items to `ChatItem`s (user/assistant/diff only; skip raw tool dumps).
- [ ] **Step 2:** Send: append user `ChatItem`, `turnStart` with composer text + model + effort. Subscribe: `agentMessage/delta` updates assistant bubble; command/file items collapse into Working detail; `turn/completed` clears working. Header mascot → `working`.
- [ ] **Step 3:** Composer: Enter send, Shift+Enter newline. While running, button is **Stop** → `turnInterrupt`.
- [ ] **Step 4:** Path in header click: `NSOpenPanel`, set `workspacePath`, `threadArchive` old, nil `threadId`, start new thread. Banner if folder missing.
- [ ] **Step 5:** Live smoke: create Engineer, pick a real folder, ask “what is the top-level of this repo?”. Commit `feat: per-agent Codex threads and quiet chat`.

### Task 6: Approval sheet

**Files:** `Features/ApprovalSheet.swift`, `AppSupport/AppSession.swift`.

**Produces:** Global modal for command/permission approvals, including when that agent is not selected. Mascot uses `needsApproval`.

- [ ] **Step 1:** On approval server-request, set `pendingApproval` (agent id, command, reason, rpc id). Present `.sheet` from the root scene, not the chat pane.
- [ ] **Step 2:** Sheet UI: 40pt mascot `needsApproval`, agent name, monospaced command, Allow / Allow always (decision value from schema) / Deny. Buttons call `respondApproval`.
- [ ] **Step 3:** Deny/allow clears sheet. If another approval is queued, show the next. Commit `feat: global Codex approval sheet`.

### Task 7: MCP handoff + waiting mascot + cards

**Files:** `MCP/MCPMain.swift`, `AppSupport/MCPBridge.swift`, `AppSupport/HandoffOrchestrator.swift`, `Features/HandoffCard.swift`, `AgentHQTests/HandoffOrchestratorTests.swift`, waiting animation in `MascotView`.

**Produces:** Any agent can `handoff`. Cards in both chats. Sender mascot waits (loop). Target works. Result returns to the paused tool. Cycles rejected.

- [ ] **Step 1:** Tests (fake, no Codex): A→B success returns summary and `status == done`; A→B→A cycle throws and creates no record; interrupt marks `failed`.
- [ ] **Step 2:** `HandoffOrchestrator.handoff(from:to:brief:)`: reject unknown id; reject if `to` has a pending handoff whose target is `from` (walk the in-flight chain); reject if `from` already has outbound pending; insert `HandoffRecord`; return an async handle that completes with summary.
- [ ] **Step 3:** `--mcp` process: JSON-RPC MCP stdio, `tools/list` with `handoff`, `tools/call` forwards to unix socket, waits for GUI JSON `{ "ok": true, "summary": "..." }` or error.
- [ ] **Step 4:** GUI `MCPBridge` accepts socket connections. On `handoff`, call orchestrator: insert cards into both in-memory transcripts, set from.status waiting / to.status working, `turnStart` on target with brief:

  ```
  Handoff from {name} ({role}).
  Their workspace: {path}
  Brief:
  {brief}

  Do the work in your workspace. Reply with a concise result for the sender.
  ```

  On target `turn/completed`, write summary onto the record, complete the MCP wait, set mascots idle/done.
- [ ] **Step 5:** `HandoffCard`: Primer card, target (or source) mascot in waiting/working/done, one-line brief, status, **Open** selects that agent. Copy: outbound “→ Lin · Software Engineer”, inbound “From Ada · Chief of Staff”.
- [ ] **Step 6:** `MascotView` waiting loop (~2s): body sway, glance, paw tap. `working` typing. Reduce Motion off. Previews for waiting.
- [ ] **Step 7:** Tool description rebuilt whenever the roster changes (name, role, uuid). Composer Stop on the specialist fails the handoff.
- [ ] **Step 8:** Run unit tests + manual: CoS “ask Engineering to list files”, click Open, see waiting mascot, result returns. Commit `feat: inter-agent handoff with waiting mascots`.

### Task 8: Polish, README, smoke

**Files:** `README.md`, Settings, previews, any layout gaps.

- [ ] **Step 1:** README: install XcodeGen, `xcodegen generate`, open `AgentHQ.xcodeproj`, require Codex CLI signed in, how to create CoS + Engineer, permissions, mascot picker.
- [ ] **Step 2:** Filter box in sidebar; status pip colors (idle muted, working accent, waiting attention, approval danger).
- [ ] **Step 3:** Verify light/dark, Reduce Motion, composer model/effort, header without model controls.
- [ ] **Step 4:** Commit `docs: Agent HQ README and polish`.

---

## Spec coverage

| Requirement                         | Task |
|-------------------------------------|------|
| Native SwiftUI macOS app            | 1    |
| GitHub Primer theme                 | 1    |
| Left roster / right chat            | 1–5  |
| Create agent, role presets          | 2    |
| Select mascot per agent             | 2    |
| Vector mascots + wait animation     | 2, 7 |
| Workspace directory per agent       | 2, 5 |
| Codex app-server engine             | 3–5  |
| Model + effort on composer          | 4–5  |
| Quiet transcript                    | 5    |
| Workspace-write + ask commands      | 5–6  |
| Any-agent handoff + cards           | 7    |
| Result returns to sender            | 7    |
| Errors / empty states               | 4, 5 |
| Tests                               | 2, 3, 7 |

## Execution

After approval, implement in this repo (not a throwaway worktree unless you ask). Two options:

1. **Subagent-driven** — one task per subagent, review between tasks.
2. **Inline** — same session, checkpoint after each task.
