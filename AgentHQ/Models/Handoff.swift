import Foundation
import SwiftData

@Model
final class HandoffRecord {
    @Attribute(.unique) var id: UUID
    var fromAgentId: UUID
    var toAgentId: UUID
    var brief: String
    var status: String
    var resultSummary: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        fromAgentId: UUID,
        toAgentId: UUID,
        brief: String,
        status: String = "pending",
        resultSummary: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fromAgentId = fromAgentId
        self.toAgentId = toAgentId
        self.brief = brief
        self.status = status
        self.resultSummary = resultSummary
        self.createdAt = createdAt
    }
}
