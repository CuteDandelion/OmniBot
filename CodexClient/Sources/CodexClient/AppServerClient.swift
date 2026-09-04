import Foundation

public enum AppServerClientError: Error, Equatable {
    case notStarted
    case processLaunchFailed(String)
    case processExited(Int32)
    case rpc(JSONRPCErrorBody)
    case unexpectedMessage
    case unknownTurn(threadId: String)
}

/// Typed newline-delimited JSON-RPC client for `codex app-server`.
public final class AppServerClient: @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let ids = JSONRPCIDGenerator()
    private let lock = NSLock()

    private var process: Process?
    private var stdin: FileHandle?
    private var readTask: Task<Void, Never>?
    private var isStarting = false
    private var didFinishEvents = false
    private var pending: [JSONRPCID: CheckedContinuation<JSONValue, Error>] = [:]
    private var lastTurnIDByThread: [String: String] = [:]
    private let eventContinuation: AsyncStream<ServerEvent>.Continuation

    public let events: AsyncStream<ServerEvent>

    public init(executableURL: URL, extraConfig: [String: String]) {
        self.executableURL = executableURL
        self.arguments = ["app-server"] + extraConfig.sorted { $0.key < $1.key }.flatMap { key, value in
            ["-c", "\(key)=\(value)"]
        }
        let (stream, continuation) = AsyncStream<ServerEvent>.makeStream()
        self.events = stream
        self.eventContinuation = continuation
    }

    /// Test seam so a fake stdio process can stand in for `codex`.
    init(executableURL: URL, processArguments: [String]) {
        self.executableURL = executableURL
        self.arguments = processArguments
        let (stream, continuation) = AsyncStream<ServerEvent>.makeStream()
        self.events = stream
        self.eventContinuation = continuation
    }

    deinit {
        shutDown()
    }

    public func start() async throws {
        while true {
            lock.lock()
            if process != nil {
                lock.unlock()
                return
            }
            if isStarting {
                lock.unlock()
                try await Task.sleep(nanoseconds: 5_000_000)
                continue
            }
            isStarting = true
            lock.unlock()
            break
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.standardError

        process.terminationHandler = { [weak self] proc in
            self?.handleTermination(status: proc.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            lock.lock()
            isStarting = false
            lock.unlock()
            throw AppServerClientError.processLaunchFailed(error.localizedDescription)
        }

        let stdout = stdoutPipe.fileHandleForReading
        lock.lock()
        self.process = process
        self.stdin = stdinPipe.fileHandleForWriting
        self.readTask = Task { [weak self] in
            await self?.readLoop(handle: stdout)
        }
        isStarting = false
        lock.unlock()
    }

    public func initialize(clientInfo: ClientInfo) async throws {
        let _: InitializeResult = try await send(
            method: AppServerMethod.initialize,
            params: InitializeParams(clientInfo: clientInfo)
        )
    }

    public func initialized() async throws {
        try write(.notification(JSONRPCNotification(method: AppServerMethod.initialized)))
    }

    public func listModels() async throws -> [ModelInfo] {
        let result: ModelListResult = try await send(
            method: AppServerMethod.modelList,
            params: JSONValue.object([:])
        )
        return result.data.map {
            ModelInfo(
                id: $0.id,
                displayName: $0.displayName,
                defaultReasoningEffort: $0.defaultReasoningEffort,
                supportedReasoningEfforts: $0.supportedReasoningEfforts,
                isDefault: $0.isDefault
            )
        }
    }

    public func threadStart(_ params: ThreadStartParams) async throws -> Thread {
        let envelope: ThreadEnvelope = try await send(method: AppServerMethod.threadStart, params: params)
        rememberTurns(from: envelope.thread)
        return envelope.thread
    }

    public func threadResume(threadId: String) async throws -> Thread {
        let envelope: ThreadEnvelope = try await send(
            method: AppServerMethod.threadResume,
            params: ThreadIdParams(threadId: threadId)
        )
        rememberTurns(from: envelope.thread)
        return envelope.thread
    }

    public func threadRead(threadId: String, includeTurns: Bool) async throws -> ThreadReadResult {
        let result: ThreadReadResult = try await send(
            method: AppServerMethod.threadRead,
            params: ThreadReadParams(threadId: threadId, includeTurns: includeTurns)
        )
        rememberTurns(from: result.thread)
        return result
    }

    public func threadArchive(threadId: String) async throws {
        let _: JSONValue = try await send(
            method: AppServerMethod.threadArchive,
            params: ThreadIdParams(threadId: threadId)
        )
    }

    public func turnStart(_ params: TurnStartParams) async throws -> Turn {
        let envelope: TurnEnvelope = try await send(method: AppServerMethod.turnStart, params: params)
        rememberTurn(threadId: params.threadId, turnId: envelope.turn.id)
        return envelope.turn
    }

    public func turnInterrupt(threadId: String) async throws {
        guard let turnId = lastTurnID(for: threadId) else {
            throw AppServerClientError.unknownTurn(threadId: threadId)
        }
        let _: JSONValue = try await send(
            method: AppServerMethod.turnInterrupt,
            params: TurnInterruptParams(threadId: threadId, turnId: turnId)
        )
    }

    public func respondApproval(requestId: JSONRPCID, decision: ApprovalDecision) async throws {
        try write(
            .response(
                JSONRPCResponse(
                    id: requestId,
                    result: try JSONValue(encoding: ApprovalResponse(decision: decision))
                )
            )
        )
    }

    private func send<Params: Encodable, Result: Decodable>(method: String, params: Params) async throws -> Result {
        let result = try await send(method: method, params: try JSONValue(encoding: params))
        return try result.decode(as: Result.self)
    }

    private func send(method: String, params: JSONValue?) async throws -> JSONValue {
        let id = ids.nextID()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pending[id] = continuation
            lock.unlock()
            do {
                try write(.request(JSONRPCRequest(id: id, method: method, params: params)))
            } catch {
                finishPending(id: id, result: .failure(error))
            }
        }
    }

    private func write(_ message: JSONRPCMessage) throws {
        let data = try message.encodeLine()
        lock.lock()
        defer { lock.unlock() }
        guard let handle = stdin else {
            throw AppServerClientError.notStarted
        }
        try handle.write(contentsOf: data)
    }

    private func readLoop(handle: FileHandle) async {
        var buffer = Data()
        do {
            for try await byte in handle.bytes {
                if Task.isCancelled { break }
                buffer.append(byte)
                if byte == UInt8(ascii: "\n") {
                    for line in JSONRPCCodec.pullLines(from: &buffer) {
                        handleLine(line)
                    }
                }
            }
            if !buffer.isEmpty {
                handleLine(buffer)
            }
        } catch {
            failAllPending(error)
            finishEvents()
            return
        }
        failAllPending(AppServerClientError.processExited(currentExitStatus()))
        finishEvents()
    }

    private func handleLine(_ data: Data) {
        let message: JSONRPCMessage
        do {
            message = try JSONRPCMessage.decode(data)
        } catch {
            eventContinuation.yield(.invalidMessage)
            failAllPending(AppServerClientError.unexpectedMessage)
            return
        }

        switch message {
        case .response(let response):
            eventContinuation.yield(.response(id: response.id, result: response.result))
            finishPending(id: response.id, result: .success(response.result))
        case .error(let response):
            finishPending(id: response.id, result: .failure(AppServerClientError.rpc(response.error)))
        case .notification(let notification):
            eventContinuation.yield(Self.event(for: notification))
            if notification.method == AppServerMethod.turnCompleted,
               let params = try? notification.params?.decode(as: TurnCompletedNotification.self) {
                rememberTurn(threadId: params.threadId, turnId: params.turn.id)
            } else if notification.method == AppServerMethod.agentMessageDelta,
                      let params = try? notification.params?.decode(as: AgentMessageDeltaNotification.self) {
                rememberTurn(threadId: params.threadId, turnId: params.turnId)
            }
        case .request(let request):
            eventContinuation.yield(Self.event(for: request))
        }
    }

    private static func event(for notification: JSONRPCNotification) -> ServerEvent {
        switch notification.method {
        case AppServerMethod.agentMessageDelta:
            if let params = try? notification.params?.decode(as: AgentMessageDeltaNotification.self) {
                return .agentMessageDelta(params)
            }
        case AppServerMethod.turnCompleted:
            if let params = try? notification.params?.decode(as: TurnCompletedNotification.self) {
                return .turnCompleted(params)
            }
        default:
            break
        }
        return .notification(method: notification.method, params: notification.params)
    }

    private static func event(for request: JSONRPCRequest) -> ServerEvent {
        if request.method == AppServerMethod.commandExecutionRequestApproval,
           let params = try? request.params?.decode(as: CommandExecutionRequestApprovalParams.self) {
            return .commandExecutionApproval(requestId: request.id, params: params)
        }
        return .request(id: request.id, method: request.method, params: request.params)
    }

    private func rememberTurns(from thread: Thread) {
        let inProgress = thread.turns.last { $0.status == "inProgress" }
        guard let turn = inProgress ?? thread.turns.last else { return }
        rememberTurn(threadId: thread.id, turnId: turn.id)
    }

    private func rememberTurn(threadId: String, turnId: String) {
        lock.lock()
        lastTurnIDByThread[threadId] = turnId
        lock.unlock()
    }

    private func lastTurnID(for threadId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return lastTurnIDByThread[threadId]
    }

    private func finishPending(id: JSONRPCID, result: Result<JSONValue, Error>) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func failAllPending(_ error: Error) {
        lock.lock()
        let continuations = Array(pending.values)
        pending.removeAll()
        lock.unlock()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func handleTermination(status: Int32) {
        failAllPending(AppServerClientError.processExited(status))
        finishEvents()
    }

    private func currentExitStatus() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard let process else { return -1 }
        return process.isRunning ? -1 : process.terminationStatus
    }

    private func finishEvents() {
        lock.lock()
        let already = didFinishEvents
        didFinishEvents = true
        lock.unlock()
        if !already {
            eventContinuation.finish()
        }
    }

    func shutDown() {
        lock.lock()
        let process = self.process
        let stdin = self.stdin
        let readTask = self.readTask
        self.process = nil
        self.stdin = nil
        self.readTask = nil
        isStarting = false
        lock.unlock()
        readTask?.cancel()
        try? stdin?.close()
        if process?.isRunning == true {
            process?.terminate()
        }
        failAllPending(AppServerClientError.processExited(-1))
        finishEvents()
    }
}
