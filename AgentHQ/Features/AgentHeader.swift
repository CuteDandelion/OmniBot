import SwiftData
import SwiftUI

struct AgentHeader: View {
    @Bindable var agent: Agent
    @State private var showingMascotPicker = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                showingMascotPicker.toggle()
            } label: {
                MascotView(kind: agent.mascot, state: .idle, size: 40)
            }
            .buttonStyle(.plain)
            .help("Change mascot")
            .accessibilityIdentifier("header-mascot")
            .popover(isPresented: $showingMascotPicker, arrowEdge: .bottom) {
                MascotPicker(selection: $agent.mascot)
                    .padding(12)
                    .frame(width: 264)
                    .background(Tokens.subtle)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(agent.name)
                        .font(Tokens.body.weight(.semibold))
                        .foregroundStyle(Tokens.fg)
                    Text(" · ")
                        .font(Tokens.body)
                        .foregroundStyle(Tokens.muted)
                    Text(agent.displayRole)
                        .font(Tokens.body)
                        .foregroundStyle(Tokens.muted)
                }
                .lineLimit(1)

                Button {
                    if let path = WorkspaceFolder.choose(currentPath: agent.workspacePath) {
                        agent.workspacePath = path
                    }
                } label: {
                    Text(agent.displayWorkspacePath)
                        .font(Tokens.caption)
                        .foregroundStyle(Tokens.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Change workspace folder")
                .accessibilityIdentifier("header-workspace")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Tokens.canvas)
    }
}
