import SwiftData
import SwiftUI

struct ChatView: View {
    var selectedAgentID: UUID?
    @EnvironmentObject private var session: AppSession
    @Query private var agents: [Agent]

    private var selectedAgent: Agent? {
        guard let selectedAgentID else { return nil }
        return agents.first { $0.id == selectedAgentID }
    }

    var body: some View {
        if session.showsSetupEmptyState {
            EmptyStateView()
        } else if let agent = selectedAgent {
            VStack(spacing: 0) {
                AgentHeader(agent: agent)
                Divider()
                    .overlay(Tokens.border)
                Tokens.canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                    .overlay(Tokens.border)
                ComposerView(agent: agent)
            }
            .background(Tokens.canvas)
        } else {
            EmptyStateView()
        }
    }
}
