import SwiftUI

struct AgentRow: View {
    var agent: Agent
    @EnvironmentObject private var session: AppSession

    var body: some View {
        HStack(spacing: 8) {
            MascotView(kind: agent.mascot, state: session.mascotState(for: agent.id), size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                    .font(Tokens.body)
                    .foregroundStyle(Tokens.fg)
                    .lineLimit(1)
                Text(agent.displayRole)
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agent.name), \(agent.displayRole)")
    }
}
