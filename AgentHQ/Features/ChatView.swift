import SwiftData
import SwiftUI

struct ChatView: View {
    var selectedAgentID: UUID?
    @Query private var agents: [Agent]

    private var selectedAgent: Agent? {
        guard let selectedAgentID else { return nil }
        return agents.first { $0.id == selectedAgentID }
    }

    var body: some View {
        if let agent = selectedAgent {
            VStack(spacing: 0) {
                AgentHeader(agent: agent)
                Divider()
                    .overlay(Tokens.border)
                Tokens.canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Tokens.canvas)
        } else {
            EmptyStateView()
        }
    }
}
