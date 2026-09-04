import Combine
import CodexClient
import Foundation

enum CodexConnectionState: Equatable {
    case idle
    case connecting
    case ready
    case missingBinary
    case notSignedIn
    case disconnected
}

enum EmptyStateCopy {
    static func title(for state: CodexConnectionState) -> String {
        switch state {
        case .missingBinary:
            return "Codex CLI not found"
        case .notSignedIn:
            return "Codex is not signed in"
        case .connecting, .idle:
            return "Connecting to Codex…"
        case .ready, .disconnected:
            return "Create an agent to start."
        }
    }

    static func showsActions(_ state: CodexConnectionState) -> Bool {
        state == .missingBinary || state == .notSignedIn
    }
}

enum CodexErrorClassifier {
    enum Kind: Equatable {
        case notSignedIn
        case missingBinary
        case crashed
        case other
    }

    static func kind(for error: Error) -> Kind {
        if let appError = error as? AppServerClientError {
            switch appError {
            case .processLaunchFailed:
                return .missingBinary
            case .notStarted:
                return .missingBinary
            case .processExited:
                return .crashed
            case .rpc(let body):
                if isAuthFailure(message: body.message, data: body.data) {
                    return .notSignedIn
                }
                return .other
            case .unexpectedMessage, .unknownTurn:
                return .other
            }
        }
        if isAuthFailure(message: error.localizedDescription, data: nil) {
            return .notSignedIn
        }
        return .other
    }

    static func isAuthFailure(message: String, data: JSONValue?) -> Bool {
        var parts = [message]
        if let data {
            parts.append(String(describing: data))
        }
        let haystack = parts.joined(separator: " ").lowercased()
        let needles = [
            "not signed in",
            "not authenticated",
            "authentication required",
            "unauthenticated",
            "login required",
            "please log in",
            "please login",
            "not logged in",
            "codex login",
            "auth required",
        ]
        return needles.contains { haystack.contains($0) }
    }
}

