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
            ZStack(alignment: .top) {
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

                if session.isReconnecting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting to Codex…")
                            .font(Tokens.caption)
                            .foregroundStyle(Tokens.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Tokens.subtle.opacity(0.95))
                    .overlay(alignment: .bottom) {
                        Tokens.border.frame(height: 1)
                    }
                    .accessibilityIdentifier("reconnecting-indicator")
                    .allowsHitTesting(false)
                }
            }
        } else {
            EmptyStateView()
        }
    }
}
