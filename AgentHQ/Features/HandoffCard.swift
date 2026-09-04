import SwiftData
import SwiftUI

struct HandoffCard: View {
    var record: HandoffRecord
    var viewerAgentID: UUID

    @Query private var agents: [Agent]
    @EnvironmentObject private var session: AppSession

    private var isOutbound: Bool {
        record.fromAgentId == viewerAgentID
    }

    private var counterpart: Agent? {
        let id = isOutbound ? record.toAgentId : record.fromAgentId
        return agents.first { $0.id == id }
    }

    private var mascotState: MascotState {
        switch record.status {
        case "done", "failed":
            return .idle
        default:
            return isOutbound ? .waiting : .working
        }
    }

    private var statusText: String {
        switch record.status {
        case "done": return "done"
        case "failed": return "failed"
        default: return isOutbound ? "waiting" : "working"
        }
    }

    private var title: String {
        let name = counterpart?.name ?? "Agent"
        let role = counterpart?.displayRole ?? ""
        if isOutbound {
            return "→ \(name) · \(role)"
        }
        return "From \(name) · \(role)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MascotView(
                kind: counterpart?.mascot ?? .fox,
                state: mascotState,
                size: 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Tokens.body.weight(.semibold))
                    .foregroundStyle(Tokens.fg)
                    .lineLimit(1)
                Text(record.brief)
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(statusText)
                    .font(Tokens.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer(minLength: 0)
            Button("Open") {
                if let counterpart {
                    session.selectAgent(counterpart.id)
                }
            }
            .font(Tokens.body)
            .accessibilityIdentifier("handoff-open")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.subtle)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cardRadius)
                .stroke(Tokens.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("handoff-card")
    }

    private var statusColor: Color {
        switch record.status {
        case "done": return Tokens.accent
        case "failed": return Tokens.danger
        default: return isOutbound ? Tokens.attention : Tokens.accent
        }
    }
}

#Preview("Handoff waiting") {
    let record = HandoffRecord(
        fromAgentId: UUID(),
        toAgentId: UUID(),
        brief: "List the top-level files",
        status: "running"
    )
    return HandoffCard(record: record, viewerAgentID: record.fromAgentId)
        .environmentObject(AppSession())
        .modelContainer(for: [Agent.self, HandoffRecord.self], inMemory: true)
        .padding()
        .background(Tokens.canvas)
}
