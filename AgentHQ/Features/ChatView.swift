import CodexClient
import SwiftData
import SwiftUI

struct ChatView: View {
    var selectedAgentID: UUID?
    @EnvironmentObject private var session: AppSession
    @Query private var agents: [Agent]

    @Environment(\.modelContext) private var modelContext

    private var selectedAgent: Agent? {
        guard let selectedAgentID else { return nil }
        return agents.first { $0.id == selectedAgentID }
    }

    private func threadTaskID(for agent: Agent) -> String {
        "\(agent.id.uuidString)-\(session.connectionState == .ready ? "ready" : "wait")"
    }

    private func chatBanner(_ text: String, identifier: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(Tokens.caption)
                .foregroundStyle(Tokens.attention)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Tokens.subtle)
        .overlay(alignment: .bottom) {
            Tokens.border.frame(height: 1)
        }
        .accessibilityIdentifier(identifier)
    }

    private func approvalBanner(_ pending: PendingApproval) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Approval needed: \(pending.command)")
                .font(Tokens.caption)
                .foregroundStyle(Tokens.attention)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Allow") {
                Task { await session.respondToPendingApproval(.accept) }
            }
            .font(Tokens.caption)
            .accessibilityIdentifier("approval-allow")
            Button("Deny") {
                Task { await session.respondToPendingApproval(.decline) }
            }
            .font(Tokens.caption)
            .accessibilityIdentifier("approval-deny")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Tokens.subtle)
        .overlay(alignment: .bottom) {
            Tokens.border.frame(height: 1)
        }
        .accessibilityIdentifier("approval-placeholder")
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
                    if let warning = session.workspaceWarning {
                        chatBanner(warning, identifier: "workspace-missing-banner")
                    }
                    if let pending = session.pendingApproval {
                        approvalBanner(pending)
                    }
                    TranscriptView(items: session.items)
                    Divider()
                        .overlay(Tokens.border)
                    ComposerView(agent: agent)
                }
                .background(Tokens.canvas)
                .task(id: threadTaskID(for: agent)) {
                    guard session.connectionState == .ready else { return }
                    await session.ensureThread(for: agent)
                    try? modelContext.save()
                    if let prompt = ProcessInfo.processInfo.environment["AGENTHQ_CHAT_PROMPT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !prompt.isEmpty,
                       agent.threadId != nil,
                       session.items.isEmpty {
                        await session.send(prompt, from: agent)
                    }
                }

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
