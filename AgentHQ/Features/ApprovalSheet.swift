import CodexClient
import SwiftData
import SwiftUI

struct ApprovalSheet: View {
    @EnvironmentObject private var session: AppSession
    @Query private var agents: [Agent]

    var body: some View {
        if let pending = session.pendingApproval {
            content(for: pending)
        }
    }

    private func content(for pending: PendingApproval) -> some View {
        let agent = agents.first { $0.id == pending.agentID }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                MascotView(
                    kind: agent?.mascot ?? .fox,
                    state: .needsApproval,
                    size: 40
                )
                .accessibilityIdentifier("approval-mascot")

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent?.name ?? "Agent")
                        .font(Tokens.body.weight(.semibold))
                        .foregroundStyle(Tokens.fg)
                        .accessibilityIdentifier("approval-agent-name")
                    Text("wants to run a command")
                        .font(Tokens.caption)
                        .foregroundStyle(Tokens.muted)
                }
            }

            if let reason = pending.reason, !reason.isEmpty {
                Text(reason)
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("approval-reason")
            }

            Text(pending.command)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Tokens.fg)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tokens.canvas)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.cardRadius)
                        .stroke(Tokens.border, lineWidth: 1)
                )
                .accessibilityIdentifier("approval-command")

            HStack(spacing: 8) {
                Button("Deny", role: .destructive) {
                    Task { await session.respondToPendingApproval(.decline) }
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("approval-deny")

                Spacer(minLength: 0)

                Button("Allow always") {
                    Task { await session.respondToPendingApproval(.acceptForSession) }
                }
                .accessibilityIdentifier("approval-allow-always")

                Button("Allow") {
                    Task { await session.respondToPendingApproval(.accept) }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("approval-allow")
            }
            .font(Tokens.body)
            .disabled(session.isRespondingToApproval)
            .id(pending.requestId)
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 420)
        .background(Tokens.subtle)
        .accessibilityIdentifier("approval-sheet")
        .id(pending.requestId)
    }
}
