import Darwin
import Foundation

enum HandoffIPCError: Error, LocalizedError {
    case pathTooLong
    case connectFailed
    case disconnected
    case timeout
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .pathTooLong: return "Handoff socket path is too long"
        case .connectFailed: return "Could not connect to Agent HQ"
        case .disconnected: return "Handoff socket disconnected"
        case .timeout: return "Handoff timed out"
        case .remote(let message): return message
        }
    }
}

enum HandoffIPC {
    static func encode(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            return nil
        }
        data.append(0x0A)
        return data
    }

    static func decode(_ data: Data) -> [String: Any]? {
        var trimmed = data
        while trimmed.last == 0x0A || trimmed.last == 0x0D {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: trimmed)) as? [String: Any]
    }

    static func jsonID(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    static func bindUnix(_ fd: Int32, path: String) throws {
        unlink(path)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        try writeUnixPath(&addr, path: path)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                Darwin.bind(fd, sock, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw posixError() }
    }

    static func connectUnix(_ fd: Int32, path: String) throws {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        try writeUnixPath(&addr, path: path)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                Darwin.connect(fd, sock, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw posixError() }
    }

    static func writeUnixPath(_ addr: inout sockaddr_un, path: String) throws {
        try path.withCString { cPath in
            let length = Int(strlen(cPath))
            let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
            guard length < maxLen else { throw HandoffIPCError.pathTooLong }
            withUnsafeMutableBytes(of: &addr.sun_path) { raw in
                guard let base = raw.baseAddress else { return }
                base.copyMemory(from: UnsafeRawPointer(cPath), byteCount: length + 1)
            }
        }
    }

    static func setNoSigPipe(_ fd: Int32) {
        var value: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }

    static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var sent = 0
            let total = raw.count
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            while sent < total {
                let n = Darwin.write(fd, base + sent, total - sent)
                if n <= 0 {
                    throw HandoffIPCError.disconnected
                }
                sent += n
            }
        }
    }
}

final class UnixJSONServer {
    private let path: String
    private let queue = DispatchQueue(label: "local.agenthq.handoff.server")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]

    var onRequest: ([String: Any], @escaping ([String: Any]) -> Void) -> Void = { _, reply in
        reply(["ok": false, "error": "unhandled"])
    }
    var onConnect: ((Int32) -> Void)?

    private struct Client {
        var source: DispatchSourceRead
        var buffer: Data
    }

    init(path: String) {
        self.path = path
    }

    func start() throws {
        stop()
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HandoffIPC.posixError() }
        HandoffIPC.setNoSigPipe(fd)
        do {
            try HandoffIPC.bindUnix(fd, path: path)
        } catch {
            Darwin.close(fd)
            throw error
        }
        guard Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            throw HandoffIPC.posixError()
        }
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptClient()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        acceptSource = source
        source.resume()
    }

    func stop() {
        queue.sync {
            for fd in clients.keys {
                closeClient(fd)
            }
            acceptSource?.cancel()
            acceptSource = nil
            listenFD = -1
        }
        unlink(path)
    }

    func broadcast(_ object: [String: Any]) {
        guard let data = HandoffIPC.encode(object) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            for fd in self.clients.keys {
                try? HandoffIPC.writeAll(fd, data)
            }
        }
    }

    func send(_ object: [String: Any], to fd: Int32) {
        guard let data = HandoffIPC.encode(object) else { return }
        queue.async {
            try? HandoffIPC.writeAll(fd, data)
        }
    }

    private func acceptClient() {
        let clientFD = Darwin.accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }
        HandoffIPC.setNoSigPipe(clientFD)
        let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readClient(clientFD)
        }
        source.setCancelHandler {
            Darwin.close(clientFD)
        }
        clients[clientFD] = Client(source: source, buffer: Data())
        source.resume()
        onConnect?(clientFD)
    }

    private func readClient(_ fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(fd, &chunk, chunk.count)
        if n <= 0 {
            closeClient(fd)
            return
        }
        guard var client = clients[fd] else { return }
        client.buffer.append(contentsOf: chunk.prefix(n))
        clients[fd] = client
        while let line = pullLine(from: fd) {
            guard let object = HandoffIPC.decode(line) else { continue }
            if object["method"] == nil { continue }
            onRequest(object) { [weak self] response in
                self?.send(response, to: fd)
            }
        }
    }

    private func pullLine(from fd: Int32) -> Data? {
        guard var client = clients[fd],
              let newline = client.buffer.firstIndex(of: 0x0A) else { return nil }
        let line = client.buffer.subdata(in: client.buffer.startIndex..<newline)
        client.buffer.removeSubrange(client.buffer.startIndex...newline)
        clients[fd] = client
        return line
    }

    private func closeClient(_ fd: Int32) {
        clients[fd]?.source.cancel()
        clients.removeValue(forKey: fd)
    }
}