struct PendingApproval: Equatable {
    let requestId: JSONRPCID
    let threadId: String
    let agentID: UUID?
    let command: String
    let reason: String?
}

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var connectionState: CodexConnectionState = .idle
    @Published private(set) var models: [ModelInfo] = []
    @Published private(set) var resolvedExecutablePath: String?
    @Published var banner: String?
    @Published private(set) var items: [ChatItem] = []
    @Published private(set) var activeTurnAgentIDs: Set<UUID> = []
    @Published private(set) var workspaceWarning: String?
    @Published private(set) var pendingApproval: PendingApproval?
    @Published private(set) var isRespondingToApproval = false
    @Published private var approvalQueue: [PendingApproval] = []
    private var inFlightApprovalRequestID: JSONRPCID?

    static let clientInfo = ClientInfo(name: "agent_hq", title: "Agent HQ", version: "0.1.0")

    private var client: AppServerClient?
    private var lastStoppedPid: Int32?
    private var generation = 0
    private var reconnectUsed = false
    private var didStart = false
    private var didConnectOnce = false
    private var didForceRetry = false
    private let resolveExecutable: () -> URL?
    private let makeClient: (URL) -> AppServerClient
    private var eventPump: Task<Void, Never>?
    private var eventContinuations: [UUID: AsyncStream<ServerEvent>.Continuation] = [:]
    private var itemsByAgent: [UUID: [ChatItem]] = [:]
    private var agentIDByThread: [String: UUID] = [:]
    private var hydratedAgents: Set<UUID> = []
    private var selectedAgentID: UUID?
    private var selectGeneration = 0
    private var startingTurnAgentIDs: Set<UUID> = []
    private var pendingInterruptAgentIDs: Set<UUID> = []
    private var interruptedAgentIDs: Set<UUID> = []

    var showsSetupEmptyState: Bool {
        switch connectionState {
        case .missingBinary, .notSignedIn:
            return true
        case .connecting, .idle:
            return !didConnectOnce
        case .ready, .disconnected:
            return false
        }
    }

    var isReconnecting: Bool {
        connectionState == .connecting && didConnectOnce
    }

    func isTurnActive(for agentID: UUID) -> Bool {
        activeTurnAgentIDs.contains(agentID)
    }

    func mascotState(for agentID: UUID) -> MascotState {
        if pendingApproval?.agentID == agentID { return .needsApproval }
        if approvalQueue.contains(where: { $0.agentID == agentID }) { return .needsApproval }
        if activeTurnAgentIDs.contains(agentID) { return .working }
        return .idle
    }

    func subscribeToEvents() -> AsyncStream<ServerEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ServerEvent>.makeStream()
        eventContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.eventContinuations.removeValue(forKey: id)
            }
        }
        return stream
    }

    init(
        resolveExecutable: @escaping () -> URL? = { CodexProcess.resolveExecutable() },
        makeClient: @escaping (URL) -> AppServerClient = { executable in
            AppServerClient(
                executableURL: executable,
                extraConfig: CodexProcess.makeExtraConfig(
                    mcpExecutable: Bundle.main.executableURL ?? executable,
                    socketPath: CodexProcess.handoffSocketURL.path
                )
            )
        }
    ) {
        self.resolveExecutable = resolveExecutable
        self.makeClient = makeClient
    }

    func start() async {
        guard !AgentHQApp.isRunningTests else { return }
        guard !didStart else { return }
        didStart = true
        await retry()
    }

    func retry() async {
        generation += 1
        let generation = generation
        reconnectUsed = false
        banner = nil
        await connect(generation: generation, allowReconnect: true)
    }

    func shutdown() {
        discardClient()
    }

    func ensureThread(for agent: Agent) async {
        selectGeneration += 1
        let generation = selectGeneration
        selectedAgentID = agent.id
        items = itemsByAgent[agent.id] ?? []

        guard connectionState == .ready, client != nil else { return }

        if !workspaceExists(agent.workspacePath) {
            workspaceWarning = "Workspace folder is missing"
            return
        }
        if workspaceWarning == "Workspace folder is missing" {
            workspaceWarning = nil
        }

        if hydratedAgents.contains(agent.id), agent.threadId != nil {
            return
        }

        if let threadId = agent.threadId {
            await resumeThread(for: agent, threadId: threadId, generation: generation)
        } else {
            await startThread(for: agent, generation: generation)
        }
    }

    func send(_ text: String, from agent: Agent) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let threadId = agent.threadId, let client, !trimmed.isEmpty else { return }
        guard !activeTurnAgentIDs.contains(agent.id) else { return }

        interruptedAgentIDs.remove(agent.id)
        pendingInterruptAgentIDs.remove(agent.id)

        var current = itemsByAgent[agent.id] ?? []
        current.append(ChatItem(id: "local-\(UUID().uuidString)", kind: .user(trimmed)))
        ChatTranscript.setWorking(detail: nil, on: &current)
        store(current, for: agent.id)
        activeTurnAgentIDs.insert(agent.id)
        startingTurnAgentIDs.insert(agent.id)

        do {
            _ = try await client.turnStart(
                TurnStartParams(
                    threadId: threadId,
                    input: [.text(trimmed)],
                    model: agent.model.isEmpty ? nil : agent.model,
                    effort: agent.reasoningEffort.isEmpty ? nil : agent.reasoningEffort
                )
            )
            startingTurnAgentIDs.remove(agent.id)
            if pendingInterruptAgentIDs.contains(agent.id) {
                pendingInterruptAgentIDs.remove(agent.id)
                await performInterrupt(for: agent, threadId: threadId)
            }
        } catch {
            startingTurnAgentIDs.remove(agent.id)
            pendingInterruptAgentIDs.remove(agent.id)
            finishTurn(agent.id)
            banner = error.localizedDescription
        }
    }

    func interruptTurn(for agent: Agent) async {
        guard let threadId = agent.threadId else { return }
        if startingTurnAgentIDs.contains(agent.id) {
            pendingInterruptAgentIDs.insert(agent.id)
            return
        }
        guard activeTurnAgentIDs.contains(agent.id) else { return }
        await performInterrupt(for: agent, threadId: threadId)
    }

    func changeWorkspace(for agent: Agent, to path: String) async {
        let oldThreadId = agent.threadId
        if activeTurnAgentIDs.contains(agent.id) {
            await interruptTurn(for: agent)
        }
        if let oldThreadId {
            try? await client?.threadArchive(threadId: oldThreadId)
            agentIDByThread.removeValue(forKey: oldThreadId)
        }
        agent.workspacePath = path
        agent.threadId = nil
        itemsByAgent[agent.id] = []
        hydratedAgents.remove(agent.id)
        finishTurn(agent.id)
        if selectedAgentID == agent.id {
            items = []
        }
        await ensureThread(for: agent)
    }

    func respondToPendingApproval(_ decision: ApprovalDecision) async {
        guard !isRespondingToApproval, let pending = pendingApproval else { return }
        isRespondingToApproval = true
        inFlightApprovalRequestID = pending.requestId
        defer {
            inFlightApprovalRequestID = nil
            isRespondingToApproval = false
        }
        do {
            try await client?.respondApproval(requestId: pending.requestId, decision: decision)
        } catch {
            banner = error.localizedDescription
            return
        }
        guard pendingApproval?.requestId == pending.requestId else { return }
        pendingApproval = approvalQueue.isEmpty ? nil : approvalQueue.removeFirst()
    }

    private func connect(generation: Int, allowReconnect: Bool) async {
        guard generation == self.generation else { return }
        discardClient()
        connectionState = .connecting
        writeEvidence()

        guard let executable = resolveExecutable() else {
            resolvedExecutablePath = nil
            connectionState = .missingBinary
            models = []
            writeEvidence()
            return
        }
        resolvedExecutablePath = executable.path

        let client = makeClient(executable)
        self.client = client
        do {
            try await client.start()
            guard generation == self.generation else {
                client.stop()
                return
            }
            try await client.initialize(clientInfo: Self.clientInfo)
            guard generation == self.generation else {
                client.stop()
                return
            }
            try await client.initialized()
            guard generation == self.generation else {
                client.stop()
                return
            }
            let catalog = try await client.listModels()
            guard generation == self.generation else {
                client.stop()
                return
            }
            models = catalog
            connectionState = .ready
            didConnectOnce = true
            banner = nil
            hydratedAgents.removeAll()
            observeTermination(of: client, generation: generation, allowReconnect: allowReconnect)
            pumpEvents(from: client)
            writeEvidence()
            maybeForceRetryForEvidence()
        } catch {
            guard generation == self.generation else {
                client.stop()
                return
            }
            await handleFailure(error, generation: generation, allowReconnect: allowReconnect)
        }
    }

    private func discardClient() {
        eventPump?.cancel()
        eventPump = nil
        let old = client
        lastStoppedPid = old?.processIdentifier
        client = nil
        old?.onTermination = nil
        old?.stop()
        activeTurnAgentIDs = []
        startingTurnAgentIDs = []
        pendingInterruptAgentIDs = []
        interruptedAgentIDs = []
        pendingApproval = nil
        approvalQueue = []
        inFlightApprovalRequestID = nil
        isRespondingToApproval = false
        clearWorkingRows()
    }

    private func observeTermination(
        of client: AppServerClient,
        generation: Int,
        allowReconnect: Bool
    ) {
        client.onTermination = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.handleUnexpectedExit(
                    client: client,
                    generation: generation,
                    allowReconnect: allowReconnect
                )
            }
        }
    }

    private func handleUnexpectedExit(
        client: AppServerClient,
        generation: Int,
        allowReconnect: Bool
    ) async {
        guard generation == self.generation else { return }
        guard self.client === client else { return }
        await handleCrash(generation: generation, allowReconnect: allowReconnect)
    }

    private func handleCrash(generation: Int, allowReconnect: Bool) async {
        guard generation == self.generation else { return }
        if allowReconnect && !reconnectUsed {
            reconnectUsed = true
            await connect(generation: generation, allowReconnect: false)
            return
        }
        discardClient()
        connectionState = .disconnected
        banner = "Codex disconnected"
        writeEvidence()
    }

    private func handleFailure(_ error: Error, generation: Int, allowReconnect: Bool) async {
        switch CodexErrorClassifier.kind(for: error) {
        case .notSignedIn:
            connectionState = .notSignedIn
            writeEvidence()
        case .missingBinary:
            discardClient()
            connectionState = .missingBinary
            models = []
            writeEvidence()
        case .crashed:
            await handleCrash(generation: generation, allowReconnect: allowReconnect)
        case .other:
            if allowReconnect && !reconnectUsed {
                reconnectUsed = true
                await connect(generation: generation, allowReconnect: false)
            } else {
                discardClient()
                connectionState = .disconnected
                banner = "Codex disconnected"
                writeEvidence()
            }
        }
    }

    private func maybeForceRetryForEvidence() {
        guard ProcessInfo.processInfo.environment["AGENTHQ_RETRY_AFTER_READY"] == "1" else { return }
        guard !didForceRetry else { return }
        didForceRetry = true
        Task { await retry() }
    }

    private func pumpEvents(from client: AppServerClient) {
        eventPump?.cancel()
        eventPump = Task.detached { [weak self, weak client] in
            guard let client else { return }
            for await event in client.events {
                guard !Task.isCancelled else { break }
                await self?.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: ServerEvent) async {
        broadcast(event)

        switch event {
        case .commandExecutionApproval(let requestId, let params):
            let approval = PendingApproval(
                requestId: requestId,
                threadId: params.threadId,
                agentID: agentIDByThread[params.threadId],
                command: params.command ?? "command",
                reason: params.reason
            )
            await ingestApproval(approval)
        case .request(let requestId, let method, let params):
            if method.contains("requestApproval") || method.contains("requestUserInput") {
                let threadId = params?.object?["threadId"]?.string ?? ""
                let approval = PendingApproval(
                    requestId: requestId,
                    threadId: threadId,
                    agentID: agentIDByThread[threadId],
                    command: params?.object?["command"]?.string
                        ?? params?.object?["reason"]?.string
                        ?? method,
                    reason: params?.object?["reason"]?.string
                )
                await ingestApproval(approval)
            }
        default:
            break
        }

        guard let threadId = eventThreadId(event), let agentID = agentIDByThread[threadId] else { return }
        if interruptedAgentIDs.contains(agentID) {
            guard case .turnCompleted = event else { return }
        }
        var current = itemsByAgent[agentID] ?? []
        let finished = ChatTranscript.apply(event, threadId: threadId, to: &current)
        store(current, for: agentID)
        if finished {
            finishTurn(agentID)
            interruptedAgentIDs.remove(agentID)
            await respondAndDropApprovals(for: threadId, decision: .decline)
        }
    }

    private func ingestApproval(_ approval: PendingApproval) async {
        if let agentID = approval.agentID, interruptedAgentIDs.contains(agentID) {
            await respondToApprovals([approval], decision: .cancel)
            return
        }
        enqueueApproval(approval)
    }

    private func enqueueApproval(_ approval: PendingApproval) {
        if pendingApproval?.requestId == approval.requestId { return }
        if approvalQueue.contains(where: { $0.requestId == approval.requestId }) { return }
        if pendingApproval == nil {
            pendingApproval = approval
        } else {
            approvalQueue.append(approval)
        }
    }

    private func takeApprovals(for threadId: String) -> [PendingApproval] {
        var taken: [PendingApproval] = []
        var remaining: [PendingApproval] = []
        let skip = inFlightApprovalRequestID
        func consider(_ item: PendingApproval) {
            if item.threadId != threadId {
                remaining.append(item)
            } else if let skip, item.requestId == skip {
                return
            } else {
                taken.append(item)
            }
        }
        if let pending = pendingApproval {
            consider(pending)
        }
        for item in approvalQueue {
            consider(item)
        }
        pendingApproval = remaining.first
        approvalQueue = Array(remaining.dropFirst())
        return taken
    }

    private func requeueApprovals(_ approvals: [PendingApproval]) {
        guard !approvals.isEmpty else { return }
        if pendingApproval == nil {
            pendingApproval = approvals[0]
            approvalQueue.insert(contentsOf: approvals.dropFirst(), at: 0)
        } else {
            approvalQueue.insert(contentsOf: approvals, at: 0)
        }
    }

    private func respondToApprovals(_ approvals: [PendingApproval], decision: ApprovalDecision) async {
        for approval in approvals {
            do {
                try await client?.respondApproval(requestId: approval.requestId, decision: decision)
            } catch {
                banner = error.localizedDescription
            }
        }
    }

    private func respondAndDropApprovals(for threadId: String, decision: ApprovalDecision) async {
        let taken = takeApprovals(for: threadId)
        await respondToApprovals(taken, decision: decision)
    }

    private func broadcast(_ event: ServerEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func eventThreadId(_ event: ServerEvent) -> String? {
        switch event {
        case .agentMessageDelta(let delta):
            return delta.threadId
        case .turnCompleted(let completed):
            return completed.threadId
        case .commandExecutionApproval(_, let params):
            return params.threadId
        case .notification(_, let params), .request(_, _, let params):
            return params?.object?["threadId"]?.string
        default:
            return nil
        }
    }

    private func startThread(for agent: Agent, generation: Int) async {
        guard let client else { return }
        let instructions = agent.resolvedDeveloperInstructions
        do {
            let thread = try await client.threadStart(
                ThreadStartParams(
                    cwd: agent.workspacePath,
                    model: agent.model.isEmpty ? nil : agent.model,
                    sandbox: .workspaceWrite,
                    approvalPolicy: .onRequest,
                    developerInstructions: instructions.isEmpty ? nil : instructions
                )
            )
            agent.threadId = thread.id
            agentIDByThread[thread.id] = agent.id
            if itemsByAgent[agent.id] == nil {
                itemsByAgent[agent.id] = []
            }
            hydratedAgents.insert(agent.id)
            guard generation == selectGeneration else { return }
            items = itemsByAgent[agent.id] ?? []
        } catch {
            guard generation == selectGeneration else { return }
            banner = error.localizedDescription
        }
    }

    private func resumeThread(for agent: Agent, threadId: String, generation: Int) async {
        guard let client else { return }
        do {
            _ = try await client.threadResume(threadId: threadId)
            agentIDByThread[threadId] = agent.id
            if itemsByAgent[agent.id] == nil {
                let read = try await client.threadRead(threadId: threadId, includeTurns: true)
                itemsByAgent[agent.id] = ChatTranscript.items(from: read.thread)
            }
            hydratedAgents.insert(agent.id)
            guard generation == selectGeneration else { return }
            items = itemsByAgent[agent.id] ?? []
        } catch {
            agent.threadId = nil
            hydratedAgents.remove(agent.id)
            await startThread(for: agent, generation: generation)
        }
    }

    private func store(_ current: [ChatItem], for agentID: UUID) {
        itemsByAgent[agentID] = current
        if selectedAgentID == agentID {
            items = current
        }
        writeEvidence()
    }

    private func performInterrupt(for agent: Agent, threadId: String) async {
        interruptedAgentIDs.insert(agent.id)
        let dropped = takeApprovals(for: threadId)
        do {
            try await client?.turnInterrupt(threadId: threadId)
        } catch {
            if case AppServerClientError.unknownTurn = error {
                if startingTurnAgentIDs.contains(agent.id) {
                    pendingInterruptAgentIDs.insert(agent.id)
                    interruptedAgentIDs.remove(agent.id)
                    requeueApprovals(dropped)
                    return
                }
                await respondToApprovals(dropped, decision: .cancel)
                finishTurn(agent.id)
                return
            }
            interruptedAgentIDs.remove(agent.id)
            requeueApprovals(dropped)
            banner = error.localizedDescription
            return
        }
        await respondToApprovals(dropped, decision: .cancel)
        finishTurn(agent.id)
    }

    private func finishTurn(_ agentID: UUID) {
        var current = itemsByAgent[agentID] ?? []
        ChatTranscript.removeWorking(from: &current)
        store(current, for: agentID)
        activeTurnAgentIDs.remove(agentID)
        startingTurnAgentIDs.remove(agentID)
        pendingInterruptAgentIDs.remove(agentID)
    }

    private func clearWorkingRows() {
        for id in itemsByAgent.keys {
            var current = itemsByAgent[id] ?? []
            ChatTranscript.removeWorking(from: &current)
            itemsByAgent[id] = current
        }
        var current = items
        ChatTranscript.removeWorking(from: &current)
        items = current
    }

    private func workspaceExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func writeEvidence() {
        guard let raw = ProcessInfo.processInfo.environment["AGENTHQ_EVIDENCE"], !raw.isEmpty else { return }
        let dir = URL(fileURLWithPath: raw, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let modelPayload: [[String: Any]] = models.map { model in
            var item: [String: Any] = [
                "id": model.id,
                "displayName": model.displayName,
                "isDefault": model.isDefault,
                "efforts": model.supportedReasoningEfforts.map(\.reasoningEffort),
            ]
            if let effort = model.defaultReasoningEffort {
                item["defaultReasoningEffort"] = effort
            }
            return item
        }
        var payload: [String: Any] = [
            "state": describe(connectionState),
            "modelCount": models.count,
            "models": modelPayload,
            "generation": generation,
            "running": client?.isRunning ?? false,
        ]
        if let banner {
            payload["banner"] = banner
        }
        if let path = resolvedExecutablePath {
            payload["executable"] = path
        }
        if let pid = client?.processIdentifier {
            payload["pid"] = pid
        }
        if let lastStoppedPid {
            payload["lastStoppedPid"] = lastStoppedPid
        }
        payload["itemCount"] = items.count
        payload["activeTurns"] = activeTurnAgentIDs.count
        payload["hasWorking"] = items.contains { if case .working = $0.kind { return true }; return false }
        if let pendingApproval {
            payload["pendingApproval"] = pendingApproval.command
        }
        let transcript: [[String: String]] = items.compactMap { item in
            switch item.kind {
            case .user(let text): return ["kind": "user", "text": text]
            case .assistant(let text): return ["kind": "assistant", "text": text]
            case .working(let detail): return ["kind": "working", "text": detail ?? ""]
            case .diff(let path, let summary): return ["kind": "diff", "text": "\(path) \(summary)"]
            case .handoff: return ["kind": "handoff", "text": ""]
            }
        }
        payload["transcript"] = transcript
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("session.json"))
        }
        if connectionState != .connecting && connectionState != .idle {
            try? "ok\n".write(to: dir.appendingPathComponent("SESSION_DONE"), atomically: true, encoding: .utf8)
        }
    }

    private func describe(_ state: CodexConnectionState) -> String {
        switch state {
        case .idle: return "idle"
        case .connecting: return "connecting"
        case .ready: return "ready"
        case .missingBinary: return "missingBinary"
        case .notSignedIn: return "notSignedIn"
        case .disconnected: return "disconnected"
        }
    }
}
