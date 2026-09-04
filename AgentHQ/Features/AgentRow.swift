import SwiftUI

struct AgentRow: View {
    var agent: Agent
    @EnvironmentObject private var session: AppSession

    private var status: MascotState {
        session.mascotState(for: agent.id)
    }

    var body: some View {
        HStack(spacing: 8) {
            MascotView(kind: agent.mascot, state: status, size: 32)
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
            StatusPip(state: status)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agent.name), \(agent.displayRole), \(status.statusLabel)")
    }
}

struct StatusPip: View {
    var state: MascotState
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(state.pipColor)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