final class HandoffIPCClient: @unchecked Sendable {
    private let path: String
    private let queue = DispatchQueue(label: "local.agenthq.handoff.client")
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: Pending] = [:]

    var onRoster: ([HandoffRosterEntry]) -> Void = { _ in }

    private struct Pending {
        var semaphore: DispatchSemaphore
        var response: [String: Any]?
    }

    init(path: String) {
        self.path = path
    }

    func start() {
        queue.async { [weak self] in
            _ = try? self?.ensureConnected()
        }
    }

    func stop() {
        queue.sync { disconnect() }
    }

    func request(method: String, params: [String: Any] = [:], timeout: TimeInterval) throws -> [String: Any] {
        lock.lock()
        let id = nextID
        nextID += 1
        lock.unlock()
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        pending[id] = Pending(semaphore: semaphore, response: nil)
        lock.unlock()
        try queue.sync {
            try ensureConnected()
            var payload: [String: Any] = ["id": id, "method": method]
            if !params.isEmpty {
                payload["params"] = params
            }
            guard let data = HandoffIPC.encode(payload) else { throw HandoffIPCError.disconnected }
            try HandoffIPC.writeAll(fd, data)
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            lock.lock()
            pending.removeValue(forKey: id)
            lock.unlock()
            throw HandoffIPCError.timeout
        }
        lock.lock()
        let response = pending.removeValue(forKey: id)?.response
        lock.unlock()
        guard let response else { throw HandoffIPCError.disconnected }
        return response
    }

    private func ensureConnected() throws {
        if fd >= 0 { return }
        var lastError: Error = HandoffIPCError.connectFailed
        for _ in 0..<20 {
            do {
                try connectOnce()
                return
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        throw lastError
    }

    private func connectOnce() throws {
        let clientFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard clientFD >= 0 else { throw HandoffIPCError.connectFailed }
        HandoffIPC.setNoSigPipe(clientFD)
        do {
            try HandoffIPC.connectUnix(clientFD, path: path)
        } catch {
            Darwin.close(clientFD)
            throw HandoffIPCError.connectFailed
        }
        fd = clientFD
        buffer = Data()
        let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        source.setCancelHandler {
            Darwin.close(clientFD)
        }
        self.source = source
        source.resume()
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(fd, &chunk, chunk.count)
        if n <= 0 {
            failAll()
            disconnect()
            return
        }
        buffer.append(contentsOf: chunk.prefix(n))
        while let line = pullLine() {
            guard let object = HandoffIPC.decode(line) else { continue }
            if let id = HandoffIPC.jsonID(object["id"]) {
                lock.lock()
                if var pending = self.pending[id] {
                    pending.response = object
                    self.pending[id] = pending
                    pending.semaphore.signal()
                }
                lock.unlock()
            } else if object["method"] as? String == "roster" {
                let agents = (object["agents"] as? [Any] ?? []).compactMap(HandoffRosterEntry.fromJSON)
                onRoster(agents)
            }
        }
    }

    private func pullLine() -> Data? {
        guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
        let line = buffer.subdata(in: buffer.startIndex..<newline)
        buffer.removeSubrange(buffer.startIndex...newline)
        return line
    }

    private func failAll() {
        lock.lock()
        for key in pending.keys {
            pending[key]?.semaphore.signal()
        }
        lock.unlock()
    }

    private func disconnect() {
        source?.cancel()
        source = nil
        fd = -1
        buffer = Data()
    }
}

