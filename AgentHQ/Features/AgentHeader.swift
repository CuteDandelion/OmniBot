import SwiftData
import SwiftUI

struct AgentHeader: View {
    @Bindable var agent: Agent
    @EnvironmentObject private var session: AppSession
    @Environment(\.modelContext) private var modelContext
    @State private var showingMascotPicker = false
    @State private var showingSystemMessage = false
    @State private var draftSystemMessage = ""
    @State private var saveError: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                showingMascotPicker.toggle()
            } label: {
                MascotView(kind: agent.mascot, state: session.mascotState(for: agent.id), size: 40)
            }
            .buttonStyle(.plain)
            .help("Change mascot")
            .accessibilityIdentifier("header-mascot")
            .popover(isPresented: $showingMascotPicker, arrowEdge: .bottom) {
                MascotPicker(selection: $agent.mascot) { _ in
                    persist()
                }
                .padding(12)
                .fixedSize()
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
                        Task {
                            await session.changeWorkspace(for: agent, to: path)
                            persist()
                        }
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

            Button {
                draftSystemMessage = agent.resolvedDeveloperInstructions
                showingSystemMessage.toggle()
            } label: {
                Image(systemName: "text.alignleft")
                    .font(Tokens.body)
                    .foregroundStyle(Tokens.muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit system message")
            .accessibilityIdentifier("header-system-message")
            .popover(isPresented: $showingSystemMessage, arrowEdge: .bottom) {
                systemMessageEditor
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Tokens.canvas)
        .alert("Couldn’t save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var systemMessageEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System message")
                .font(Tokens.body.weight(.semibold))
                .foregroundStyle(Tokens.fg)
            Text("Sent to Codex as developer instructions. Saving a change starts a new thread.")
                .font(Tokens.caption)
                .foregroundStyle(Tokens.muted)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Role instructions for Codex…", text: $draftSystemMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Tokens.body)
                .foregroundStyle(Tokens.fg)
                .lineLimit(6...12)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Tokens.canvas)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.cardRadius)
                        .stroke(Tokens.border, lineWidth: 1)
                )
                .accessibilityIdentifier("header-system-message-field")

            HStack {
                Spacer()
                Button("Cancel") { showingSystemMessage = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveSystemMessage() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("header-system-message-save")
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(Tokens.subtle)
    }

    private func saveSystemMessage() {
        let draft = draftSystemMessage
        showingSystemMessage = false
        Task {
            await session.updateDeveloperInstructions(for: agent, to: draft)
            persist()
        }
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
