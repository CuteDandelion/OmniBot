import Foundation
import SwiftData

enum HandoffError: Error, Equatable, LocalizedError {
    case unknownAgent
    case cycle
    case alreadyPending
    case interrupted
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unknownAgent:
            return "Unknown agent"
        case .cycle:
            return "Handoff cycle rejected"
        case .alreadyPending:
            return "Agent already has an in-flight handoff"
        case .interrupted:
            return "Handoff interrupted"
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class HandoffOrchestrator {
    private let modelContext: ModelContext
    private var waiters: [UUID: CheckedContinuation<String, Error>] = [:]

    var runTarget: ((HandoffRecord, Agent, Agent) async throws -> String)?
    var onEvent: ((HandoffRecord) -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func handoff(from: UUID, to: UUID, brief: String) async throws -> String {
        let record = try begin(from: from, to: to, brief: brief)
        onEvent?(record)
        return try await withCheckedThrowingContinuation { continuation in
            waiters[record.id] = continuation
            Task { @MainActor in
                do {
                    let summary = try await self.execute(record)
                    self.complete(record, summary: summary)
                } catch {
                    self.fail(record, error: error)
                }
            }
        }
    }

    @discardableResult
    func failInvolving(_ agentID: UUID) -> [HandoffRecord] {
        let matches = inFlightRecords().filter { $0.fromAgentId == agentID || $0.toAgentId == agentID }
        for record in matches {
            fail(record, error: HandoffError.interrupted)
        }
        return matches
    }

    func failAll() {
        for record in inFlightRecords() {
            fail(record, error: HandoffError.interrupted)
        }
    }

    func inFlightRecords() -> [HandoffRecord] {
        let all = (try? modelContext.fetch(FetchDescriptor<HandoffRecord>())) ?? []
        return all.filter { $0.status == "pending" || $0.status == "running" }
    }

    private func begin(from: UUID, to: UUID, brief: String) throws -> HandoffRecord {
        guard from != to else { throw HandoffError.cycle }
        guard agent(id: from) != nil, agent(id: to) != nil else { throw HandoffError.unknownAgent }

        let inflight = inFlightRecords()
        if inflight.contains(where: { $0.fromAgentId == from }) {
            throw HandoffError.alreadyPending
        }
        if wouldCycle(from: from, to: to, inflight: inflight) {
            throw HandoffError.cycle
        }

        let record = HandoffRecord(fromAgentId: from, toAgentId: to, brief: brief, status: "pending")
        modelContext.insert(record)
        persist()
        return record
    }

    private func execute(_ record: HandoffRecord) async throws -> String {
        guard let fromAgent = agent(id: record.fromAgentId),
              let toAgent = agent(id: record.toAgentId) else {
            throw HandoffError.unknownAgent
        }
        record.status = "running"
        persist()
        onEvent?(record)
        guard let runTarget else {
            throw HandoffError.failed("Handoff runner unavailable")
        }
        return try await runTarget(record, fromAgent, toAgent)
    }

    private func complete(_ record: HandoffRecord, summary: String) {
        guard let waiter = waiters.removeValue(forKey: record.id) else { return }
        record.status = "done"
        record.resultSummary = summary
        persist()
        onEvent?(record)
        waiter.resume(returning: summary)
    }

    private func fail(_ record: HandoffRecord, error: Error) {
        guard let waiter = waiters.removeValue(forKey: record.id) else { return }
        record.status = "failed"
        record.resultSummary = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        persist()
        onEvent?(record)
        waiter.resume(throwing: error)
    }

    private func wouldCycle(from: UUID, to: UUID, inflight: [HandoffRecord]) -> Bool {
        var cursor = to
        var seen = Set<UUID>()
        while let next = inflight.first(where: { $0.fromAgentId == cursor }) {
            if next.toAgentId == from { return true }
            if !seen.insert(cursor).inserted { return true }
            cursor = next.toAgentId
        }
        return false
    }

    private func agent(id: UUID) -> Agent? {
        let all = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
        return all.first { $0.id == id }
    }

    private func persist() {
        try? modelContext.save()
    }
}
